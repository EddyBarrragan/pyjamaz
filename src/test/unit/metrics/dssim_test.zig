//! Unit tests for DSSIM perceptual metric
//!
//! Tests verify correct DSSIM integration and behavior:
//! - Identical images should return ~0.0
//! - Different images should return > 0.0
//! - Dimension mismatches should fail gracefully
//! - RGB and RGBA formats both work

const std = @import("std");
const testing = std.testing;
const dssim = @import("../../../metrics/dssim.zig");
const ImageBuffer = @import("../../../types/image_buffer.zig").ImageBuffer;

/// Helper: Create a test image with solid color
fn createSolidImage(
    allocator: std.mem.Allocator,
    width: u32,
    height: u32,
    channels: u8,
    color: []const u8,
) !ImageBuffer {
    std.debug.assert(channels >= 3 and channels <= 4);
    std.debug.assert(color.len >= channels);

    const stride = width * channels;
    const data = try allocator.alloc(u8, @as(usize, stride) * @as(usize, height));

    // Fill with solid color
    var i: usize = 0;
    while (i < data.len) : (i += channels) {
        for (color[0..channels], 0..) |c, j| {
            data[i + j] = c;
        }
    }

    return ImageBuffer{
        .data = data,
        .width = width,
        .height = height,
        .stride = stride,
        .channels = channels,
        .allocator = allocator,
        .color_space = 0,
    };
}

test "DSSIM: identical RGB images return ~0.0" {
    const allocator = testing.allocator;

    // Create two identical images (gray)
    var img1 = try createSolidImage(allocator, 100, 100, 3, &[_]u8{ 128, 128, 128 });
    defer img1.deinit();

    var img2 = try createSolidImage(allocator, 100, 100, 3, &[_]u8{ 128, 128, 128 });
    defer img2.deinit();

    const score = try dssim.compute(allocator, &img1, &img2);

    // Identical images should have very low DSSIM (~0.0)
    try testing.expect(score < 0.001);
    try testing.expect(score >= 0.0);
}

test "DSSIM: identical RGBA images return ~0.0" {
    const allocator = testing.allocator;

    // Create two identical images (gray with alpha)
    var img1 = try createSolidImage(allocator, 100, 100, 4, &[_]u8{ 128, 128, 128, 255 });
    defer img1.deinit();

    var img2 = try createSolidImage(allocator, 100, 100, 4, &[_]u8{ 128, 128, 128, 255 });
    defer img2.deinit();

    const score = try dssim.compute(allocator, &img1, &img2);

    // Identical images should have very low DSSIM (~0.0)
    try testing.expect(score < 0.001);
    try testing.expect(score >= 0.0);
}

test "DSSIM: different RGB images return > 0.0" {
    const allocator = testing.allocator;

    // Black vs White
    var black = try createSolidImage(allocator, 100, 100, 3, &[_]u8{ 0, 0, 0 });
    defer black.deinit();

    var white = try createSolidImage(allocator, 100, 100, 3, &[_]u8{ 255, 255, 255 });
    defer white.deinit();

    const score = try dssim.compute(allocator, &black, &white);

    // Very different images should have high DSSIM
    try testing.expect(score > 0.1); // Black vs white should be very different
}

test "DSSIM: slightly different RGB images return small score" {
    const allocator = testing.allocator;

    // Gray (128) vs slightly lighter gray (138)
    var gray1 = try createSolidImage(allocator, 100, 100, 3, &[_]u8{ 128, 128, 128 });
    defer gray1.deinit();

    var gray2 = try createSolidImage(allocator, 100, 100, 3, &[_]u8{ 138, 138, 138 });
    defer gray2.deinit();

    const score = try dssim.compute(allocator, &gray1, &gray2);

    // Slightly different images should have small but non-zero DSSIM
    try testing.expect(score > 0.0);
    try testing.expect(score < 0.1); // Not too different
}

test "DSSIM: mixed RGB and RGBA works" {
    const allocator = testing.allocator;

    // RGB image
    var rgb = try createSolidImage(allocator, 100, 100, 3, &[_]u8{ 128, 128, 128 });
    defer rgb.deinit();

    // RGBA image (same color + alpha)
    var rgba = try createSolidImage(allocator, 100, 100, 4, &[_]u8{ 128, 128, 128, 255 });
    defer rgba.deinit();

    // DSSIM should handle RGB vs RGBA gracefully
    const score = try dssim.compute(allocator, &rgb, &rgba);

    // Should be very similar (same RGB values)
    try testing.expect(score < 0.01);
    try testing.expect(score >= 0.0);
}

test "DSSIM: larger images work" {
    const allocator = testing.allocator;

    // Create larger images (500x500)
    var img1 = try createSolidImage(allocator, 500, 500, 3, &[_]u8{ 128, 128, 128 });
    defer img1.deinit();

    var img2 = try createSolidImage(allocator, 500, 500, 3, &[_]u8{ 128, 128, 128 });
    defer img2.deinit();

    const score = try dssim.compute(allocator, &img1, &img2);

    // Identical large images should still have ~0.0 score
    try testing.expect(score < 0.001);
    try testing.expect(score >= 0.0);
}
