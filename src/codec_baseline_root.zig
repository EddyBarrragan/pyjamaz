///! Codec baseline benchmark root - measures current libvips performance

const std = @import("std");
const vips = @import("vips.zig");
const codecs = @import("codecs.zig");
const ImageBuffer = @import("types/image_buffer.zig").ImageBuffer;
const ImageFormat = @import("types/image_metadata.zig").ImageFormat;

/// Benchmark baseline for libvips codec performance
///
/// This measures current encode/decode speed to establish a baseline
/// before replacing libvips with direct codec libraries.
///
/// Expected performance (libvips):
/// - JPEG decode: ~100ms for typical images
/// - JPEG encode: ~150ms for typical images
/// - PNG decode: ~80ms for typical images
/// - PNG encode: ~120ms for typical images
///
/// Target after replacement (2-5x improvement):
/// - JPEG decode: ~40-50ms (2-2.5x faster)
/// - JPEG encode: ~75-100ms (1.5-2x faster)
/// - PNG decode: ~30-40ms (2-2.5x faster)
/// - PNG encode: ~50-60ms (2-2.5x faster)

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Initialize libvips
    var vips_ctx = try vips.VipsContext.init();
    defer vips_ctx.deinit();

    std.debug.print("\n=== libvips Codec Baseline Benchmark ===\n\n", .{});

    // Test image path
    const test_image = "testdata/conformance/testimages/boat_alt.png";

    // Verify test image exists
    std.fs.cwd().access(test_image, .{}) catch |err| {
        std.debug.print("Error: Test image not found: {s}\n", .{test_image});
        std.debug.print("Error details: {}\n", .{err});
        return err;
    };

    // ========================================================================
    // Benchmark: Image Decode
    // ========================================================================
    {
        std.debug.print("Benchmark: PNG Decode (libvips)\n", .{});
        std.debug.print("Image: {s}\n", .{test_image});

        const iterations: u32 = 100;
        var total_time: u64 = 0;
        var i: u32 = 0;

        while (i < iterations) : (i += 1) {
            const start = std.time.nanoTimestamp();

            var img = try vips.loadImage(test_image);
            defer img.deinit();

            const end = std.time.nanoTimestamp();
            total_time += @intCast(end - start);
        }

        const avg_ns = total_time / iterations;
        const avg_ms = @as(f64, @floatFromInt(avg_ns)) / 1_000_000.0;

        std.debug.print("  Iterations: {d}\n", .{iterations});
        std.debug.print("  Average time: {d:.2} ms\n", .{avg_ms});
        std.debug.print("  Total time: {d:.2} ms\n\n", .{@as(f64, @floatFromInt(total_time)) / 1_000_000.0});
    }

    // ========================================================================
    // Benchmark: JPEG Encode
    // ========================================================================
    {
        std.debug.print("Benchmark: JPEG Encode (libvips, quality=85)\n", .{});

        // First decode the image
        var img = try vips.loadImage(test_image);
        defer img.deinit();

        // Get image buffer
        const buffer = try img.toImageBuffer(allocator);
        defer allocator.free(buffer.data);

        const iterations: u32 = 100;
        var total_time: u64 = 0;
        var i: u32 = 0;

        while (i < iterations) : (i += 1) {
            const start = std.time.nanoTimestamp();

            const encoded = try codecs.encodeImage(allocator, &buffer, .jpeg, 85);
            defer allocator.free(encoded);

            const end = std.time.nanoTimestamp();
            total_time += @intCast(end - start);
        }

        const avg_ns = total_time / iterations;
        const avg_ms = @as(f64, @floatFromInt(avg_ns)) / 1_000_000.0;

        std.debug.print("  Iterations: {d}\n", .{iterations});
        std.debug.print("  Average time: {d:.2} ms\n", .{avg_ms});
        std.debug.print("  Total time: {d:.2} ms\n\n", .{@as(f64, @floatFromInt(total_time)) / 1_000_000.0});
    }

    // ========================================================================
    // Benchmark: PNG Encode
    // ========================================================================
    {
        std.debug.print("Benchmark: PNG Encode (libvips, compression=6)\n", .{});

        // First decode the image
        var img = try vips.loadImage(test_image);
        defer img.deinit();

        // Get image buffer
        const buffer = try img.toImageBuffer(allocator);
        defer allocator.free(buffer.data);

        const iterations: u32 = 100;
        var total_time: u64 = 0;
        var i: u32 = 0;

        while (i < iterations) : (i += 1) {
            const start = std.time.nanoTimestamp();

            const encoded = try codecs.encodeImage(allocator, &buffer, .png, 6);
            defer allocator.free(encoded);

            const end = std.time.nanoTimestamp();
            total_time += @intCast(end - start);
        }

        const avg_ns = total_time / iterations;
        const avg_ms = @as(f64, @floatFromInt(avg_ns)) / 1_000_000.0;

        std.debug.print("  Iterations: {d}\n", .{iterations});
        std.debug.print("  Average time: {d:.2} ms\n", .{avg_ms});
        std.debug.print("  Total time: {d:.2} ms\n\n", .{@as(f64, @floatFromInt(total_time)) / 1_000_000.0});
    }

    // ========================================================================
    // Benchmark: WebP Encode (Native codec - NEW in Phase 2)
    // ========================================================================
    {
        std.debug.print("Benchmark: WebP Encode (native libwebp, quality=80)\n", .{});

        // First decode the image
        var img = try vips.loadImage(test_image);
        defer img.deinit();

        // Get image buffer
        const buffer = try img.toImageBuffer(allocator);
        defer allocator.free(buffer.data);

        const iterations: u32 = 100;
        var total_time: u64 = 0;
        var i: u32 = 0;

        while (i < iterations) : (i += 1) {
            const start = std.time.nanoTimestamp();

            const encoded = try codecs.encodeImage(allocator, &buffer, .webp, 80);
            defer allocator.free(encoded);

            const end = std.time.nanoTimestamp();
            total_time += @intCast(end - start);
        }

        const avg_ns = total_time / iterations;
        const avg_ms = @as(f64, @floatFromInt(avg_ns)) / 1_000_000.0;

        std.debug.print("  Iterations: {d}\n", .{iterations});
        std.debug.print("  Average time: {d:.2} ms\n", .{avg_ms});
        std.debug.print("  Total time: {d:.2} ms\n\n", .{@as(f64, @floatFromInt(total_time)) / 1_000_000.0});
    }

    // ========================================================================
    // Summary
    // ========================================================================
    std.debug.print("=== Baseline Complete ===\n", .{});
    std.debug.print("Run this benchmark again after codec replacement to measure improvement.\n", .{});
    std.debug.print("Target: 2-5x speedup for JPEG/PNG/WebP operations\n\n", .{});
}
