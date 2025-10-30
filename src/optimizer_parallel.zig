//! Parallel candidate generation prototype for performance optimization
//!
//! This is a prototype implementation demonstrating parallel encoding
//! of image candidates. NOT YET INTEGRATED into main optimizer.
//!
//! Tiger Style compliance:
//! - Bounded parallelism (respects max_workers)
//! - Per-thread memory isolation (arena allocators)
//! - Explicit error handling (thread errors captured)
//! - 2+ assertions per function
//!
//! Status: PROTOTYPE (for 0.2.0 evaluation)

const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const Thread = std.Thread;

const types = @import("types.zig");
const ImageBuffer = types.ImageBuffer;
const ImageFormat = types.ImageFormat;
const codecs = @import("codecs.zig");
const search = @import("search.zig");
const optimizer = @import("optimizer.zig");
const EncodedCandidate = optimizer.EncodedCandidate;

/// Result from a single encoding thread
const ThreadResult = struct {
    candidate: ?EncodedCandidate, // null if error
    error_msg: ?[]const u8, // null if success
    format: ImageFormat,
};

/// Context passed to each encoding thread
const EncodingContext = struct {
    parent_allocator: Allocator,
    buffer: *const ImageBuffer,
    format: ImageFormat,
    max_bytes: ?u32,
    result: ThreadResult,
    mutex: Thread.Mutex,
};

/// Worker function executed by each encoding thread
///
/// Tiger Style:
/// - Per-thread arena allocator (memory isolation)
/// - Bounded operations (single encoding task)
/// - Explicit error handling (errors captured in result)
/// - 2+ assertions (pre-conditions, post-conditions)
fn encodingWorker(ctx: *EncodingContext) void {
    // Tiger Style: Pre-conditions
    std.debug.assert(ctx.buffer.width > 0);
    std.debug.assert(ctx.buffer.height > 0);
    std.debug.assert(ctx.buffer.data.len > 0);

    // Each thread gets its own arena allocator
    var arena = std.heap.ArenaAllocator.init(ctx.parent_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // Encode candidate
    const candidate = encodeCandidateForFormat(
        allocator,
        ctx.buffer,
        ctx.format,
        ctx.max_bytes,
    ) catch |err| {
        // Capture error
        const err_name = @errorName(err);
        const err_msg = ctx.parent_allocator.dupe(u8, err_name) catch {
            // Fallback if error message allocation fails
            ctx.result = .{
                .candidate = null,
                .error_msg = null,
                .format = ctx.format,
            };
            return;
        };

        ctx.result = .{
            .candidate = null,
            .error_msg = err_msg,
            .format = ctx.format,
        };
        return;
    };

    // Clone candidate to parent allocator (arena will be freed)
    const cloned = cloneCandidate(ctx.parent_allocator, candidate) catch |err| {
        std.log.err("Failed to clone candidate: {}", .{err});
        ctx.result = .{
            .candidate = null,
            .error_msg = null,
            .format = ctx.format,
        };
        return;
    };

    // Tiger Style: Post-condition
    std.debug.assert(cloned.encoded_bytes.len > 0);
    std.debug.assert(cloned.file_size > 0);

    ctx.result = .{
        .candidate = cloned,
        .error_msg = null,
        .format = ctx.format,
    };
}

/// Encode a single candidate for a specific format (helper for thread worker)
///
/// Identical to optimizer.zig:encodeCandidateForFormat but extracted
/// for clarity in parallel context.
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
            .{},
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

    const passed = blk: {
        if (max_bytes) |limit| {
            if (file_size > limit) break :blk false;
        }
        break :blk true;
    };

    return .{
        .format = format,
        .encoded_bytes = encoded_bytes,
        .file_size = file_size,
        .quality = quality,
        .diff_score = 0.0,
        .passed_constraints = passed,
        .encoding_time_ns = encode_time,
    };
}

/// Clone an encoded candidate to a different allocator
///
/// Tiger Style:
/// - Explicit allocator passing
/// - 2+ assertions (input validation, output validation)
fn cloneCandidate(
    allocator: Allocator,
    candidate: EncodedCandidate,
) !EncodedCandidate {
    // Tiger Style: Pre-conditions
    std.debug.assert(candidate.encoded_bytes.len > 0);
    std.debug.assert(candidate.file_size > 0);

    const cloned_bytes = try allocator.dupe(u8, candidate.encoded_bytes);

    // Tiger Style: Post-condition
    std.debug.assert(cloned_bytes.len == candidate.encoded_bytes.len);

    return .{
        .format = candidate.format,
        .encoded_bytes = cloned_bytes,
        .file_size = candidate.file_size,
        .quality = candidate.quality,
        .diff_score = candidate.diff_score,
        .passed_constraints = candidate.passed_constraints,
        .encoding_time_ns = candidate.encoding_time_ns,
    };
}

/// Generate encoding candidates in parallel (PROTOTYPE)
///
/// Tiger Style:
/// - Bounded parallelism: num_threads = min(formats.len, max_workers)
/// - Per-thread memory isolation: Each thread uses arena allocator
/// - Explicit error handling: Thread errors captured, don't crash main
/// - 2+ assertions: Pre-conditions, post-conditions
///
/// Performance:
/// - Expected speedup: 2-4x on 4+ cores
/// - Memory overhead: ~1MB per thread (arena allocators)
/// - Thread creation: ~1ms overhead per thread
pub fn generateCandidatesParallel(
    allocator: Allocator,
    buffer: *const ImageBuffer,
    formats: []const ImageFormat,
    max_bytes: ?u32,
    max_workers: u8,
    warnings: *ArrayList([]u8),
) !ArrayList(EncodedCandidate) {
    // Tiger Style: Pre-conditions
    std.debug.assert(formats.len > 0);
    std.debug.assert(max_workers > 0);
    std.debug.assert(buffer.width > 0);
    std.debug.assert(buffer.height > 0);

    var candidates = ArrayList(EncodedCandidate){};
    errdefer {
        for (candidates.items) |*candidate| candidate.deinit(allocator);
        candidates.deinit(allocator);
    }

    // Tiger Style: Bounded parallelism
    const num_threads: u8 = @min(@as(u8, @intCast(formats.len)), max_workers);
    std.debug.assert(num_threads <= max_workers);
    std.debug.assert(num_threads <= formats.len);

    // Special case: Single format or single worker → sequential
    if (num_threads == 1) {
        return generateCandidatesSequential(
            allocator,
            buffer,
            formats,
            max_bytes,
            warnings,
        );
    }

    // Allocate thread contexts
    var contexts = try allocator.alloc(EncodingContext, num_threads);
    defer allocator.free(contexts);

    var threads = try allocator.alloc(Thread, num_threads);
    defer allocator.free(threads);

    // Initialize contexts and spawn threads
    for (contexts, threads, 0..) |*ctx, *thread, i| {
        ctx.* = .{
            .parent_allocator = allocator,
            .buffer = buffer,
            .format = formats[i],
            .max_bytes = max_bytes,
            .result = .{
                .candidate = null,
                .error_msg = null,
                .format = formats[i],
            },
            .mutex = .{},
        };

        // Spawn thread
        thread.* = try Thread.spawn(.{}, encodingWorker, .{ctx});
    }

    // Wait for all threads and collect results
    for (threads, contexts) |thread, *ctx| {
        thread.join();

        if (ctx.result.candidate) |candidate| {
            // Success: Add candidate
            try candidates.append(allocator, candidate);
        } else if (ctx.result.error_msg) |err_msg| {
            // Error: Add warning
            const warning = try std.fmt.allocPrint(
                allocator,
                "Failed to encode {s}: {s}",
                .{ @tagName(ctx.result.format), err_msg },
            );
            try warnings.append(allocator, warning);
            allocator.free(err_msg);
        }
    }

    // Tiger Style: Post-condition
    std.debug.assert(candidates.items.len <= formats.len);

    return candidates;
}

/// Sequential candidate generation (fallback)
///
/// Identical to optimizer.zig:generateCandidates but extracted
/// for clarity in parallel comparison.
fn generateCandidatesSequential(
    allocator: Allocator,
    buffer: *const ImageBuffer,
    formats: []const ImageFormat,
    max_bytes: ?u32,
    warnings: *ArrayList([]u8),
) !ArrayList(EncodedCandidate) {
    std.debug.assert(formats.len > 0);

    var candidates = ArrayList(EncodedCandidate){};
    errdefer {
        for (candidates.items) |*candidate| candidate.deinit(allocator);
        candidates.deinit(allocator);
    }

    for (formats) |format| {
        const candidate = encodeCandidateForFormat(
            allocator,
            buffer,
            format,
            max_bytes,
        ) catch |err| {
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

    return candidates;
}

// ============================================================================
// Unit Tests
// ============================================================================

const testing = std.testing;

test "cloneCandidate: creates independent copy" {
    const original = EncodedCandidate{
        .format = .jpeg,
        .encoded_bytes = try testing.allocator.alloc(u8, 100),
        .file_size = 100,
        .quality = 85,
        .diff_score = 0.0,
        .passed_constraints = true,
        .encoding_time_ns = 1000,
    };
    defer testing.allocator.free(original.encoded_bytes);

    const cloned = try cloneCandidate(testing.allocator, original);
    defer testing.allocator.free(cloned.encoded_bytes);

    // Verify independence (different pointers)
    try testing.expect(cloned.encoded_bytes.ptr != original.encoded_bytes.ptr);

    // Verify equality (same content)
    try testing.expectEqual(original.file_size, cloned.file_size);
    try testing.expectEqual(original.quality, cloned.quality);
}

test "ThreadResult: captures success" {
    const result = ThreadResult{
        .candidate = .{
            .format = .png,
            .encoded_bytes = &[_]u8{1, 2, 3},
            .file_size = 3,
            .quality = 6,
            .diff_score = 0.0,
            .passed_constraints = true,
            .encoding_time_ns = 1000,
        },
        .error_msg = null,
        .format = .png,
    };

    try testing.expect(result.candidate != null);
    try testing.expect(result.error_msg == null);
}

test "ThreadResult: captures error" {
    const result = ThreadResult{
        .candidate = null,
        .error_msg = "OutOfMemory",
        .format = .jpeg,
    };

    try testing.expect(result.candidate == null);
    try testing.expect(result.error_msg != null);
}

// Note: Full integration tests for parallel encoding require
// actual image data and are in src/test/benchmark/parallel_encoding.zig
