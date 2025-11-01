const std = @import("std");
const Allocator = std.mem.Allocator;
const ImageBuffer = @import("../types/image_buffer.zig").ImageBuffer;

/// WebP codec using libwebp
///
/// This module provides WebP encoding and decoding using the libwebp API.
///
/// Tiger Style: All operations bounded, explicit error handling, memory safety.

// ============================================================================
// C FFI Declarations (libwebp)
// ============================================================================

// Simple encoding API (returns allocated buffer via WebPMalloc)
extern "c" fn WebPEncodeRGBA(
    rgba: [*c]const u8,
    width: c_int,
    height: c_int,
    stride: c_int,
    quality_factor: f32,
    output: *[*c]u8,
) usize;

extern "c" fn WebPEncodeRGB(
    rgb: [*c]const u8,
    width: c_int,
    height: c_int,
    stride: c_int,
    quality_factor: f32,
    output: *[*c]u8,
) usize;

extern "c" fn WebPEncodeLosslessRGBA(
    rgba: [*c]const u8,
    width: c_int,
    height: c_int,
    stride: c_int,
    output: *[*c]u8,
) usize;

extern "c" fn WebPEncodeLosslessRGB(
    rgb: [*c]const u8,
    width: c_int,
    height: c_int,
    stride: c_int,
    output: *[*c]u8,
) usize;

// Simple decoding API (returns allocated buffer via WebPMalloc)
extern "c" fn WebPDecodeRGBA(
    data: [*c]const u8,
    data_size: usize,
    width: *c_int,
    height: *c_int,
) ?[*]u8;

extern "c" fn WebPDecodeRGB(
    data: [*c]const u8,
    data_size: usize,
    width: *c_int,
    height: *c_int,
) ?[*]u8;

// Memory management
extern "c" fn WebPFree(ptr: ?*anyopaque) void;

// Magic number validation
extern "c" fn WebPGetInfo(
    data: [*c]const u8,
    data_size: usize,
    width: *c_int,
    height: *c_int,
) c_int;

// ============================================================================
// Error Handling
// ============================================================================

pub const WebPError = error{
    InitFailed,
    EncodeFailed,
    DecodeFailed,
    OutOfMemory,
    InvalidQuality,
    InvalidImage,
};

// ============================================================================
// WebP Encoding
// ============================================================================

/// Encode ImageBuffer to WebP with given quality
///
/// Quality: 0-100 (0 = smallest file, 100 = best quality)
/// Quality 100: Triggers lossless encoding
/// Quality < 100: Lossy encoding with specified quality
///
/// Safety: Returns owned slice, caller must free with allocator
/// Tiger Style: Quality bounded 0-100, explicit error handling
pub fn encodeWebP(
    allocator: Allocator,
    buffer: *const ImageBuffer,
    quality: u8,
) ![]u8 {
    // Assertions (Tiger Style: 2+)
    std.debug.assert(buffer.width > 0 and buffer.width <= 16383); // WebP max dimension
    std.debug.assert(buffer.height > 0 and buffer.height <= 16383);
    std.debug.assert(buffer.channels == 3 or buffer.channels == 4);
    std.debug.assert(quality <= 100);

    // WebP API output pointer (allocated via WebPMalloc)
    var webp_output: [*c]u8 = null;
    var webp_size: usize = 0;

    // Encode based on channels and quality
    const width_int: c_int = @intCast(buffer.width);
    const height_int: c_int = @intCast(buffer.height);
    const stride: c_int = @intCast(buffer.width * buffer.channels);

    if (quality == 100) {
        // Lossless encoding
        if (buffer.channels == 4) {
            webp_size = WebPEncodeLosslessRGBA(
                buffer.data.ptr,
                width_int,
                height_int,
                stride,
                &webp_output,
            );
        } else {
            webp_size = WebPEncodeLosslessRGB(
                buffer.data.ptr,
                width_int,
                height_int,
                stride,
                &webp_output,
            );
        }
    } else {
        // Lossy encoding
        const quality_float: f32 = @floatFromInt(quality);
        if (buffer.channels == 4) {
            webp_size = WebPEncodeRGBA(
                buffer.data.ptr,
                width_int,
                height_int,
                stride,
                quality_float,
                &webp_output,
            );
        } else {
            webp_size = WebPEncodeRGB(
                buffer.data.ptr,
                width_int,
                height_int,
                stride,
                quality_float,
                &webp_output,
            );
        }
    }

    // Check encoding success
    if (webp_size == 0 or webp_output == null) {
        if (webp_output != null) WebPFree(webp_output);
        return WebPError.EncodeFailed;
    }

    // Copy to our allocator (WebP uses its own malloc)
    const result = try allocator.alloc(u8, webp_size);
    errdefer allocator.free(result);

    @memcpy(result, webp_output[0..webp_size]);

    // Free WebP's allocated buffer
    WebPFree(webp_output);

    // Validate output (WebP magic: "RIFF....WEBP")
    std.debug.assert(result.len >= 12);
    std.debug.assert(result[0] == 'R' and result[1] == 'I' and result[2] == 'F' and result[3] == 'F');
    std.debug.assert(result[8] == 'W' and result[9] == 'E' and result[10] == 'B' and result[11] == 'P');

    return result;
}

// ============================================================================
// WebP Decoding
// ============================================================================

/// Decode WebP data to ImageBuffer
///
/// **IMPORTANT**: Always returns RGBA (4 channels) for consistency,
/// even if the source WebP image is RGB. This simplifies downstream
/// processing and ensures consistent memory layout.
///
/// Safety: Allocates ImageBuffer, caller must call buffer.deinit()
/// Tiger Style: Validates magic bytes, explicit error handling
pub fn decodeWebP(
    allocator: Allocator,
    data: []const u8,
) !ImageBuffer {
    // Pre-conditions (Tiger Style: 2+)
    const MAX_WEBP_SIZE: usize = 100 * 1024 * 1024; // 100MB
    std.debug.assert(data.len > 0);
    std.debug.assert(data.len <= MAX_WEBP_SIZE);

    // Validate WebP magic bytes (RIFF....WEBP)
    if (data.len < 12 or
        data[0] != 'R' or data[1] != 'I' or data[2] != 'F' or data[3] != 'F' or
        data[8] != 'W' or data[9] != 'E' or data[10] != 'B' or data[11] != 'P')
    {
        return WebPError.InvalidImage;
    }

    // Get image info first
    var width: c_int = 0;
    var height: c_int = 0;
    const info_result = WebPGetInfo(data.ptr, data.len, &width, &height);
    if (info_result == 0) {
        return WebPError.InvalidImage;
    }

    // Validate dimensions
    if (width <= 0 or height <= 0 or width > 16383 or height > 16383) {
        return WebPError.InvalidImage;
    }

    // Decode to RGBA (always 4 channels for consistency)
    const decoded_ptr = WebPDecodeRGBA(data.ptr, data.len, &width, &height);
    if (decoded_ptr == null) {
        return WebPError.DecodeFailed;
    }
    defer WebPFree(decoded_ptr);

    // Copy to our allocator
    const width_u32: u32 = @intCast(width);
    const height_u32: u32 = @intCast(height);
    const channels: u8 = 4; // WebPDecodeRGBA always returns RGBA
    const pixel_count: usize = @as(usize, width_u32) * @as(usize, height_u32) * @as(usize, channels);

    const pixel_data = try allocator.alloc(u8, pixel_count);
    errdefer allocator.free(pixel_data);

    @memcpy(pixel_data, decoded_ptr.?[0..pixel_count]);

    // Post-condition: Valid buffer created
    std.debug.assert(pixel_data.len == pixel_count);
    std.debug.assert(width_u32 > 0 and height_u32 > 0);

    return ImageBuffer{
        .data = pixel_data,
        .width = width_u32,
        .height = height_u32,
        .stride = width_u32 * channels,
        .channels = channels,
        .allocator = allocator,
        .color_space = 0, // sRGB default
    };
}

// ============================================================================
// Tests
// ============================================================================

test "WebP encode/decode roundtrip RGBA" {
    const allocator = std.testing.allocator;

    // Create test image (4x4 RGBA gradient)
    const width: u32 = 4;
    const height: u32 = 4;
    const channels: u8 = 4;
    const pixel_count = width * height * channels;

    const pixel_data = try allocator.alloc(u8, pixel_count);
    defer allocator.free(pixel_data);

    // Fill with gradient pattern
    for (0..height) |y| {
        for (0..width) |x| {
            const idx = (y * width + x) * channels;
            pixel_data[idx + 0] = @intCast(x * 60); // R
            pixel_data[idx + 1] = @intCast(y * 60); // G
            pixel_data[idx + 2] = 128; // B
            pixel_data[idx + 3] = 255; // A
        }
    }

    const original = ImageBuffer{
        .data = pixel_data,
        .width = width,
        .height = height,
        .stride = width * channels,
        .channels = channels,
        .allocator = allocator,
        .color_space = 0,
    };

    // Encode to WebP (lossless for exact roundtrip)
    const encoded = try encodeWebP(allocator, &original, 100);
    defer allocator.free(encoded);

    // Validate WebP magic bytes
    try std.testing.expect(encoded.len >= 12);
    try std.testing.expectEqual(@as(u8, 'R'), encoded[0]);
    try std.testing.expectEqual(@as(u8, 'I'), encoded[1]);
    try std.testing.expectEqual(@as(u8, 'F'), encoded[2]);
    try std.testing.expectEqual(@as(u8, 'F'), encoded[3]);
    try std.testing.expectEqual(@as(u8, 'W'), encoded[8]);
    try std.testing.expectEqual(@as(u8, 'E'), encoded[9]);
    try std.testing.expectEqual(@as(u8, 'B'), encoded[10]);
    try std.testing.expectEqual(@as(u8, 'P'), encoded[11]);

    // Decode
    var decoded = try decodeWebP(allocator, encoded);
    defer decoded.deinit();

    // Verify dimensions
    try std.testing.expectEqual(width, decoded.width);
    try std.testing.expectEqual(height, decoded.height);
    try std.testing.expectEqual(channels, decoded.channels);

    // Verify pixel data matches (lossless should be exact)
    try std.testing.expectEqualSlices(u8, original.data, decoded.data);
}

test "WebP encode/decode roundtrip RGB" {
    const allocator = std.testing.allocator;

    // Create test image (4x4 RGB gradient)
    const width: u32 = 4;
    const height: u32 = 4;
    const channels: u8 = 3;
    const pixel_count = width * height * channels;

    const pixel_data = try allocator.alloc(u8, pixel_count);
    defer allocator.free(pixel_data);

    // Fill with gradient pattern
    for (0..height) |y| {
        for (0..width) |x| {
            const idx = (y * width + x) * channels;
            pixel_data[idx + 0] = @intCast(x * 60); // R
            pixel_data[idx + 1] = @intCast(y * 60); // G
            pixel_data[idx + 2] = 128; // B
        }
    }

    const original = ImageBuffer{
        .data = pixel_data,
        .width = width,
        .height = height,
        .stride = width * channels,
        .channels = channels,
        .allocator = allocator,
        .color_space = 0,
    };

    // Encode to WebP (lossless)
    const encoded = try encodeWebP(allocator, &original, 100);
    defer allocator.free(encoded);

    // Validate WebP magic bytes
    try std.testing.expect(encoded.len >= 12);
    try std.testing.expectEqual(@as(u8, 'R'), encoded[0]);

    // Decode (will be RGBA)
    var decoded = try decodeWebP(allocator, encoded);
    defer decoded.deinit();

    // Verify dimensions
    try std.testing.expectEqual(width, decoded.width);
    try std.testing.expectEqual(height, decoded.height);
    try std.testing.expectEqual(@as(u8, 4), decoded.channels); // WebP decode returns RGBA

    // Verify RGB channels match (ignore alpha)
    for (0..height) |y| {
        for (0..width) |x| {
            const original_idx = (y * width + x) * 3;
            const decoded_idx = (y * width + x) * 4;

            try std.testing.expectEqual(original.data[original_idx + 0], decoded.data[decoded_idx + 0]); // R
            try std.testing.expectEqual(original.data[original_idx + 1], decoded.data[decoded_idx + 1]); // G
            try std.testing.expectEqual(original.data[original_idx + 2], decoded.data[decoded_idx + 2]); // B
            // Alpha should be 255 (opaque)
            try std.testing.expectEqual(@as(u8, 255), decoded.data[decoded_idx + 3]);
        }
    }
}

test "WebP lossy encoding quality levels" {
    const allocator = std.testing.allocator;

    // Create test image
    const width: u32 = 8;
    const height: u32 = 8;
    const channels: u8 = 3;
    const pixel_count = width * height * channels;

    const pixel_data = try allocator.alloc(u8, pixel_count);
    defer allocator.free(pixel_data);

    // Fill with pattern
    for (0..height) |y| {
        for (0..width) |x| {
            const idx = (y * width + x) * channels;
            pixel_data[idx + 0] = @intCast((x * y) % 256);
            pixel_data[idx + 1] = @intCast((x + y) % 256);
            pixel_data[idx + 2] = @intCast((x * 30) % 256);
        }
    }

    const buffer = ImageBuffer{
        .data = pixel_data,
        .width = width,
        .height = height,
        .stride = width * channels,
        .channels = channels,
        .allocator = allocator,
        .color_space = 0,
    };

    // Test different quality levels
    const qualities = [_]u8{ 10, 50, 90, 100 };
    var prev_size: usize = 0;

    for (qualities) |quality| {
        const encoded = try encodeWebP(allocator, &buffer, quality);
        defer allocator.free(encoded);

        // Higher quality should generally produce larger files
        if (prev_size > 0 and quality > 10) {
            // Note: This is a general trend but not guaranteed for all images
            // We just verify it's a valid WebP file
            try std.testing.expect(encoded.len >= 12);
        }
        prev_size = encoded.len;

        // Verify can decode
        var decoded = try decodeWebP(allocator, encoded);
        defer decoded.deinit();

        try std.testing.expectEqual(width, decoded.width);
        try std.testing.expectEqual(height, decoded.height);
    }
}

test "WebP invalid data handling" {
    const allocator = std.testing.allocator;

    // Test invalid magic bytes
    const invalid_data = [_]u8{ 0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46, 0x00, 0x01 };
    const result = decodeWebP(allocator, &invalid_data);
    try std.testing.expectError(WebPError.InvalidImage, result);

    // Test truncated data
    const truncated = [_]u8{ 'R', 'I', 'F', 'F' };
    const result2 = decodeWebP(allocator, &truncated);
    try std.testing.expectError(WebPError.InvalidImage, result2);
}
