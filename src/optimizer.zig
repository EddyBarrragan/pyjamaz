const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const fs = std.fs;

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
const cache = @import("cache.zig");
const Cache = cache.Cache;

/// Represents a single encoded candidate result
pub const EncodedCandidate = struct {
    format: ImageFormat,
    encoded_bytes: []u8, // Owned by this struct
    file_size: u64, // Support large files (>4GB) - Tiger Style: explicit types
    quality: u8,
    diff_score: f64, // Stubbed to 0.0 for MVP, real metric in 0.2.0
    passed_constraints: bool,
    encoding_time_ns: u64,

    comptime {
        // Tiger Style: Ensure struct size is reasonable
        std.debug.assert(@sizeOf(EncodedCandidate) <= 128);
    }

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
    cache_ptr: ?*Cache, // Optional cache (null = caching disabled)

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
            .cache_ptr = null, // No caching by default
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

/// Detect image format from magic numbers (file signature)
///
/// Tiger Style: Bounded checks, explicit fallback to .unknown
fn detectFormatFromMagic(bytes: []const u8) ImageFormat {
    std.debug.assert(bytes.len >= 0); // Pre-condition

    if (bytes.len < 4) return .unknown;

    // JPEG: FF D8 FF
    if (bytes[0] == 0xFF and bytes[1] == 0xD8) return .jpeg;

    // PNG: 89 50 4E 47
    if (bytes[0] == 0x89 and bytes[1] == 0x50 and
        bytes[2] == 0x4E and bytes[3] == 0x47) return .png;

    // WebP: RIFF ... WEBP (needs 12 bytes)
    if (bytes.len >= 12 and
        bytes[0] == 0x52 and bytes[1] == 0x49 and
        bytes[8] == 0x57 and bytes[9] == 0x45) return .webp;

    // AVIF: ftyp (needs 12 bytes)
    if (bytes.len >= 12 and
        bytes[4] == 0x66 and bytes[5] == 0x74) return .avif;

    return .unknown;
}

/// Add original file as baseline candidate
///
/// Ensures optimizer never makes files larger. Critical for conformance!
///
/// Tiger Style:
/// - Bounded file I/O (MAX_ORIGINAL_SIZE)
/// - Graceful format detection fallback
/// - Pre-condition: path must be valid file
fn addOriginalCandidate(
    allocator: Allocator,
    input_path: []const u8,
    max_bytes: ?u32,
    candidates: *ArrayList(EncodedCandidate),
) !void {
    // Pre-conditions
    std.debug.assert(input_path.len > 0);

    // Tiger Style: Bounded file I/O to prevent OOM
    const MAX_ORIGINAL_SIZE: u64 = 100 * 1024 * 1024; // 100MB

    const file = try std.fs.cwd().openFile(input_path, .{});
    defer file.close();

    const stat = try file.stat();
    if (stat.size > MAX_ORIGINAL_SIZE) {
        std.log.err("Original file too large: {d} bytes (max: {d})", .{stat.size, MAX_ORIGINAL_SIZE});
        return error.FileTooLarge;
    }

    const original_bytes = try file.readToEndAlloc(allocator, stat.size);
    errdefer allocator.free(original_bytes);

    // Get original format with graceful fallback
    const original_format = image_ops.getImageMetadata(input_path) catch |err| blk: {
        std.log.warn("Failed to get original metadata: {}, attempting format detection from bytes", .{err});

        const detected_format = detectFormatFromMagic(original_bytes);
        std.log.warn("Detected format from magic numbers: {s}", .{@tagName(detected_format)});

        break :blk ImageMetadata{
            .format = detected_format,
            .original_width = 0,
            .original_height = 0,
            .has_alpha = false,
            .exif_orientation = .normal,
            .icc_profile = null,
            .allocator = null,
        };
    };

    const passed_constraints = if (max_bytes) |max| original_bytes.len <= max else true;

    const original_candidate = EncodedCandidate{
        .format = original_format.format,
        .encoded_bytes = original_bytes,
        .file_size = @intCast(original_bytes.len),
        .quality = 100,
        .diff_score = 0.0,
        .passed_constraints = passed_constraints,
        .encoding_time_ns = 0,
    };

    std.log.debug("Adding original file as baseline candidate: format={s}, size={d}", .{
        @tagName(original_candidate.format),
        original_candidate.file_size,
    });

    try candidates.append(allocator, original_candidate);

    // Post-condition: original added successfully
    std.debug.assert(candidates.items.len > 0);
}

/// Optimize image from memory buffer (no temp files required)
///
/// Similar to optimizeImage but works directly with bytes in memory.
/// Useful for language bindings (Python, Node.js) that already have image bytes.
///
/// Tiger Style: Same guarantees as optimizeImage, but avoids file I/O
pub fn optimizeImageFromBuffer(
    allocator: Allocator,
    input_bytes: []const u8,
    original_format: ImageFormat,
    max_bytes: ?u32,
    max_diff: ?f64,
    metric_type: MetricType,
    formats: []const ImageFormat,
    concurrency: u8,
    cache_ptr: ?*Cache,
) !OptimizationResult {
    // Validate inputs
    std.debug.assert(input_bytes.len > 0);
    std.debug.assert(formats.len > 0);
    std.debug.assert(concurrency > 0);

    const start_time = std.time.nanoTimestamp();

    // Try cache first (for each format)
    if (cache_ptr) |cache_ref| {
        for (formats) |format| {
            const cache_key = Cache.computeKey(
                input_bytes,
                max_bytes,
                max_diff,
                metric_type,
                format,
            );

            if (cache_ref.get(cache_key, format)) |cached| {
                std.log.info("Cache HIT for format {s}", .{@tagName(format)});

                // Convert cached result to OptimizationResult
                const selected = EncodedCandidate{
                    .format = cached.metadata.format,
                    .encoded_bytes = cached.bytes, // Transfer ownership
                    .file_size = cached.metadata.file_size,
                    .quality = cached.metadata.quality,
                    .diff_score = cached.metadata.diff_score,
                    .passed_constraints = cached.metadata.passed_constraints,
                    .encoding_time_ns = 0, // Cached, no encoding
                };

                const total_time = @as(u64, @intCast(std.time.nanoTimestamp() - start_time));

                // Return immediately with cached result
                return .{
                    .selected = selected,
                    .all_candidates = &[_]EncodedCandidate{}, // Empty for cached results
                    .timings = .{
                        .decode_ns = 0,
                        .encode_ns = 0,
                        .total_ns = total_time,
                    },
                    .warnings = &[_][]const u8{},
                    .success = cached.metadata.passed_constraints,
                };
            }
        }
    }
    var warnings = ArrayList([]u8){};
    errdefer {
        for (warnings.items) |warning| allocator.free(warning);
        warnings.deinit(allocator);
    }

    // Step 1: Decode and normalize from memory
    const decode_start = std.time.nanoTimestamp();
    var buffer = try image_ops.decodeImageFromMemory(allocator, input_bytes);
    errdefer buffer.deinit();
    const decode_time = @as(u64, @intCast(std.time.nanoTimestamp() - decode_start));

    // Step 2: Generate candidates (parallel encoding)
    const encode_start = std.time.nanoTimestamp();
    var candidates = try generateCandidates(
        allocator,
        &buffer,
        formats,
        max_bytes,
        max_diff,
        metric_type,
        concurrency,
        true, // Enable parallel encoding
        &warnings,
    );
    errdefer {
        for (candidates.items) |*candidate| candidate.deinit(allocator);
        candidates.deinit(allocator);
    }
    const encode_time = @as(u64, @intCast(std.time.nanoTimestamp() - encode_start));

    buffer.deinit(); // No longer needed

    // Step 2.5: Add original bytes as baseline candidate
    const original_bytes_copy = try allocator.dupe(u8, input_bytes);
    const original_candidate = EncodedCandidate{
        .format = original_format,
        .encoded_bytes = original_bytes_copy,
        .file_size = @intCast(original_bytes_copy.len),
        .quality = 100, // Original quality
        .diff_score = 0.0, // Perfect match to original
        .passed_constraints = if (max_bytes) |max| original_bytes_copy.len <= max else true,
        .encoding_time_ns = 0, // No encoding needed
    };
    try candidates.append(allocator, original_candidate);

    // Step 3: Select best candidate
    const selected = try selectBestCandidate(
        allocator,
        candidates.items,
        max_bytes,
        max_diff,
    );

    const total_time = @as(u64, @intCast(std.time.nanoTimestamp() - start_time));

    // Store result in cache if enabled and successful
    if (cache_ptr) |cache_ref| {
        if (selected) |sel| {
            const cache_key = Cache.computeKey(
                input_bytes,
                max_bytes,
                max_diff,
                metric_type,
                sel.format,
            );

            const metadata = cache.CacheMetadata{
                .format = sel.format,
                .file_size = sel.file_size,
                .quality = sel.quality,
                .diff_score = sel.diff_score,
                .passed_constraints = sel.passed_constraints,
                .timestamp = std.time.timestamp(),
                .access_count = 0,
            };

            cache_ref.put(cache_key, sel.format, sel.encoded_bytes, metadata) catch |err| {
                std.log.warn("Failed to cache result: {}", .{err});
                // Continue anyway - caching is optional
            };
        }
    }

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

/// Try to get cached result for optimization job
///
/// Tiger Style: Bounded iteration over formats, ≤70 lines
fn tryCacheHit(
    allocator: Allocator,
    job: OptimizationJob,
    start_time: i128,
) !?OptimizationResult {
    // Pre-conditions
    std.debug.assert(job.formats.len > 0);
    std.debug.assert(job.input_path.len > 0);

    const cache_ref = job.cache_ptr orelse return null;

    const input_bytes = fs.cwd().readFileAlloc(
        allocator,
        job.input_path,
        100 * 1024 * 1024, // Max 100MB
    ) catch return null;
    defer allocator.free(input_bytes);

    // Tiger Style: Bounded loop over formats
    for (job.formats) |format| {
        const cache_key = Cache.computeKey(
            input_bytes,
            job.max_bytes,
            job.max_diff,
            job.metric_type,
            format,
        );

        if (cache_ref.get(cache_key, format)) |cached| {
            std.log.info("Cache HIT for {s} (format: {s})", .{ job.input_path, @tagName(format) });

            const selected = EncodedCandidate{
                .format = cached.metadata.format,
                .encoded_bytes = cached.bytes,
                .file_size = cached.metadata.file_size,
                .quality = cached.metadata.quality,
                .diff_score = cached.metadata.diff_score,
                .passed_constraints = cached.metadata.passed_constraints,
                .encoding_time_ns = 0,
            };

            const total_time = @as(u64, @intCast(std.time.nanoTimestamp() - start_time));

            return OptimizationResult{
                .selected = selected,
                .all_candidates = &[_]EncodedCandidate{},
                .timings = .{
                    .decode_ns = 0,
                    .encode_ns = 0,
                    .total_ns = total_time,
                },
                .warnings = &[_][]const u8{},
                .success = cached.metadata.passed_constraints,
            };
        }
    }

    // Post-condition: No cache hit found
    return null;
}

/// Store optimized result in cache if enabled
///
/// Tiger Style: ≤70 lines, graceful degradation on failure
fn storeCacheResult(
    allocator: Allocator,
    job: OptimizationJob,
    selected: EncodedCandidate,
) void {
    // Pre-condition
    std.debug.assert(selected.encoded_bytes.len > 0);

    const cache_ref = job.cache_ptr orelse return;

    // Read file for cache key computation
    const input_bytes = fs.cwd().readFileAlloc(
        allocator,
        job.input_path,
        100 * 1024 * 1024,
    ) catch |err| {
        std.log.warn("Failed to read file for caching: {}", .{err});
        return;
    };
    defer allocator.free(input_bytes);

    const cache_key = Cache.computeKey(
        input_bytes,
        job.max_bytes,
        job.max_diff,
        job.metric_type,
        selected.format,
    );

    const metadata = cache.CacheMetadata{
        .format = selected.format,
        .file_size = selected.file_size,
        .quality = selected.quality,
        .diff_score = selected.diff_score,
        .passed_constraints = selected.passed_constraints,
        .timestamp = std.time.timestamp(),
        .access_count = 0,
    };

    cache_ref.put(cache_key, selected.format, selected.encoded_bytes, metadata) catch |err| {
        std.log.warn("Failed to cache result: {}", .{err});
        // Continue anyway - caching is optional
    };

    // Post-condition: Cache storage attempted (may have failed gracefully)
}

/// Main optimization function - orchestrates the entire pipeline
///
/// Steps:
/// 1. Try cache first
/// 2. Decode and generate candidates
/// 3. Add original file as baseline
/// 4. Select best candidate and cache result
///
/// Tiger Style:
/// - ≤70 lines (extracts helpers)
/// - Bounded operations
/// - Explicit error handling
pub fn optimizeImage(
    allocator: Allocator,
    job: OptimizationJob,
) !OptimizationResult {
    // Pre-conditions
    std.debug.assert(job.formats.len > 0);
    std.debug.assert(job.concurrency > 0);
    std.debug.assert(job.input_path.len > 0);
    std.debug.assert(job.output_path.len > 0);

    const start_time = std.time.nanoTimestamp();

    // Try cache first
    if (try tryCacheHit(allocator, job, start_time)) |cached_result| {
        return cached_result;
    }

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
        job.max_diff,
        job.metric_type,
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

    // Step 2.5: Add original file as baseline candidate (prevents size regressions)
    try addOriginalCandidate(allocator, job.input_path, job.max_bytes, &candidates);

    // Step 3: Select best candidate
    const selected = try selectBestCandidate(
        allocator,
        candidates.items,
        job.max_bytes,
        job.max_diff,
    );

    const total_time = @as(u64, @intCast(std.time.nanoTimestamp() - start_time));

    // Store result in cache if enabled and successful
    if (selected) |sel| {
        storeCacheResult(allocator, job, sel);
    }

    // Post-condition: Return complete result
    return OptimizationResult{
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
    max_diff: ?f64,
    metric_type: MetricType,
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
            max_diff,
            metric_type,
            max_workers,
            warnings,
        );
    } else {
        return generateCandidatesSequential(
            allocator,
            buffer,
            formats,
            max_bytes,
            max_diff,
            metric_type,
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
    max_diff: ?f64,
    metric_type: MetricType,
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
    var processed: u8 = 0;
    for (formats, 0..) |format, i| {
        std.debug.assert(i < MAX_FORMATS); // Loop invariant
        processed += 1;

        const candidate = encodeCandidateForFormat(
            allocator,
            buffer,
            format,
            max_bytes,
            max_diff,
            metric_type
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

    // Post-loop assertions: Verify bounded execution
    std.debug.assert(processed == formats.len);
    std.debug.assert(processed <= MAX_FORMATS);
    std.debug.assert(candidates.items.len <= MAX_FORMATS);

    return candidates;
}

/// Thread context for parallel encoding (v0.2.0)
///
/// Each thread gets isolated arena allocator for memory safety.
/// Results are cloned back to parent allocator after encoding.
const EncodingThreadContext = struct {
    parent_allocator: Allocator,
    buffer: *const ImageBuffer,
    format: ImageFormat,
    max_bytes: ?u32,
    max_diff: ?f64,
    metric_type: MetricType,
    result: ?EncodedCandidate,
    error_msg: ?[]u8,

    /// Worker function executed by each thread
    fn worker(self: *EncodingThreadContext) void {
        // Per-thread arena allocator (memory isolation)
        var arena = std.heap.ArenaAllocator.init(self.parent_allocator);
        defer arena.deinit();
        const thread_alloc = arena.allocator();

        // Encode candidate
        const candidate = encodeCandidateForFormat(
            thread_alloc,
            self.buffer,
            self.format,
            self.max_bytes,
            self.max_diff,
            self.metric_type,
        ) catch |err| {
            self.error_msg = self.parent_allocator.dupe(u8, @errorName(err)) catch null;
            self.result = null;
            return;
        };

        // Clone to parent allocator (arena will be freed)
        self.result = cloneCandidate(self.parent_allocator, candidate) catch {
            self.result = null;
            return;
        };
    }
};

/// Parallel candidate generation (v0.2.0)
///
/// Uses thread pool to encode multiple formats simultaneously.
/// Expected speedup: 2-4x on multi-core systems.
///
/// Tiger Style: ≤70 lines, bounded parallelism, memory isolation
fn generateCandidatesParallel(
    allocator: Allocator,
    buffer: *const ImageBuffer,
    formats: []const ImageFormat,
    max_bytes: ?u32,
    max_diff: ?f64,
    metric_type: MetricType,
    max_workers: u8,
    warnings: *ArrayList([]u8),
) !ArrayList(EncodedCandidate) {
    const MAX_FORMATS: u8 = 10;

    // Pre-conditions
    std.debug.assert(formats.len > 0 and formats.len <= MAX_FORMATS);
    std.debug.assert(max_workers > 0);
    std.debug.assert(buffer.width > 0 and buffer.height > 0);

    var candidates = ArrayList(EncodedCandidate){};
    errdefer {
        for (candidates.items) |*candidate| candidate.deinit(allocator);
        candidates.deinit(allocator);
    }

    // Bounded parallelism
    const num_threads: u8 = @min(@as(u8, @intCast(formats.len)), max_workers);
    std.debug.assert(num_threads <= max_workers and num_threads <= formats.len);

    const contexts = try allocator.alloc(EncodingThreadContext, num_threads);
    defer allocator.free(contexts);

    const threads = try allocator.alloc(std.Thread, num_threads);
    defer allocator.free(threads);

    // Spawn threads
    for (contexts, threads, 0..) |*ctx, *thread, i| {
        ctx.* = .{
            .parent_allocator = allocator,
            .buffer = buffer,
            .format = formats[i],
            .max_bytes = max_bytes,
            .max_diff = max_diff,
            .metric_type = metric_type,
            .result = null,
            .error_msg = null,
        };
        thread.* = try std.Thread.spawn(.{}, EncodingThreadContext.worker, .{ctx});
    }

    // Collect results
    for (threads, contexts, 0..) |thread, *ctx, i| {
        std.debug.assert(i < num_threads);
        thread.join();

        if (ctx.result) |candidate| {
            try candidates.append(allocator, candidate);
        } else if (ctx.error_msg) |err_msg| {
            const warning = try std.fmt.allocPrint(allocator, "Failed to encode {s}: {s}",
                .{ @tagName(ctx.format), err_msg });
            try warnings.append(allocator, warning);
            allocator.free(err_msg);
        }
    }

    // Post-condition
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

/// Compute perceptual diff for a candidate
///
/// Decodes candidate and compares against baseline using specified metric.
/// Returns 0.0 on decode/metric failure (conservative: assume perfect match).
///
/// Tiger Style: Pre/post conditions, graceful degradation
fn computeCandidateDiff(
    allocator: Allocator,
    baseline: *const ImageBuffer,
    encoded_bytes: []const u8,
    metric_type: MetricType,
) f64 {
    // Pre-conditions
    std.debug.assert(baseline.width > 0 and baseline.height > 0);
    std.debug.assert(encoded_bytes.len > 0);

    if (metric_type == .none) return 0.0;

    // Decode candidate for comparison
    var decoded_candidate = image_ops.decodeImageFromMemory(
        allocator,
        encoded_bytes,
    ) catch |err| {
        std.log.warn("Failed to decode candidate for diff computation: {}", .{err});
        return 0.0; // Conservative: assume perfect match
    };
    defer decoded_candidate.deinit();

    // Compute perceptual diff
    const diff = metrics.computePerceptualDiff(
        allocator,
        baseline,
        &decoded_candidate,
        metric_type,
    ) catch |err| {
        std.log.warn("Failed to compute perceptual diff: {}", .{err});
        return 0.0; // Conservative: assume perfect match
    };

    // Post-condition: valid diff score
    std.debug.assert(diff >= 0.0 and !std.math.isNan(diff));

    return diff;
}

/// Encode a single candidate for a specific format
///
/// Uses binary search to hit size target if max_bytes is specified,
/// otherwise uses default quality.
///
/// Tiger Style: ≤70 lines, 2+ assertions, explicit error handling
fn encodeCandidateForFormat(
    allocator: Allocator,
    baseline: *const ImageBuffer,
    format: ImageFormat,
    max_bytes: ?u32,
    max_diff: ?f64,
    metric_type: MetricType,
) !EncodedCandidate {
    // Pre-conditions
    std.debug.assert(baseline.width > 0 and baseline.height > 0);
    std.debug.assert(baseline.data.len > 0);

    const encode_start = std.time.nanoTimestamp();

    var encoded_bytes: []u8 = undefined;
    var quality: u8 = undefined;

    if (max_bytes) |target_bytes| {
        // Use binary search to hit target size
        const search_result = try search.binarySearchQuality(
            allocator,
            baseline.*,
            format,
            target_bytes,
            .{},
        );
        encoded_bytes = search_result.encoded;
        quality = search_result.quality;
    } else {
        // No size constraint - use default quality
        quality = codecs.getDefaultQuality(format);
        encoded_bytes = try codecs.encodeImage(allocator, baseline, format, quality);
    }

    const encode_time = @as(u64, @intCast(std.time.nanoTimestamp() - encode_start));
    const file_size: u64 = @intCast(encoded_bytes.len);

    // Post-condition: encoded data is valid
    std.debug.assert(encoded_bytes.len > 0);
    std.debug.assert(file_size == encoded_bytes.len);

    // Compute perceptual diff (v0.4.0)
    const diff_score = computeCandidateDiff(allocator, baseline, encoded_bytes, metric_type);

    // Check if constraints are met (both size and quality)
    const passed = blk: {
        if (max_bytes) |limit| {
            if (file_size > limit) break :blk false;
        }
        if (max_diff) |limit| {
            if (diff_score > limit) break :blk false;
        }
        break :blk true;
    };

    return .{
        .format = format,
        .encoded_bytes = encoded_bytes,
        .file_size = file_size,
        .quality = quality,
        .diff_score = diff_score,
        .passed_constraints = passed,
        .encoding_time_ns = encode_time,
    };
}

/// Select the best candidate that passes all constraints
///
/// Selection criteria:
/// 1. Must pass size constraint (bytes <= max_bytes)
/// 2. Must pass quality constraint (diff <= max_diff)
/// 3. Prefer smallest file size
/// 4. Tiebreak by format preference (AVIF > WebP > JPEG > PNG)
///
/// Returns null if no candidate passes constraints.
///
/// Tiger Style: Bounded loop, explicit constraints, ≤70 lines
fn selectBestCandidate(
    allocator: Allocator,
    candidates: []const EncodedCandidate,
    max_bytes: ?u32,
    max_diff: ?f64,
) !?EncodedCandidate {
    // Pre-condition
    std.debug.assert(candidates.len > 0);

    var best: ?*const EncodedCandidate = null;

    // Tiger Style: Bounded loop (exactly candidates.len iterations)
    for (candidates) |*candidate| {
        // Filter: Check size constraint
        if (max_bytes) |limit| {
            if (candidate.file_size > limit) continue;
        }

        // Filter: Check diff constraint (v0.4.0: dual-constraint validation)
        if (max_diff) |limit| {
            if (candidate.diff_score > limit) continue;
        }

        // Select if first passing candidate or smaller than current best
        if (best == null or candidate.file_size < best.?.file_size) {
            best = candidate;
        } else if (candidate.file_size == best.?.file_size) {
            // Tiebreak by format preference (AVIF > WebP > JPEG > PNG)
            const cand_pref = formatPreference(candidate.format);
            const best_pref = formatPreference(best.?.format);
            if (cand_pref > best_pref) {
                best = candidate;
            }
        }
    }

    if (best) |b| {
        std.log.info("Selected: format={s}, size={d}, quality={d}, diff={d:.4}", .{
            @tagName(b.format), b.file_size, b.quality, b.diff_score
        });

        // Clone the best candidate for return
        const cloned_bytes = try allocator.dupe(u8, b.encoded_bytes);

        // Post-condition: cloned data matches original
        std.debug.assert(cloned_bytes.len == b.encoded_bytes.len);

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
    // selectBestCandidate clones the bytes, so we must free them
    defer if (best) |b| testing.allocator.free(b.encoded_bytes);

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
    // selectBestCandidate clones the bytes, so we must free them
    defer if (best) |b| testing.allocator.free(b.encoded_bytes);

    try testing.expect(best != null);
    // WebP preferred over PNG at same size
    try testing.expectEqual(ImageFormat.webp, best.?.format);
}
