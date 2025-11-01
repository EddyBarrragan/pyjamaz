const std = @import("std");
const Allocator = std.mem.Allocator;
const codec_api = @import("codecs/api.zig");
const ImageBuffer = @import("types/image_buffer.zig").ImageBuffer;
const ImageMetadata = @import("types/image_metadata.zig").ImageMetadata;
const ImageFormat = @import("types/image_metadata.zig").ImageFormat;

/// High-level image operations using native codecs
///
/// This module provides the main image processing functions for Pyjamaz:
/// - decodeImage: Load and normalize image from file
/// - resizeImage: Resize with various modes
/// - normalizeColorSpace: Convert to sRGB
///
/// Tiger Style: All functions have bounded operations, explicit error handling,
/// and return owned memory that must be freed by caller.

/// Decode image from file path
///
/// Steps:
/// 1. Read image file into memory
/// 2. Detect format from magic bytes
/// 3. Decode using native codec
/// 4. Return normalized ImageBuffer (RGB/RGBA in sRGB)
///
/// Note: EXIF auto-rotation not yet implemented (future enhancement)
///
/// Safety: Returns ImageBuffer, caller must call deinit()
/// Tiger Style: Bounded file size, explicit error handling
pub fn decodeImage(allocator: Allocator, path: []const u8) !ImageBuffer {
    // Pre-conditions (Tiger Style: 2+)
    std.debug.assert(path.len > 0);
    std.debug.assert(path.len < std.fs.max_path_bytes);

    // Read entire file into memory (bounded to 100MB)
    const MAX_FILE_SIZE = 100 * 1024 * 1024; // 100MB
    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();

    const file_size = (try file.stat()).size;
    if (file_size == 0 or file_size > MAX_FILE_SIZE) {
        return error.InvalidFileSize;
    }

    const bytes = try file.readToEndAlloc(allocator, MAX_FILE_SIZE);
    defer allocator.free(bytes);

    // Pre-condition: File has content
    std.debug.assert(bytes.len > 0);
    std.debug.assert(bytes.len <= MAX_FILE_SIZE);

    // Decode using native codec (auto-detects format from magic bytes)
    const buffer = try codec_api.decode(allocator, bytes);

    // Post-conditions (Tiger Style: 2+)
    std.debug.assert(buffer.width > 0 and buffer.width <= 65535);
    std.debug.assert(buffer.height > 0 and buffer.height <= 65535);
    std.debug.assert(buffer.channels == 3 or buffer.channels == 4);
    std.debug.assert(buffer.data.len == @as(usize, buffer.stride) * @as(usize, buffer.height));

    return buffer;
}

/// Decode image from memory buffer (v0.4.0 - for perceptual metrics)
///
/// Steps:
/// 1. Detect format from magic bytes
/// 2. Decode using native codec
/// 3. Return normalized ImageBuffer (RGB/RGBA in sRGB)
///
/// Note: EXIF auto-rotation not yet implemented (future enhancement)
///
/// Safety: Returns ImageBuffer, caller must call deinit()
/// Tiger Style: Bounded input size, explicit error handling
pub fn decodeImageFromMemory(allocator: Allocator, bytes: []const u8) !ImageBuffer {
    // Pre-conditions (Tiger Style: 2+)
    std.debug.assert(bytes.len > 0);
    const MAX_SIZE = 100 * 1024 * 1024; // 100MB
    std.debug.assert(bytes.len <= MAX_SIZE);

    // Decode using native codec (auto-detects format)
    const buffer = try codec_api.decode(allocator, bytes);

    // Post-conditions (Tiger Style: 2+)
    std.debug.assert(buffer.width > 0 and buffer.width <= 65535);
    std.debug.assert(buffer.height > 0 and buffer.height <= 65535);
    std.debug.assert(buffer.channels == 3 or buffer.channels == 4);
    std.debug.assert(buffer.data.len == @as(usize, buffer.stride) * @as(usize, buffer.height));

    return buffer;
}

/// Resize mode for image transformations
pub const ResizeMode = enum {
    /// Resize to exact dimensions (may distort aspect ratio)
    exact,

    /// Resize to fit within dimensions (preserve aspect ratio)
    contain,

    /// Resize to cover dimensions (preserve aspect ratio, crop if needed)
    cover,

    /// Only shrink, never upscale
    only_shrink,
};

/// Resize parameters
pub const ResizeParams = struct {
    /// Target width (0 = keep original)
    target_width: u32,

    /// Target height (0 = keep original)
    target_height: u32,

    /// Resize mode
    mode: ResizeMode,

    /// Apply sharpening after resize
    sharpen: bool,
};

/// Resize image according to parameters
///
/// Safety: Modifies buffer in place or returns error
/// Tiger Style: Bounded scale factors (0.01 to 10.0)
pub fn resizeImage(buffer: ImageBuffer, params: ResizeParams) !ImageBuffer {
    _ = buffer;
    _ = params;

    // TODO: Implement resize logic
    // This requires converting ImageBuffer back to VipsImage,
    // which needs vips_image_new_from_memory
    return error.NotImplemented;
}

/// ICC profile handling mode
pub const IccMode = enum {
    /// Keep original ICC profile
    keep,

    /// Convert to sRGB
    srgb,

    /// Discard ICC profile
    discard,
};

/// Normalize color space according to ICC mode
///
/// Safety: Returns new ImageBuffer, caller must deinit
pub fn normalizeColorSpace(
    allocator: Allocator,
    buffer: ImageBuffer,
    mode: IccMode,
) !ImageBuffer {
    _ = mode;

    // For now, we already convert to sRGB in decodeImage
    // TODO: Implement full ICC profile handling
    return buffer.clone(allocator);
}

/// Get image metadata from file without decoding pixels
///
/// Note: Currently requires full decode. Future optimization: parse headers only.
pub fn getImageMetadata(allocator: Allocator, path: []const u8) !ImageMetadata {
    // Pre-conditions
    std.debug.assert(path.len > 0);
    std.debug.assert(path.len < std.fs.max_path_bytes);

    // For now, we need to decode to get accurate metadata
    // TODO: Implement header-only parsing for each format
    var buffer = try decodeImage(allocator, path);
    defer buffer.deinit();

    // Detect format from file extension
    const format = detectFormatFromPath(path);

    const has_alpha = (buffer.channels == 4);

    return ImageMetadata.init(format, buffer.width, buffer.height, has_alpha);
}

/// Detect image format from file extension
fn detectFormatFromPath(path: []const u8) ImageFormat {
    if (std.mem.endsWith(u8, path, ".jpg") or std.mem.endsWith(u8, path, ".jpeg")) {
        return .jpeg;
    } else if (std.mem.endsWith(u8, path, ".png")) {
        return .png;
    } else if (std.mem.endsWith(u8, path, ".webp")) {
        return .webp;
    } else if (std.mem.endsWith(u8, path, ".avif")) {
        return .avif;
    } else {
        return .unknown;
    }
}

// ============================================================================
// Unit Tests
// ============================================================================

test "detectFormatFromPath recognizes extensions" {
    const testing = std.testing;

    try testing.expectEqual(ImageFormat.jpeg, detectFormatFromPath("test.jpg"));
    try testing.expectEqual(ImageFormat.jpeg, detectFormatFromPath("test.jpeg"));
    try testing.expectEqual(ImageFormat.png, detectFormatFromPath("test.png"));
    try testing.expectEqual(ImageFormat.webp, detectFormatFromPath("test.webp"));
    try testing.expectEqual(ImageFormat.avif, detectFormatFromPath("test.avif"));
    try testing.expectEqual(ImageFormat.unknown, detectFormatFromPath("test.bmp"));
}

// Note: Full integration tests require actual image files
// These will be in src/test/integration/
