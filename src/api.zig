// Pyjamaz Public API
// Clean API layer for language bindings (Python, Node.js, etc.)
//
// Design principles:
// - Simple C-compatible ABI for FFI
// - Memory safety (caller must free allocated memory)
// - Clear ownership semantics
// - Minimal surface area

const std = @import("std");
const optimizer = @import("optimizer.zig");
const types = @import("types.zig");
const cache = @import("cache.zig");

/// API version (semantic versioning)
pub const VERSION_MAJOR: u32 = 1;
pub const VERSION_MINOR: u32 = 0;
pub const VERSION_PATCH: u32 = 0;

/// Optimization options passed from client
pub const OptimizeOptions = extern struct {
    /// Input image bytes
    input_bytes: [*]const u8,
    input_len: usize,

    /// Maximum output file size in bytes (0 = no limit)
    max_bytes: u32,

    /// Maximum perceptual difference (0.0 = no limit)
    max_diff: f64,

    /// Metric type: "dssim", "ssimulacra2", or "none"
    metric_type: [*:0]const u8,

    /// Comma-separated format list: "jpeg,png,webp,avif" (null = all formats)
    formats: [*:0]const u8,

    /// Number of parallel encoding threads (0 = auto)
    concurrency: u8,

    /// Enable caching (1 = enabled, 0 = disabled)
    cache_enabled: u8,

    /// Cache directory path (null = default ~/.cache/pyjamaz)
    cache_dir: [*:0]const u8,

    /// Maximum cache size in bytes (0 = default 1GB)
    cache_max_size: u64,
};

/// Optimization result returned to client
pub const OptimizeResult = extern struct {
    /// Output image bytes (caller must free with pyjamaz_free)
    output_bytes: [*]u8,
    output_len: usize,

    /// Selected format: "jpeg", "png", "webp", or "avif"
    format: [*:0]u8,

    /// Perceptual difference score
    diff_value: f64,

    /// Whether all constraints were met
    passed: u8, // boolean (1 = true, 0 = false)

    /// Error message (null if no error, caller must free with pyjamaz_free)
    error_message: [*:0]u8,

    /// Internal: tracks if error_message was heap-allocated (1) or static (0)
    error_message_allocated: u8,
};

/// Global allocator for API layer (uses C allocator for FFI compatibility)
var gpa = std.heap.c_allocator;

/// Detect image format from magic bytes
fn detectFormat(bytes: []const u8) types.ImageFormat {
    if (bytes.len < 4) return .jpeg; // Default fallback

    // JPEG: FF D8 FF
    if (bytes[0] == 0xFF and bytes[1] == 0xD8 and bytes[2] == 0xFF) {
        return .jpeg;
    }

    // PNG: 89 50 4E 47 0D 0A 1A 0A
    if (bytes.len >= 8 and bytes[0] == 0x89 and bytes[1] == 0x50 and bytes[2] == 0x4E and bytes[3] == 0x47) {
        return .png;
    }

    // WebP: "RIFF" ... "WEBP"
    if (bytes.len >= 12 and bytes[0] == 'R' and bytes[1] == 'I' and bytes[2] == 'F' and bytes[3] == 'F' and bytes[8] == 'W' and bytes[9] == 'E' and bytes[10] == 'B' and bytes[11] == 'P') {
        return .webp;
    }

    // AVIF: ftyp ... avif/avis
    if (bytes.len >= 12 and bytes[4] == 'f' and bytes[5] == 't' and bytes[6] == 'y' and bytes[7] == 'p') {
        return .avif;
    }

    // Default to JPEG
    return .jpeg;
}

/// Initialize the library (must be called before any other functions)
/// Thread-safe, can be called multiple times
export fn pyjamaz_init() void {
    // libvips initialization handled per-context, no global init needed
    _ = gpa;
}

/// Clean up library resources (call at program exit)
/// Thread-safe, can be called multiple times
export fn pyjamaz_cleanup() void {
    // libvips cleanup handled per-context, no global cleanup needed
}

/// Get version string (e.g., "1.0.0")
/// Returns a static string (do not free)
export fn pyjamaz_version() [*:0]const u8 {
    return "1.0.0";
}

/// Optimize an image from memory buffer
/// Returns OptimizeResult* (caller must free with pyjamaz_free_result)
export fn pyjamaz_optimize(options: *const OptimizeOptions) ?*OptimizeResult {
    // Pre-conditions: Validate inputs at FFI boundary
    std.debug.assert(options.input_len > 0); // Must have input data
    std.debug.assert(options.concurrency > 0 and options.concurrency <= 16); // Reasonable concurrency range

    // Allocate result struct
    const result = gpa.create(OptimizeResult) catch {
        return null;
    };
    errdefer gpa.destroy(result);

    // Initialize result with defaults
    result.* = .{
        .output_bytes = undefined,
        .output_len = 0,
        .format = undefined,
        .diff_value = 0.0,
        .passed = 0,
        .error_message = @ptrCast(@constCast("".ptr)),
        .error_message_allocated = 0, // Static empty string
    };

    // Parse metric type
    const metric_str = std.mem.span(options.metric_type);
    const metric_type: types.MetricType = if (std.mem.eql(u8, metric_str, "dssim"))
        .dssim
    else if (std.mem.eql(u8, metric_str, "ssimulacra2"))
        .ssimulacra2
    else if (std.mem.eql(u8, metric_str, "none"))
        .none
    else
        .dssim; // default

    // Parse formats (default to all if empty)
    // Tiger Style: Bounded loop with explicit MAX constant
    const MAX_FORMATS: u8 = 10;
    var formats_list = std.ArrayList(types.ImageFormat){};
    defer formats_list.deinit(gpa);

    const formats_str = std.mem.span(options.formats);
    if (formats_str.len > 0) {
        var iter = std.mem.splitScalar(u8, formats_str, ',');
        var format_count: u8 = 0;
        while (iter.next()) |fmt| : (format_count += 1) {
            std.debug.assert(format_count < MAX_FORMATS); // Loop invariant

            const trimmed = std.mem.trim(u8, fmt, " ");
            if (std.mem.eql(u8, trimmed, "jpeg")) {
                formats_list.append(gpa, .jpeg) catch {};
            } else if (std.mem.eql(u8, trimmed, "png")) {
                formats_list.append(gpa, .png) catch {};
            } else if (std.mem.eql(u8, trimmed, "webp")) {
                formats_list.append(gpa, .webp) catch {};
            } else if (std.mem.eql(u8, trimmed, "avif")) {
                formats_list.append(gpa, .avif) catch {};
            }
        }
        std.debug.assert(format_count <= MAX_FORMATS); // Post-loop assertion
    } else {
        // Default: all formats
        formats_list.append(gpa, .jpeg) catch {};
        formats_list.append(gpa, .png) catch {};
        formats_list.append(gpa, .webp) catch {};
        formats_list.append(gpa, .avif) catch {};
    }

    // Post-condition: formats_list has at least one format
    std.debug.assert(formats_list.items.len > 0 and formats_list.items.len <= MAX_FORMATS);

    // Set up cache if enabled
    var cache_config: ?cache.CacheConfig = null;
    var cache_instance: ?cache.Cache = null;
    var cache_dir_allocated: ?[]u8 = null;
    defer if (cache_instance) |*c| c.deinit();
    defer if (cache_dir_allocated) |dir| gpa.free(dir);

    if (options.cache_enabled == 1) {
        const cache_dir_str = std.mem.span(options.cache_dir);
        const cache_dir_path = if (cache_dir_str.len > 0)
            cache_dir_str
        else blk: {
            // Get default cache directory
            cache_dir_allocated = cache.CacheConfig.getDefaultCacheDir(gpa) catch break :blk "";
            break :blk cache_dir_allocated.?;
        };

        if (cache_dir_path.len > 0) {
            cache_config = cache.CacheConfig{
                .cache_dir = cache_dir_path,
                .max_size_bytes = if (options.cache_max_size > 0) options.cache_max_size else 1024 * 1024 * 1024, // 1GB default
                .enabled = true,
            };

            cache_instance = cache.Cache.init(gpa, cache_config.?) catch null;
        }
    }

    // Create optimization job
    const input_slice = options.input_bytes[0..options.input_len];

    // Detect original format from magic bytes
    const original_format = detectFormat(input_slice);

    // Try to optimize from buffer
    const opt_result = optimizer.optimizeImageFromBuffer(
        gpa,
        input_slice,
        original_format,
        if (options.max_bytes > 0) options.max_bytes else null,
        if (options.max_diff > 0.0) options.max_diff else null,
        metric_type,
        formats_list.items,
        if (options.concurrency > 0) options.concurrency else 4,
        if (cache_instance) |*c| c else null,
    ) catch |err| {
        // Handle error
        const error_msg = std.fmt.allocPrint(gpa, "Optimization failed: {s}\x00", .{@errorName(err)}) catch {
            result.error_message = @ptrCast(@constCast("Unknown error\x00".ptr));
            result.error_message_allocated = 0; // Static string
            return result;
        };
        result.error_message = @ptrCast(error_msg.ptr);
        result.error_message_allocated = 1; // Heap-allocated
        return result;
    };

    // Check if optimization succeeded
    if (opt_result.selected) |candidate| {
        // Clone output bytes (caller will free)
        const output_copy = gpa.alloc(u8, candidate.encoded_bytes.len) catch {
            result.error_message = @ptrCast(@constCast("Out of memory\x00".ptr));
            result.error_message_allocated = 0; // Static string
            return result;
        };
        @memcpy(output_copy, candidate.encoded_bytes);

        result.output_bytes = output_copy.ptr;
        result.output_len = output_copy.len;

        // Clone format string with null terminator
        const format_str = @tagName(candidate.format);
        const format_copy = std.fmt.allocPrint(gpa, "{s}\x00", .{format_str}) catch {
            gpa.free(output_copy);
            result.error_message = @ptrCast(@constCast("Out of memory\x00".ptr));
            result.error_message_allocated = 0; // Static string
            return result;
        };
        result.format = @ptrCast(format_copy.ptr);

        result.diff_value = candidate.diff_score;
        result.passed = 1;
    } else {
        // No candidate met constraints
        result.passed = 0;
        result.error_message = @ptrCast(@constCast("No candidate met constraints\x00".ptr));
        result.error_message_allocated = 0; // Static string
    }

    // Post-conditions: Verify result integrity before returning
    std.debug.assert(result.passed == 0 or result.output_len > 0); // If passed, must have output
    std.debug.assert(result.passed == 1 or result.error_message != @as([*:0]u8, @ptrCast(@constCast("".ptr)))); // If failed, must have error

    return result;
}

/// Free memory allocated by pyjamaz_optimize
export fn pyjamaz_free_result(result: *OptimizeResult) void {
    if (result.output_len > 0) {
        const output_slice = result.output_bytes[0..result.output_len];
        gpa.free(output_slice);
    }

    // Free format string
    const format_slice = std.mem.span(result.format);
    if (format_slice.len > 0) {
        gpa.free(format_slice);
    }

    // Free error message if it was heap-allocated (tracked by flag)
    if (result.error_message_allocated == 1) {
        const error_slice = std.mem.span(result.error_message);
        if (error_slice.len > 0) {
            gpa.free(error_slice);
        }
    }

    gpa.destroy(result);
}

/// Free a generic string allocated by the library
export fn pyjamaz_free(ptr: [*]u8) void {
    _ = ptr;
    // Generic free - for future use
}
