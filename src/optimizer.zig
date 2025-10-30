const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

const types = @import("types.zig");
const ImageBuffer = types.ImageBuffer;
const ImageMetadata = types.ImageMetadata;
const ImageFormat = types.ImageFormat;
const MetricType = types.MetricType;
const TransformParams = @import("types/transform_params.zig").TransformParams;
const image_ops = @import("image_ops.zig");
const codecs = @import("codecs.zig");
const search = @import("search.zig");
const metrics = @import("metrics.zig");

/// Represents a single encoded candidate result
pub const EncodedCandidate = struct {
    format: ImageFormat,
    encoded_bytes: []u8, // Owned by this struct
    file_size: u32,
    quality: u8,
    diff_score: f64, // Stubbed to 0.0 for MVP, real metric in 0.2.0
    passed_constraints: bool,
    encoding_time_ns: u64,

    pub fn deinit(self: *EncodedCandidate, allocator: Allocator) void {
        allocator.free(self.encoded_bytes);
    }
};

/// Input parameters for image optimization
pub const OptimizationJob = struct {
    input_path: []const u8,
    output_path: []const u8,
    max_bytes: ?u32, // null = no size constraint
    max_diff: ?f64, // null = no quality constraint
    metric_type: MetricType, // Perceptual metric to use (v0.3.0)
    formats: []const ImageFormat, // Formats to try
    transform_params: TransformParams,
    concurrency: u8, // Max parallel encoding tasks
    parallel_encoding: bool, // Enable parallel encoding (default: true in 0.2.0)

    /// Create a basic job with sensible defaults
    pub fn init(input_path: []const u8, output_path: []const u8) OptimizationJob {
        return .{
            .input_path = input_path,
            .output_path = output_path,
            .max_bytes = null,
            .max_diff = null,
            .metric_type = .none, // MVP: No perceptual checking by default
            .formats = &[_]ImageFormat{ .avif, .webp, .jpeg, .png }, // v0.3.0: All 4 formats, prefer modern
            .transform_params = TransformParams.init(),
            .concurrency = 4,
            .parallel_encoding = true, // v0.2.0: Enable by default
        };
    }
};

/// Timing breakdown for optimization pipeline
pub const OptimizationTimings = struct {
    decode_ns: u64,
    encode_ns: u64,
    total_ns: u64,
};

/// Result of image optimization
pub const OptimizationResult = struct {
    selected: ?EncodedCandidate, // null if no candidate passed constraints
    all_candidates: []EncodedCandidate, // All attempted candidates
    timings: OptimizationTimings,
    warnings: [][]const u8, // Owned warning strings
    success: bool,

    pub fn deinit(self: *OptimizationResult, allocator: Allocator) void {
        // Free selected candidate if present
        if (self.selected) |*selected| {
            selected.deinit(allocator);
        }

        // Free all candidates
        for (self.all_candidates) |*candidate| {
            candidate.deinit(allocator);
        }
        allocator.free(self.all_candidates);

        // Free warnings
        for (self.warnings) |warning| {
            allocator.free(warning);
        }
        allocator.free(self.warnings);
    }
};

/// Main optimization function - orchestrates the entire pipeline
///
/// Steps:
/// 1. Decode and normalize input image
/// 2. Generate candidates in parallel (one per format)
/// 3. Score candidates (stubbed for MVP)
/// 4. Select best passing candidate
/// 5. Return detailed result
///
/// Tiger Style:
/// - Bounded parallelism (job.concurrency)
/// - Explicit error handling
/// - Each step bounded to avoid infinite loops
pub fn optimizeImage(
    allocator: Allocator,
    job: OptimizationJob,
) !OptimizationResult {
    // Validate inputs
    std.debug.assert(job.formats.len > 0);
    std.debug.assert(job.concurrency > 0);
    std.debug.assert(job.input_path.len > 0);
    std.debug.assert(job.output_path.len > 0);

    const start_time = std.time.nanoTimestamp();
    var warnings = ArrayList([]u8){};
    errdefer {
        for (warnings.items) |warning| allocator.free(warning);
        warnings.deinit(allocator);
    }

    // Step 1: Decode and normalize
    const decode_start = std.time.nanoTimestamp();
    var buffer = try image_ops.decodeImage(allocator, job.input_path);
    errdefer buffer.deinit();
    const decode_time = @as(u64, @intCast(std.time.nanoTimestamp() - decode_start));

    // Step 2: Generate candidates (parallel in v0.2.0)
    const encode_start = std.time.nanoTimestamp();
    var candidates = try generateCandidates(
        allocator,
        &buffer,
        job.formats,
        job.max_bytes,
        job.concurrency,
        job.parallel_encoding, // v0.2.0: Feature flag
        &warnings,
    );
    errdefer {
        for (candidates.items) |*candidate| candidate.deinit(allocator);
        candidates.deinit(allocator);
    }
    const encode_time = @as(u64, @intCast(std.time.nanoTimestamp() - encode_start));

    buffer.deinit(); // No longer needed

    // Step 2.5: Add original file as baseline candidate
    // This ensures we never make files larger - original can be selected if smallest
    // DEBUG: Added extensive logging to diagnose size regression failures
    const original_bytes = blk: {
        const file = try std.fs.cwd().openFile(job.input_path, .{});
        defer file.close();
        const stat = try file.stat();
        break :blk try file.readToEndAlloc(allocator, stat.size);
    };
    errdefer allocator.free(original_bytes);

    // Get original format with graceful fallback
    const original_format = image_ops.getImageMetadata(job.input_path) catch |err| blk: {
        std.log.warn("Failed to get original metadata: {}, attempting format detection from bytes", .{err});

        // Attempt to detect format from file magic numbers
        const detected_format = if (original_bytes.len >= 4) detect_blk: {
            // JPEG: FF D8 FF
            if (original_bytes[0] == 0xFF and original_bytes[1] == 0xD8) {
                break :detect_blk ImageFormat.jpeg;
            }
            // PNG: 89 50 4E 47
            if (original_bytes[0] == 0x89 and original_bytes[1] == 0x50 and
                original_bytes[2] == 0x4E and original_bytes[3] == 0x47) {
                break :detect_blk ImageFormat.png;
            }
            // WebP: RIFF ... WEBP
            if (original_bytes.len >= 12 and
                original_bytes[0] == 0x52 and original_bytes[1] == 0x49 and
                original_bytes[8] == 0x57 and original_bytes[9] == 0x45) {
                break :detect_blk ImageFormat.webp;
            }
            // AVIF: ftyp
            if (original_bytes.len >= 12 and
                original_bytes[4] == 0x66 and original_bytes[5] == 0x74) {
                break :detect_blk ImageFormat.avif;
            }
            break :detect_blk ImageFormat.unknown;
        } else ImageFormat.unknown;

        std.log.warn("Detected format from magic numbers: {s}", .{@tagName(detected_format)});

        break :blk ImageMetadata{
            .format = detected_format,
            .original_width = 0,  // Unknown dimensions
            .original_height = 0,
            .has_alpha = false,   // Unknown
            .exif_orientation = .normal,
            .icc_profile = null,
            .allocator = null,
        };
    };

    const passed_constraints = if (job.max_bytes) |max| original_bytes.len <= max else true;

    const original_candidate = EncodedCandidate{
        .format = original_format.format,
        .encoded_bytes = original_bytes,
        .file_size = @intCast(original_bytes.len),
        .quality = 100, // Original quality
        .diff_score = 0.0, // Perfect match to original
        .passed_constraints = passed_constraints,
        .encoding_time_ns = 0, // No encoding needed
    };

    // DEBUG: Log original candidate details
    std.log.debug("Adding original file as baseline candidate:", .{});
    std.log.debug("  Format: {s}", .{@tagName(original_candidate.format)});
    std.log.debug("  Size: {d} bytes", .{original_candidate.file_size});
    std.log.debug("  Quality: {d}", .{original_candidate.quality});
    std.log.debug("  Passed constraints: {}", .{original_candidate.passed_constraints});
    std.log.debug("  Max bytes constraint: {?d}", .{job.max_bytes});

    try candidates.append(allocator, original_candidate);
    // Note: original_bytes now owned by candidates list, errdefer above no longer applies

    // Step 3: Score candidates (stubbed - all get diff_score = 0.0)
    // In 0.2.0 this will compute Butteraugli/DSSIM

    // Step 4: Select best candidate
    const selected = try selectBestCandidate(
        allocator,
        candidates.items,
        job.max_bytes,
        job.max_diff,
    );

    const total_time = @as(u64, @intCast(std.time.nanoTimestamp() - start_time));

    return .{
        .selected = selected,
        .all_candidates = try candidates.toOwnedSlice(allocator),
        .timings = .{
            .decode_ns = decode_time,
            .encode_ns = encode_time,
            .total_ns = total_time,
        },
        .warnings = @ptrCast(try warnings.toOwnedSlice(allocator)),
        .success = selected != null,
    };
}

/// Generate encoding candidates for all requested formats
///
/// v0.2.0: Supports both sequential and parallel modes
///
/// Tiger Style:
/// - Bounded loop (iterates exactly formats.len times)
/// - Bounded parallelism (respects max_workers)
/// - Handles encoder errors gracefully (logs, continues)
fn generateCandidates(
    allocator: Allocator,
    buffer: *const ImageBuffer,
    formats: []const ImageFormat,
    max_bytes: ?u32,
    max_workers: u8,
    parallel: bool,
    warnings: *ArrayList([]u8),
) !ArrayList(EncodedCandidate) {
    std.debug.assert(formats.len > 0);
    std.debug.assert(max_workers > 0);

    // v0.2.0: Use parallel encoding if enabled and beneficial
    // Parallel makes sense when: multiple formats AND multiple workers
    const use_parallel = parallel and formats.len > 1 and max_workers > 1;

    if (use_parallel) {
        return generateCandidatesParallel(
            allocator,
            buffer,
            formats,
            max_bytes,
            max_workers,
            warnings,
        );
    } else {
        return generateCandidatesSequential(
            allocator,
            buffer,
            formats,
            max_bytes,
            warnings,
        );
    }
}

/// Sequential candidate generation (MVP implementation, also fallback for parallel)
///
/// Tiger Style: Bounded loop with explicit MAX constant
fn generateCandidatesSequential(
    allocator: Allocator,
    buffer: *const ImageBuffer,
    formats: []const ImageFormat,
    max_bytes: ?u32,
    warnings: *ArrayList([]u8),
) !ArrayList(EncodedCandidate) {
    // Tiger Style: Explicit MAX constant for bounded loops
    const MAX_FORMATS: u8 = 10; // Reasonable upper limit for format count
    std.debug.assert(formats.len > 0);
    std.debug.assert(formats.len <= MAX_FORMATS); // Pre-condition

    var candidates = ArrayList(EncodedCandidate){};
    errdefer {
        for (candidates.items) |*candidate| candidate.deinit(allocator);
        candidates.deinit(allocator);
    }

    // Sequential encoding (bounded by MAX_FORMATS)
    for (formats, 0..) |format, i| {
        std.debug.assert(i < MAX_FORMATS); // Loop invariant

        const candidate = encodeCandidateForFormat(
            allocator,
            buffer,
            format,
            max_bytes,
        ) catch |err| {
            // Log error and continue with other formats
            const warning = try std.fmt.allocPrint(
                allocator,
                "Failed to encode {s}: {}",
                .{ @tagName(format), err },
            );
            try warnings.append(allocator, warning);
            continue;
        };
        try candidates.append(allocator, candidate);
    }

    // Post-condition: Verify bounded execution
    std.debug.assert(candidates.items.len <= MAX_FORMATS);

    return candidates;
}

/// Parallel candidate generation (v0.2.0)
///
/// Uses thread pool to encode multiple formats simultaneously.
/// Expected speedup: 2-4x on multi-core systems.
///
/// Tiger Style:
/// - Bounded parallelism: num_threads = min(formats.len, max_workers)
/// - Per-thread memory isolation: Each thread uses arena allocator
/// - Explicit error handling: Thread errors captured, don't crash main
/// - Explicit MAX constant: Bounded by MAX_FORMATS
fn generateCandidatesParallel(
    allocator: Allocator,
    buffer: *const ImageBuffer,
    formats: []const ImageFormat,
    max_bytes: ?u32,
    max_workers: u8,
    warnings: *ArrayList([]u8),
) !ArrayList(EncodedCandidate) {
    // Tiger Style: Explicit MAX constant for bounded loops
    const MAX_FORMATS: u8 = 10; // Reasonable upper limit for format count

    std.debug.assert(formats.len > 0);
    std.debug.assert(formats.len <= MAX_FORMATS); // Pre-condition
    std.debug.assert(max_workers > 0);
    std.debug.assert(buffer.width > 0);
    std.debug.assert(buffer.height > 0);

    var candidates = ArrayList(EncodedCandidate){};
    errdefer {
        for (candidates.items) |*candidate| candidate.deinit(allocator);
        candidates.deinit(allocator);
    }

    // Bounded parallelism
    const num_threads: u8 = @min(@as(u8, @intCast(formats.len)), max_workers);
    std.debug.assert(num_threads <= max_workers);
    std.debug.assert(num_threads <= formats.len);
    std.debug.assert(num_threads <= MAX_FORMATS); // Additional bound check

    // Allocate thread contexts
    const ThreadContext = struct {
        parent_allocator: Allocator,
        buffer: *const ImageBuffer,
        format: ImageFormat,
        max_bytes: ?u32,
        result: ?EncodedCandidate,
        error_msg: ?[]u8,

        fn worker(ctx: *@This()) void {
            // Per-thread arena allocator (memory isolation)
            var arena = std.heap.ArenaAllocator.init(ctx.parent_allocator);
            defer arena.deinit();
            const thread_alloc = arena.allocator();

            // Encode candidate
            const candidate = encodeCandidateForFormat(
                thread_alloc,
                ctx.buffer,
                ctx.format,
                ctx.max_bytes,
            ) catch |err| {
                // Capture error
                ctx.error_msg = ctx.parent_allocator.dupe(
                    u8,
                    @errorName(err),
                ) catch null;
                ctx.result = null;
                return;
            };

            // Clone to parent allocator (arena will be freed)
            ctx.result = cloneCandidate(ctx.parent_allocator, candidate) catch {
                ctx.result = null;
                return;
            };
        }
    };

    const contexts = try allocator.alloc(ThreadContext, num_threads);
    defer allocator.free(contexts);

    const threads = try allocator.alloc(std.Thread, num_threads);
    defer allocator.free(threads);

    // Initialize contexts and spawn threads
    for (contexts, threads, 0..) |*ctx, *thread, i| {
        ctx.* = .{
            .parent_allocator = allocator,
            .buffer = buffer,
            .format = formats[i],
            .max_bytes = max_bytes,
            .result = null,
            .error_msg = null,
        };

        thread.* = try std.Thread.spawn(.{}, ThreadContext.worker, .{ctx});
    }

    // Wait for all threads and collect results (bounded by num_threads)
    for (threads, contexts, 0..) |thread, *ctx, i| {
        std.debug.assert(i < num_threads); // Loop invariant

        thread.join();

        if (ctx.result) |candidate| {
            try candidates.append(allocator, candidate);
        } else if (ctx.error_msg) |err_msg| {
            const warning = try std.fmt.allocPrint(
                allocator,
                "Failed to encode {s}: {s}",
                .{ @tagName(ctx.format), err_msg },
            );
            try warnings.append(allocator, warning);
            allocator.free(err_msg);
        }
    }

    // Post-condition: Verify bounded execution
    std.debug.assert(candidates.items.len <= num_threads);

    return candidates;
}

/// Clone an encoded candidate to a different allocator
///
/// Used by parallel encoding to transfer candidates from thread-local
/// arena allocators to the parent allocator.
///
/// Tiger Style: Comprehensive assertions verify deep clone correctness
fn cloneCandidate(
    allocator: Allocator,
    candidate: EncodedCandidate,
) !EncodedCandidate {
    // Pre-conditions: Validate input candidate
    std.debug.assert(candidate.encoded_bytes.len > 0);
    std.debug.assert(candidate.file_size > 0);
    std.debug.assert(candidate.file_size == candidate.encoded_bytes.len);
    std.debug.assert(candidate.quality <= 100);

    const cloned_bytes = try allocator.dupe(u8, candidate.encoded_bytes);

    const result = EncodedCandidate{
        .format = candidate.format,
        .encoded_bytes = cloned_bytes,
        .file_size = candidate.file_size,
        .quality = candidate.quality,
        .diff_score = candidate.diff_score,
        .passed_constraints = candidate.passed_constraints,
        .encoding_time_ns = candidate.encoding_time_ns,
    };

    // Post-conditions: Verify deep clone correctness
    std.debug.assert(result.format == candidate.format);
    std.debug.assert(result.file_size == candidate.file_size);
    std.debug.assert(result.quality == candidate.quality);
    std.debug.assert(result.encoded_bytes.len == candidate.encoded_bytes.len);
    std.debug.assert(result.encoded_bytes.ptr != candidate.encoded_bytes.ptr); // Different allocation
    std.debug.assert(result.diff_score == candidate.diff_score);
    std.debug.assert(result.passed_constraints == candidate.passed_constraints);

    return result;
}

/// Encode a single candidate for a specific format
///
/// Uses binary search to hit size target if max_bytes is specified,
/// otherwise uses default quality.
fn encodeCandidateForFormat(
    allocator: Allocator,
    buffer: *const ImageBuffer,
    format: ImageFormat,
    max_bytes: ?u32,
) !EncodedCandidate {
    const encode_start = std.time.nanoTimestamp();

    var encoded_bytes: []u8 = undefined;
    var quality: u8 = undefined;

    if (max_bytes) |target_bytes| {
        // Use binary search to hit target size
        const search_result = try search.binarySearchQuality(
            allocator,
            buffer.*,
            format,
            target_bytes,
            .{}, // Default search options
        );
        encoded_bytes = search_result.encoded;
        quality = search_result.quality;
    } else {
        // No size constraint - use default quality
        quality = codecs.getDefaultQuality(format);
        encoded_bytes = try codecs.encodeImage(allocator, buffer, format, quality);
    }

    const encode_time = @as(u64, @intCast(std.time.nanoTimestamp() - encode_start));
    const file_size: u32 = @intCast(encoded_bytes.len);

    // Check if constraints are met
    const passed = blk: {
        if (max_bytes) |limit| {
            if (file_size > limit) break :blk false;
        }
        // In 0.2.0: Also check max_diff constraint here
        break :blk true;
    };

    return .{
        .format = format,
        .encoded_bytes = encoded_bytes,
        .file_size = file_size,
        .quality = quality,
        .diff_score = 0.0, // Stubbed for MVP
        .passed_constraints = passed,
        .encoding_time_ns = encode_time,
    };
}

/// Select the best candidate that passes all constraints
///
/// Selection criteria:
/// 1. Must pass size constraint (bytes <= max_bytes)
/// 2. Must pass quality constraint (diff <= max_diff) [stubbed for MVP]
/// 3. Prefer smallest file size
/// 4. Tiebreak by format preference (AVIF > WebP > JPEG > PNG)
///
/// Returns null if no candidate passes constraints.
///
/// DEBUG: Added extensive logging to diagnose selection issues
fn selectBestCandidate(
    allocator: Allocator,
    candidates: []const EncodedCandidate,
    max_bytes: ?u32,
    max_diff: ?f64,
) !?EncodedCandidate {
    _ = max_diff; // Stubbed for MVP
    std.debug.assert(candidates.len > 0);

    // DEBUG: Log all candidates being considered
    std.log.debug("Selecting best candidate from {d} options:", .{candidates.len});
    std.log.debug("  Max bytes constraint: {?d}", .{max_bytes});

    var best: ?*const EncodedCandidate = null;

    // Tiger Style: Bounded loop (exactly candidates.len iterations)
    for (candidates, 0..) |*candidate, i| {
        // DEBUG: Log each candidate
        std.log.debug("  Candidate {d}: format={s}, size={d}, quality={d}, passed={}", .{
            i,
            @tagName(candidate.format),
            candidate.file_size,
            candidate.quality,
            candidate.passed_constraints,
        });

        // Filter: Check size constraint
        if (max_bytes) |limit| {
            if (candidate.file_size > limit) {
                std.log.debug("    Rejected: size {d} > limit {d}", .{ candidate.file_size, limit });
                continue;
            }
        }

        // Filter: Check diff constraint (stubbed for MVP)
        // In 0.2.0: if (max_diff) |limit| if (candidate.diff_score > limit) continue;

        // Select if first passing candidate or smaller than current best
        if (best == null or candidate.file_size < best.?.file_size) {
            std.log.debug("    Selected as new best (size: {d})", .{candidate.file_size});
            best = candidate;
        } else if (candidate.file_size == best.?.file_size) {
            // Tiebreak by format preference
            const cand_pref = formatPreference(candidate.format);
            const best_pref = formatPreference(best.?.format);
            if (cand_pref > best_pref) {
                std.log.debug("    Selected as new best (tiebreak: {d} > {d})", .{ cand_pref, best_pref });
                best = candidate;
            } else {
                std.log.debug("    Not selected (tiebreak: {d} <= {d})", .{ cand_pref, best_pref });
            }
        } else {
            std.log.debug("    Not selected (size {d} >= current best {d})", .{ candidate.file_size, best.?.file_size });
        }
    }

    if (best) |b| {
        // DEBUG: Log final selection
        std.log.debug("Final selection: format={s}, size={d}, quality={d}", .{
            @tagName(b.format),
            b.file_size,
            b.quality,
        });

        // Clone the best candidate for return
        const cloned_bytes = try allocator.dupe(u8, b.encoded_bytes);
        return .{
            .format = b.format,
            .encoded_bytes = cloned_bytes,
            .file_size = b.file_size,
            .quality = b.quality,
            .diff_score = b.diff_score,
            .passed_constraints = b.passed_constraints,
            .encoding_time_ns = b.encoding_time_ns,
        };
    }

    std.log.debug("No candidate selected (all failed constraints)", .{});
    return null;
}

/// Format preference for tiebreaking (higher = better)
fn formatPreference(format: ImageFormat) u8 {
    return switch (format) {
        .avif => 4, // Best compression, modern
        .webp => 3, // Good compression, wide support
        .jpeg => 2, // Universal support
        .png => 1, // Lossless but often larger
        .unknown => 0,
    };
}

// ============================================================================
// Unit Tests
// ============================================================================

const testing = std.testing;

test "EncodedCandidate: deinit frees memory" {
    var candidate = EncodedCandidate{
        .format = .jpeg,
        .encoded_bytes = try testing.allocator.alloc(u8, 100),
        .file_size = 100,
        .quality = 85,
        .diff_score = 0.0,
        .passed_constraints = true,
        .encoding_time_ns = 1000,
    };

    candidate.deinit(testing.allocator);
    // No leak if this test passes
}

test "OptimizationJob: init with defaults" {
    const job = OptimizationJob.init("input.jpg", "output.jpg");
    try testing.expectEqualStrings("input.jpg", job.input_path);
    try testing.expectEqualStrings("output.jpg", job.output_path);
    try testing.expectEqual(@as(?u32, null), job.max_bytes);
    try testing.expectEqual(@as(u8, 4), job.concurrency);
    try testing.expect(job.formats.len >= 2);
}

test "formatPreference: correct ordering" {
    try testing.expect(formatPreference(.avif) > formatPreference(.webp));
    try testing.expect(formatPreference(.webp) > formatPreference(.jpeg));
    try testing.expect(formatPreference(.jpeg) > formatPreference(.png));
    try testing.expect(formatPreference(.png) > formatPreference(.unknown));
}

test "selectBestCandidate: picks smallest passing candidate" {
    const candidates = [_]EncodedCandidate{
        .{
            .format = .jpeg,
            .encoded_bytes = try testing.allocator.alloc(u8, 1000),
            .file_size = 1000,
            .quality = 85,
            .diff_score = 0.0,
            .passed_constraints = true,
            .encoding_time_ns = 1000,
        },
        .{
            .format = .png,
            .encoded_bytes = try testing.allocator.alloc(u8, 800),
            .file_size = 800,
            .quality = 6,
            .diff_score = 0.0,
            .passed_constraints = true,
            .encoding_time_ns = 1200,
        },
    };
    defer {
        testing.allocator.free(candidates[0].encoded_bytes);
        testing.allocator.free(candidates[1].encoded_bytes);
    }

    const best = try selectBestCandidate(
        testing.allocator,
        &candidates,
        null,
        null,
    );

    try testing.expect(best != null);
    try testing.expectEqual(@as(u32, 800), best.?.file_size);
    try testing.expectEqual(ImageFormat.png, best.?.format);
}

test "selectBestCandidate: respects size constraint" {
    const candidates = [_]EncodedCandidate{
        .{
            .format = .jpeg,
            .encoded_bytes = try testing.allocator.alloc(u8, 1000),
            .file_size = 1000,
            .quality = 85,
            .diff_score = 0.0,
            .passed_constraints = false,
            .encoding_time_ns = 1000,
        },
        .{
            .format = .png,
            .encoded_bytes = try testing.allocator.alloc(u8, 1500),
            .file_size = 1500,
            .quality = 6,
            .diff_score = 0.0,
            .passed_constraints = false,
            .encoding_time_ns = 1200,
        },
    };
    defer {
        testing.allocator.free(candidates[0].encoded_bytes);
        testing.allocator.free(candidates[1].encoded_bytes);
    }

    // Max 900 bytes - both candidates too large
    const best = try selectBestCandidate(
        testing.allocator,
        &candidates,
        900,
        null,
    );

    try testing.expect(best == null);
}

test "selectBestCandidate: format tiebreak" {
    const candidates = [_]EncodedCandidate{
        .{
            .format = .png,
            .encoded_bytes = try testing.allocator.alloc(u8, 800),
            .file_size = 800,
            .quality = 6,
            .diff_score = 0.0,
            .passed_constraints = true,
            .encoding_time_ns = 1200,
        },
        .{
            .format = .webp,
            .encoded_bytes = try testing.allocator.alloc(u8, 800),
            .file_size = 800,
            .quality = 75,
            .diff_score = 0.0,
            .passed_constraints = true,
            .encoding_time_ns = 1000,
        },
    };
    defer {
        testing.allocator.free(candidates[0].encoded_bytes);
        testing.allocator.free(candidates[1].encoded_bytes);
    }

    const best = try selectBestCandidate(
        testing.allocator,
        &candidates,
        null,
        null,
    );

    try testing.expect(best != null);
    // WebP preferred over PNG at same size
    try testing.expectEqual(ImageFormat.webp, best.?.format);
}
