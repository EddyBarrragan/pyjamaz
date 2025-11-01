const std = @import("std");
const Allocator = std.mem.Allocator;
const ImageBuffer = @import("../types/image_buffer.zig").ImageBuffer;
const ImageFormat = @import("../types/image_metadata.zig").ImageFormat;

const jpeg_codec = @import("jpeg.zig");
const png_codec = @import("png.zig");
const webp_codec = @import("webp.zig");
const avif_codec = @import("avif.zig");

/// Unified Codec API for Pyjamaz
///
/// This module provides a consistent high-level interface for all image codecs,
/// abstracting away the differences between JPEG, PNG, WebP, and AVIF.
///
/// Tiger Style: All operations bounded, explicit error handling, zero dependencies.

// ============================================================================
// Error Types
// ============================================================================

pub const CodecError = error{
    UnsupportedFormat,
    EncodeFailed,
    DecodeFailed,
    InvalidQuality,
    InvalidImage,
    InvalidData,
};

// ============================================================================
// Encoding Operations
// ============================================================================

/// Encode ImageBuffer to specified format
///
/// Format: Target image format (JPEG, PNG, WebP, AVIF)
/// Quality: 0-100 for JPEG/WebP/AVIF, 0-9 for PNG compression
///
/// Safety: Returns owned slice, caller must free with allocator
/// Tiger Style: Quality bounded, format validated, magic numbers verified
pub fn encode(
    allocator: Allocator,
    buffer: *const ImageBuffer,
    format: ImageFormat,
    quality: u8,
) ![]u8 {
    // Pre-conditions (Tiger Style: 2+)
    std.debug.assert(buffer.width > 0 and buffer.width <= 65535);
    std.debug.assert(buffer.height > 0 and buffer.height <= 65535);
    std.debug.assert(buffer.channels == 3 or buffer.channels == 4);

    // Validate quality based on format
    switch (format) {
        .jpeg, .webp, .avif, .png => std.debug.assert(quality <= 100),
        .unknown => return CodecError.UnsupportedFormat,
    }

    // Warn if encoding RGBA to format that doesn't support alpha
    if (buffer.channels == 4 and !supportsAlpha(format)) {
        std.log.warn("Encoding RGBA image to {s} will discard alpha channel", .{@tagName(format)});
    }

    // Encode using native codecs
    const encoded = try switch (format) {
        .jpeg => jpeg_codec.encodeJPEG(allocator, buffer, quality, false),
        .png => png_codec.encodePNG(allocator, buffer, @min(quality, 9)),
        .webp => webp_codec.encodeWebP(allocator, buffer, quality),
        .avif => avif_codec.encodeAVIF(allocator, buffer, quality),
        .unknown => CodecError.UnsupportedFormat,
    };

    // Post-conditions: Validate encoded data (Tiger Style)
    std.debug.assert(encoded.len > 0);
    std.debug.assert(encoded.len < 100 * 1024 * 1024); // Sanity check: <100MB

    // Verify magic numbers for defense in depth
    try verifyMagicNumber(encoded, format);

    return encoded;
}

/// Encode with explicit speed/quality tradeoff (AVIF only)
///
/// For AVIF, speed parameter controls encoding time vs compression:
/// - AVIF_SPEED_DEFAULT (-1): Library default (balanced)
/// - AVIF_SPEED_SLOWEST (0): Best compression, slowest
/// - 4-6: Good balance for web use
/// - AVIF_SPEED_FASTEST (10): Fastest, larger files
///
/// For other formats, speed parameter is ignored.
///
/// Tiger Style: Bounded speed (-1 to 10), quality (0-100)
pub fn encodeWithSpeed(
    allocator: Allocator,
    buffer: *const ImageBuffer,
    format: ImageFormat,
    quality: u8,
    speed: i32,
) ![]u8 {
    // Pre-conditions
    std.debug.assert(buffer.width > 0 and buffer.width <= 65535);
    std.debug.assert(buffer.height > 0 and buffer.height <= 65535);
    std.debug.assert(buffer.channels == 3 or buffer.channels == 4);
    std.debug.assert(quality <= 100);
    std.debug.assert(speed >= -1 and speed <= 10);

    // Only AVIF supports speed parameter
    if (format == .avif) {
        return avif_codec.encodeAVIFWithSpeed(allocator, buffer, quality, @intCast(speed));
    } else {
        // For other formats, ignore speed and use standard encode
        return encode(allocator, buffer, format, quality);
    }
}

// ============================================================================
// Decoding Operations
// ============================================================================

/// Decode image data to ImageBuffer
///
/// Automatically detects format from magic bytes and decodes accordingly.
///
/// Safety: Returns owned ImageBuffer, caller must call .deinit()
/// Tiger Style: Validates magic bytes, explicit error handling
pub fn decode(
    allocator: Allocator,
    data: []const u8,
) !ImageBuffer {
    // Pre-conditions (Tiger Style: 2+)
    std.debug.assert(data.len > 0);
    std.debug.assert(data.len < 100 * 1024 * 1024); // Max 100MB

    // Detect format from magic bytes
    const format = try detectFormat(data);

    // Decode using appropriate codec
    const buffer = try switch (format) {
        .jpeg => jpeg_codec.decodeJPEG(allocator, data),
        .png => png_codec.decodePNG(allocator, data),
        .webp => webp_codec.decodeWebP(allocator, data),
        .avif => avif_codec.decodeAVIF(allocator, data),
        .unknown => CodecError.UnsupportedFormat,
    };

    // Post-conditions
    std.debug.assert(buffer.width > 0 and buffer.width <= 65535);
    std.debug.assert(buffer.height > 0 and buffer.height <= 65535);
    std.debug.assert(buffer.channels == 3 or buffer.channels == 4);

    return buffer;
}

/// Decode image data with explicit format (skip detection)
///
/// Use this when you already know the format to skip magic byte detection.
///
/// Safety: Returns owned ImageBuffer, caller must call .deinit()
/// Tiger Style: Validates input, explicit error handling
pub fn decodeWithFormat(
    allocator: Allocator,
    data: []const u8,
    format: ImageFormat,
) !ImageBuffer {
    // Pre-conditions
    std.debug.assert(data.len > 0);
    std.debug.assert(data.len < 100 * 1024 * 1024); // Max 100MB

    // Decode using specified codec
    const buffer = try switch (format) {
        .jpeg => jpeg_codec.decodeJPEG(allocator, data),
        .png => png_codec.decodePNG(allocator, data),
        .webp => webp_codec.decodeWebP(allocator, data),
        .avif => avif_codec.decodeAVIF(allocator, data),
        .unknown => CodecError.UnsupportedFormat,
    };

    // Post-conditions
    std.debug.assert(buffer.width > 0 and buffer.width <= 65535);
    std.debug.assert(buffer.height > 0 and buffer.height <= 65535);
    std.debug.assert(buffer.channels == 3 or buffer.channels == 4);

    return buffer;
}

// ============================================================================
// Format Detection
// ============================================================================

/// Detect image format from magic bytes
///
/// Returns the detected format or .unknown if not recognized.
///
/// Tiger Style: Bounded checks, explicit magic number validation
pub fn detectFormat(data: []const u8) !ImageFormat {
    // Pre-condition
    std.debug.assert(data.len > 0);

    // Need at least 12 bytes to detect most formats
    if (data.len < 12) {
        return ImageFormat.unknown;
    }

    // JPEG: FF D8 FF
    if (data[0] == 0xFF and data[1] == 0xD8 and data[2] == 0xFF) {
        return ImageFormat.jpeg;
    }

    // PNG: 89 50 4E 47 0D 0A 1A 0A
    if (data[0] == 0x89 and data[1] == 0x50 and data[2] == 0x4E and data[3] == 0x47) {
        return ImageFormat.png;
    }

    // WebP: RIFF....WEBP
    if (data[0] == 'R' and data[1] == 'I' and data[2] == 'F' and data[3] == 'F' and
        data[8] == 'W' and data[9] == 'E' and data[10] == 'B' and data[11] == 'P')
    {
        return ImageFormat.webp;
    }

    // AVIF: ....ftyp (ftyp box at offset 4)
    if (data[4] == 'f' and data[5] == 't' and data[6] == 'y' and data[7] == 'p') {
        return ImageFormat.avif;
    }

    // Unknown format
    return ImageFormat.unknown;
}

// ============================================================================
// Validation Helpers
// ============================================================================

/// Verify magic number matches expected format
///
/// Returns error if magic number doesn't match format.
///
/// Tiger Style: Explicit validation, bounded checks
fn verifyMagicNumber(data: []const u8, format: ImageFormat) !void {
    std.debug.assert(data.len >= 12); // Minimum for all formats

    switch (format) {
        .jpeg => {
            if (data.len < 2 or data[0] != 0xFF or data[1] != 0xD8) {
                return CodecError.EncodeFailed;
            }
        },
        .png => {
            if (data.len < 8 or
                data[0] != 0x89 or data[1] != 0x50 or
                data[2] != 0x4E or data[3] != 0x47)
            {
                return CodecError.EncodeFailed;
            }
        },
        .webp => {
            if (data.len < 12 or
                data[0] != 'R' or data[1] != 'I' or data[2] != 'F' or data[3] != 'F' or
                data[8] != 'W' or data[9] != 'E' or data[10] != 'B' or data[11] != 'P')
            {
                return CodecError.EncodeFailed;
            }
        },
        .avif => {
            if (data.len < 8 or
                data[4] != 'f' or data[5] != 't' or
                data[6] != 'y' or data[7] != 'p')
            {
                return CodecError.EncodeFailed;
            }
        },
        .unknown => return CodecError.UnsupportedFormat,
    }
}

// ============================================================================
// Format Capability Queries
// ============================================================================

/// Check if format supports alpha channel
pub fn supportsAlpha(format: ImageFormat) bool {
    return switch (format) {
        .png, .webp, .avif => true,
        .jpeg => false,
        .unknown => false,
    };
}

/// Check if format supports lossless compression
pub fn supportsLossless(format: ImageFormat) bool {
    return switch (format) {
        .png => true, // Always lossless
        .webp, .avif => true, // Supports both lossy and lossless
        .jpeg => false, // Always lossy
        .unknown => false,
    };
}

/// Get recommended default quality for format
pub fn getDefaultQuality(format: ImageFormat) u8 {
    return switch (format) {
        .jpeg => 85, // Good balance
        .webp => 80, // Slightly lower (WebP more efficient)
        .avif => 75, // Even lower (AVIF very efficient)
        .png => 6, // Middle compression
        .unknown => 85,
    };
}

/// Get quality range for format
pub fn getQualityRange(format: ImageFormat) struct { min: u8, max: u8 } {
    return switch (format) {
        .jpeg => .{ .min = 1, .max = 100 }, // JPEG min is 1
        .webp, .avif => .{ .min = 0, .max = 100 },
        .png => .{ .min = 0, .max = 9 },
        .unknown => .{ .min = 1, .max = 100 },
    };
}

/// Get max dimension for format
pub fn getMaxDimension(format: ImageFormat) u32 {
    return switch (format) {
        .jpeg, .png => 65535, // 16-bit max
        .webp => 16383, // WebP limitation
        .avif => 65536, // AVIF max
        .unknown => 65535,
    };
}

// ============================================================================
// Unit Tests
// ============================================================================

test "format detection from magic bytes" {
    const testing = std.testing;

    // JPEG magic
    const jpeg_data = [_]u8{ 0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46, 0x00, 0x01 };
    try testing.expectEqual(ImageFormat.jpeg, try detectFormat(&jpeg_data));

    // PNG magic
    const png_data = [_]u8{ 0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D };
    try testing.expectEqual(ImageFormat.png, try detectFormat(&png_data));

    // WebP magic
    const webp_data = [_]u8{ 'R', 'I', 'F', 'F', 0x00, 0x00, 0x00, 0x00, 'W', 'E', 'B', 'P' };
    try testing.expectEqual(ImageFormat.webp, try detectFormat(&webp_data));

    // AVIF magic
    const avif_data = [_]u8{ 0x00, 0x00, 0x00, 0x20, 'f', 't', 'y', 'p', 'a', 'v', 'i', 'f' };
    try testing.expectEqual(ImageFormat.avif, try detectFormat(&avif_data));

    // Unknown format
    const unknown_data = [_]u8{ 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00 };
    try testing.expectEqual(ImageFormat.unknown, try detectFormat(&unknown_data));
}

test "format capabilities" {
    const testing = std.testing;

    // Alpha support
    try testing.expect(!supportsAlpha(.jpeg));
    try testing.expect(supportsAlpha(.png));
    try testing.expect(supportsAlpha(.webp));
    try testing.expect(supportsAlpha(.avif));

    // Lossless support
    try testing.expect(!supportsLossless(.jpeg));
    try testing.expect(supportsLossless(.png));
    try testing.expect(supportsLossless(.webp));
    try testing.expect(supportsLossless(.avif));
}

test "default quality values" {
    const testing = std.testing;

    try testing.expectEqual(@as(u8, 85), getDefaultQuality(.jpeg));
    try testing.expectEqual(@as(u8, 80), getDefaultQuality(.webp));
    try testing.expectEqual(@as(u8, 75), getDefaultQuality(.avif));
    try testing.expectEqual(@as(u8, 6), getDefaultQuality(.png));
}

test "quality ranges" {
    const testing = std.testing;

    const jpeg_range = getQualityRange(.jpeg);
    try testing.expectEqual(@as(u8, 1), jpeg_range.min);
    try testing.expectEqual(@as(u8, 100), jpeg_range.max);

    const png_range = getQualityRange(.png);
    try testing.expectEqual(@as(u8, 0), png_range.min);
    try testing.expectEqual(@as(u8, 9), png_range.max);
}

test "max dimensions" {
    const testing = std.testing;

    try testing.expectEqual(@as(u32, 65535), getMaxDimension(.jpeg));
    try testing.expectEqual(@as(u32, 65535), getMaxDimension(.png));
    try testing.expectEqual(@as(u32, 16383), getMaxDimension(.webp));
    try testing.expectEqual(@as(u32, 65536), getMaxDimension(.avif));
}

test "encode/decode roundtrip with format detection" {
    const testing = std.testing;

    // Create small test image (8x8 RGB)
    var buffer = try ImageBuffer.init(testing.allocator, 8, 8, 3);
    defer buffer.deinit();

    // Fill with gradient pattern
    var y: u32 = 0;
    while (y < 8) : (y += 1) {
        var x: u32 = 0;
        while (x < 8) : (x += 1) {
            const offset = (y * 8 + x) * 3;
            buffer.data[offset + 0] = @truncate(x * 30); // R
            buffer.data[offset + 1] = @truncate(y * 30); // G
            buffer.data[offset + 2] = 128; // B
        }
    }

    // Test PNG (lossless)
    {
        const encoded = try encode(testing.allocator, &buffer, .png, 6);
        defer testing.allocator.free(encoded);

        // Detect format
        const detected_format = try detectFormat(encoded);
        try testing.expectEqual(ImageFormat.png, detected_format);

        // Decode
        var decoded = try decode(testing.allocator, encoded);
        defer decoded.deinit();

        try testing.expectEqual(@as(u32, 8), decoded.width);
        try testing.expectEqual(@as(u32, 8), decoded.height);
        try testing.expectEqual(@as(u8, 3), decoded.channels);

        // PNG is lossless, so data should match
        try testing.expectEqualSlices(u8, buffer.data, decoded.data);
    }

    // Test WebP (lossless quality=100)
    {
        const encoded = try encode(testing.allocator, &buffer, .webp, 100);
        defer testing.allocator.free(encoded);

        const detected_format = try detectFormat(encoded);
        try testing.expectEqual(ImageFormat.webp, detected_format);

        var decoded = try decode(testing.allocator, encoded);
        defer decoded.deinit();

        try testing.expectEqual(@as(u32, 8), decoded.width);
        try testing.expectEqual(@as(u32, 8), decoded.height);
        try testing.expectEqual(@as(u8, 4), decoded.channels); // WebP decode returns RGBA
    }
}
