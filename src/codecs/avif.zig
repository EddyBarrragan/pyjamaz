const std = @import("std");
const Allocator = std.mem.Allocator;
const ImageBuffer = @import("../types/image_buffer.zig").ImageBuffer;

/// AVIF codec using libavif
///
/// This module provides AVIF encoding and decoding using the libavif API.
/// libavif wraps libaom (encoder) and libdav1d (decoder) for AV1 image format.
///
/// Tiger Style: All operations bounded, explicit error handling, memory safety.

// ============================================================================
// C FFI Declarations (libavif)
// ============================================================================

pub const AVIF_PIXEL_FORMAT_YUV444: c_int = 0;
pub const AVIF_PIXEL_FORMAT_YUV422: c_int = 1;
pub const AVIF_PIXEL_FORMAT_YUV420: c_int = 2;
pub const AVIF_PIXEL_FORMAT_YUV400: c_int = 3;

pub const AVIF_PLANES_YUV: c_int = 1;
pub const AVIF_PLANES_ALL: c_int = 0x7F;

pub const AVIF_RANGE_LIMITED: c_int = 0;
pub const AVIF_RANGE_FULL: c_int = 1;

pub const AVIF_RESULT_OK: c_int = 0;

pub const AVIF_SPEED_DEFAULT: c_int = -1;
pub const AVIF_SPEED_SLOWEST: c_int = 0;
pub const AVIF_SPEED_FASTEST: c_int = 10;

// RGB format
pub const AVIF_RGB_FORMAT_RGB: c_int = 0;
pub const AVIF_RGB_FORMAT_RGBA: c_int = 1;
pub const AVIF_RGB_FORMAT_ABGR: c_int = 2;
pub const AVIF_RGB_FORMAT_ARGB: c_int = 3;
pub const AVIF_RGB_FORMAT_BGR: c_int = 4;
pub const AVIF_RGB_FORMAT_BGRA: c_int = 5;

// Color primaries
pub const AVIF_COLOR_PRIMARIES_SRGB: c_int = 1;

// Transfer characteristics
pub const AVIF_TRANSFER_CHARACTERISTICS_SRGB: c_int = 13;

// Matrix coefficients
pub const AVIF_MATRIX_COEFFICIENTS_BT601: c_int = 6;

const avifRGBImage = extern struct {
    width: u32,
    height: u32,
    depth: u32,
    format: c_int, // avifRGBFormat
    chromaUpsampling: c_int,
    chromaDownsampling: c_int,
    avoidLibYUV: c_int,
    ignoreAlpha: c_int,
    alphaPremultiplied: c_int,
    isFloat: c_int,
    maxThreads: c_int,
    pixels: [*c]u8,
    rowBytes: u32,
};

// avifImage structure (simplified - only fields we need to access)
const avifImage = extern struct {
    width: u32,
    height: u32,
    depth: u32,
    yuvFormat: c_int,
    yuvRange: c_int,
    yuvChromaSamplePosition: c_int,
    yuvPlanes: [3][*c]u8,
    yuvRowBytes: [3]u32,
    imageOwnsYUVPlanes: c_int,
    alphaPlane: [*c]u8,
    alphaRowBytes: u32,
    imageOwnsAlphaPlane: c_int,
    icc: avifRWData,
    colorPrimaries: c_int,
    transferCharacteristics: c_int,
    matrixCoefficients: c_int,
    // ... other fields omitted for brevity
};

// avifEncoder structure (must match C struct layout exactly)
const avifEncoder = extern struct {
    codecChoice: c_int,       // avifCodecChoice (enum)
    maxThreads: c_int,
    speed: c_int,
    keyframeInterval: c_int,
    timescale: u64,
    repetitionCount: c_int,
    extraLayerCount: u32,
    quality: c_int,
    qualityAlpha: c_int,
    // ... other fields omitted for brevity
};

const avifDecoder = opaque {};



const avifRWData = extern struct {
    data: [*c]u8,
    size: usize,
};

// Image operations
extern "c" fn avifImageCreate(width: u32, height: u32, depth: u32, format: c_int) ?*avifImage;
extern "c" fn avifImageDestroy(image: ?*avifImage) void;
extern "c" fn avifImageAllocatePlanes(image: *avifImage, planes: c_int) c_int;
extern "c" fn avifImageRGBToYUV(image: *avifImage, rgb: *const avifRGBImage) c_int;
extern "c" fn avifImageYUVToRGB(image: *const avifImage, rgb: *avifRGBImage) c_int;
extern "c" fn avifImageSetProfileICC(image: *avifImage, icc: [*c]const u8, iccSize: usize) void;
extern "c" fn avifImageSetMetadataExif(image: *avifImage, exif: [*c]const u8, exifSize: usize) void;

// RGB image operations
extern "c" fn avifRGBImageSetDefaults(rgb: *avifRGBImage, image: *const avifImage) void;
extern "c" fn avifRGBImageAllocatePixels(rgb: *avifRGBImage) c_int;
extern "c" fn avifRGBImageFreePixels(rgb: *avifRGBImage) void;

// Encoder operations
extern "c" fn avifEncoderCreate() ?*avifEncoder;
extern "c" fn avifEncoderDestroy(encoder: ?*avifEncoder) void;
extern "c" fn avifEncoderWrite(encoder: *avifEncoder, image: *const avifImage, output: *avifRWData) c_int;
extern "c" fn avifEncoderSetCodecSpecificOption(encoder: *avifEncoder, key: [*c]const u8, value: [*c]const u8) c_int;

// Decoder operations
extern "c" fn avifDecoderCreate() ?*avifDecoder;
extern "c" fn avifDecoderDestroy(decoder: ?*avifDecoder) void;
extern "c" fn avifDecoderReadMemory(decoder: *avifDecoder, image: *avifImage, data: [*c]const u8, size: usize) c_int;
extern "c" fn avifDecoderSetIOMemory(decoder: *avifDecoder, data: [*c]const u8, size: usize) c_int;
extern "c" fn avifDecoderParse(decoder: *avifDecoder) c_int;
extern "c" fn avifDecoderNextImage(decoder: *avifDecoder) c_int;

// Memory management
extern "c" fn avifRWDataFree(raw: *avifRWData) void;

// Encoder quality/speed access (via struct fields - we'll access via pointer)
// Note: avifEncoder is opaque, so we can't access fields directly in Zig
// We'll use quality parameter directly in the encode function

// ============================================================================
// Error Handling
// ============================================================================

pub const AVIFError = error{
    InitFailed,
    EncodeFailed,
    DecodeFailed,
    OutOfMemory,
    InvalidQuality,
    InvalidImage,
    InvalidSpeed,
};

// ============================================================================
// AVIF Encoding
// ============================================================================

/// Encode ImageBuffer to AVIF with given quality
///
/// Quality: 0-100 (0 = smallest file, 100 = best quality, lossless)
/// Speed: -1 to 10 (-1 = default, 0 = slowest/best, 10 = fastest)
///
/// Safety: Returns owned slice, caller must free with allocator
/// Tiger Style: Quality bounded 0-100, explicit error handling
pub fn encodeAVIF(
    allocator: Allocator,
    buffer: *const ImageBuffer,
    quality: u8,
) ![]u8 {
    return encodeAVIFWithSpeed(allocator, buffer, quality, AVIF_SPEED_DEFAULT);
}

/// Encode AVIF with explicit speed/quality tradeoff
///
/// Speed parameter controls encoding time vs compression:
/// - AVIF_SPEED_DEFAULT (-1): Library default (balanced)
/// - AVIF_SPEED_SLOWEST (0): Best compression, slowest (for production assets)
/// - 4-6: Good balance for web use
/// - AVIF_SPEED_FASTEST (10): Fastest, larger files (for previews)
///
/// Tiger Style: Bounded speed (-1 to 10), quality (0-100)
pub fn encodeAVIFWithSpeed(
    allocator: Allocator,
    buffer: *const ImageBuffer,
    quality: u8,
    speed: c_int,
) ![]u8 {
    // Assertions (Tiger Style: 2+)
    std.debug.assert(buffer.width > 0 and buffer.width <= 65536); // AVIF max dimension
    std.debug.assert(buffer.height > 0 and buffer.height <= 65536);
    std.debug.assert(buffer.channels == 3 or buffer.channels == 4);
    std.debug.assert(quality <= 100);
    std.debug.assert(speed >= -1 and speed <= 10);

    // Create AVIF image (8-bit depth, YUV420 for compatibility)
    const avif_image = avifImageCreate(
        buffer.width,
        buffer.height,
        8, // 8-bit depth
        AVIF_PIXEL_FORMAT_YUV420,
    ) orelse return AVIFError.InitFailed;
    defer avifImageDestroy(avif_image);

    // Set up RGB image from our buffer
    var rgb_image: avifRGBImage = undefined;
    avifRGBImageSetDefaults(&rgb_image, avif_image);

    rgb_image.width = buffer.width;
    rgb_image.height = buffer.height;
    rgb_image.depth = 8;
    rgb_image.format = if (buffer.channels == 4) AVIF_RGB_FORMAT_RGBA else AVIF_RGB_FORMAT_RGB;
    rgb_image.pixels = @constCast(buffer.data.ptr);
    rgb_image.rowBytes = buffer.width * buffer.channels;

    // Allocate YUV planes before conversion
    const allocate_result = avifImageAllocatePlanes(avif_image, AVIF_PLANES_YUV);
    if (allocate_result != AVIF_RESULT_OK) {
        return AVIFError.InitFailed;
    }

    // Convert RGB to YUV
    const convert_result = avifImageRGBToYUV(avif_image, &rgb_image);
    if (convert_result != AVIF_RESULT_OK) {
        return AVIFError.EncodeFailed;
    }

    // Create encoder
    const encoder = avifEncoderCreate() orelse return AVIFError.InitFailed;
    defer avifEncoderDestroy(encoder);

    // Set encoder parameters (now we can access fields directly)
    encoder.maxThreads = 10; // Use multiple threads for encoding
    encoder.speed = speed; // Encoding speed preset

    // Set quality (0-100 scale, where 100 = lossless)
    // Note: minQuantizer/maxQuantizer are deprecated, use quality instead
    encoder.quality = @as(c_int, quality);
    encoder.qualityAlpha = @as(c_int, quality);

    // Encode image
    var output: avifRWData = .{ .data = null, .size = 0 };
    defer avifRWDataFree(&output);

    const encode_result = avifEncoderWrite(encoder, avif_image, &output);
    if (encode_result != AVIF_RESULT_OK or output.size == 0) {
        return AVIFError.EncodeFailed;
    }

    // Copy to our allocator
    const result = try allocator.alloc(u8, output.size);
    errdefer allocator.free(result);

    @memcpy(result, output.data[0..output.size]);

    // Validate output (AVIF magic: starts with ftyp box)
    std.debug.assert(result.len >= 12);
    std.debug.assert(result[4] == 'f' and result[5] == 't' and result[6] == 'y' and result[7] == 'p');

    return result;
}

// ============================================================================
// AVIF Decoding
// ============================================================================

/// Decode AVIF data to ImageBuffer
///
/// **IMPORTANT**: Always returns RGBA (4 channels) for consistency,
/// even if the source AVIF image is RGB/YUV. This simplifies downstream
/// processing and ensures consistent memory layout.
///
/// Safety: Allocates ImageBuffer, caller must call buffer.deinit()
/// Tiger Style: Validates magic bytes, explicit error handling
pub fn decodeAVIF(
    allocator: Allocator,
    data: []const u8,
) !ImageBuffer {
    // Pre-conditions (Tiger Style: 2+)
    const MAX_AVIF_SIZE: usize = 100 * 1024 * 1024; // 100MB
    std.debug.assert(data.len > 0);
    std.debug.assert(data.len <= MAX_AVIF_SIZE);

    // Validate AVIF magic bytes (ftyp box)
    if (data.len < 12 or data[4] != 'f' or data[5] != 't' or data[6] != 'y' or data[7] != 'p') {
        return AVIFError.InvalidImage;
    }

    // Create decoder
    const decoder = avifDecoderCreate() orelse return AVIFError.InitFailed;
    defer avifDecoderDestroy(decoder);

    // Create image to hold decoded data
    const avif_image = avifImageCreate(1, 1, 8, AVIF_PIXEL_FORMAT_YUV420) orelse return AVIFError.InitFailed;
    defer avifImageDestroy(avif_image);

    // Decode image directly from memory (high-level API)
    const decode_result = avifDecoderReadMemory(decoder, avif_image, data.ptr, data.len);
    if (decode_result != AVIF_RESULT_OK) {
        return AVIFError.DecodeFailed;
    }

    // Access image dimensions directly from struct
    const width = avif_image.width;
    const height = avif_image.height;

    // Validate dimensions
    if (width == 0 or height == 0 or width > 65536 or height > 65536) {
        return AVIFError.InvalidImage;
    }

    // Set up RGB output (always RGBA for consistency)
    var rgb_image: avifRGBImage = undefined;
    avifRGBImageSetDefaults(&rgb_image, avif_image);
    rgb_image.depth = 8;
    rgb_image.format = AVIF_RGB_FORMAT_RGBA;

    // Allocate RGB pixels
    const alloc_result = avifRGBImageAllocatePixels(&rgb_image);
    if (alloc_result != AVIF_RESULT_OK) {
        return AVIFError.OutOfMemory;
    }
    defer avifRGBImageFreePixels(&rgb_image);

    // Convert YUV to RGB
    const convert_result = avifImageYUVToRGB(avif_image, &rgb_image);
    if (convert_result != AVIF_RESULT_OK) {
        return AVIFError.DecodeFailed;
    }

    // Copy to our allocator
    const channels: u8 = 4; // RGBA
    const pixel_count: usize = @as(usize, width) * @as(usize, height) * @as(usize, channels);

    const pixel_data = try allocator.alloc(u8, pixel_count);
    errdefer allocator.free(pixel_data);

    @memcpy(pixel_data, rgb_image.pixels[0..pixel_count]);

    // Post-condition: Valid buffer created
    std.debug.assert(pixel_data.len == pixel_count);
    std.debug.assert(width > 0 and height > 0);

    return ImageBuffer{
        .data = pixel_data,
        .width = width,
        .height = height,
        .stride = width * channels,
        .channels = channels,
        .allocator = allocator,
        .color_space = 0, // sRGB default
    };
}

// ============================================================================
// Tests
// ============================================================================

test "AVIF encode/decode roundtrip RGBA" {
    const allocator = std.testing.allocator;

    // Create test image (8x8 RGBA gradient)
    const width: u32 = 8;
    const height: u32 = 8;
    const channels: u8 = 4;
    const pixel_count = width * height * channels;

    const pixel_data = try allocator.alloc(u8, pixel_count);
    defer allocator.free(pixel_data);

    // Fill with gradient pattern
    for (0..height) |y| {
        for (0..width) |x| {
            const idx = (y * width + x) * channels;
            pixel_data[idx + 0] = @intCast(x * 30); // R
            pixel_data[idx + 1] = @intCast(y * 30); // G
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

    // Encode to AVIF (high quality for better roundtrip)
    const encoded = try encodeAVIF(allocator, &original, 95);
    defer allocator.free(encoded);

    // Validate AVIF magic bytes (ftyp box)
    try std.testing.expect(encoded.len >= 12);
    try std.testing.expectEqual(@as(u8, 'f'), encoded[4]);
    try std.testing.expectEqual(@as(u8, 't'), encoded[5]);
    try std.testing.expectEqual(@as(u8, 'y'), encoded[6]);
    try std.testing.expectEqual(@as(u8, 'p'), encoded[7]);

    // Decode
    var decoded = try decodeAVIF(allocator, encoded);
    defer decoded.deinit();

    // Verify dimensions
    try std.testing.expectEqual(width, decoded.width);
    try std.testing.expectEqual(height, decoded.height);
    try std.testing.expectEqual(channels, decoded.channels);

    // Note: AVIF is lossy, so we can't expect exact pixel match
    // We just verify the image decoded successfully and has correct dimensions
}

test "AVIF encode/decode roundtrip RGB" {
    const allocator = std.testing.allocator;

    // Create test image (8x8 RGB gradient)
    const width: u32 = 8;
    const height: u32 = 8;
    const channels: u8 = 3;
    const pixel_count = width * height * channels;

    const pixel_data = try allocator.alloc(u8, pixel_count);
    defer allocator.free(pixel_data);

    // Fill with gradient pattern
    for (0..height) |y| {
        for (0..width) |x| {
            const idx = (y * width + x) * channels;
            pixel_data[idx + 0] = @intCast(x * 30); // R
            pixel_data[idx + 1] = @intCast(y * 30); // G
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

    // Encode to AVIF (high quality)
    const encoded = try encodeAVIF(allocator, &original, 95);
    defer allocator.free(encoded);

    // Validate AVIF magic bytes
    try std.testing.expect(encoded.len >= 12);
    try std.testing.expectEqual(@as(u8, 'f'), encoded[4]);

    // Decode (will be RGBA)
    var decoded = try decodeAVIF(allocator, encoded);
    defer decoded.deinit();

    // Verify dimensions
    try std.testing.expectEqual(width, decoded.width);
    try std.testing.expectEqual(height, decoded.height);
    try std.testing.expectEqual(@as(u8, 4), decoded.channels); // AVIF decode returns RGBA
}

test "AVIF quality levels" {
    const allocator = std.testing.allocator;

    // Create test image
    const width: u32 = 16;
    const height: u32 = 16;
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
            pixel_data[idx + 2] = @intCast((x * 20) % 256);
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
        const encoded = try encodeAVIF(allocator, &buffer, quality);
        defer allocator.free(encoded);

        // Verify it's a valid AVIF file
        try std.testing.expect(encoded.len >= 12);
        try std.testing.expectEqual(@as(u8, 'f'), encoded[4]);

        // Verify can decode
        var decoded = try decodeAVIF(allocator, encoded);
        defer decoded.deinit();

        try std.testing.expectEqual(width, decoded.width);
        try std.testing.expectEqual(height, decoded.height);

        prev_size = encoded.len;
    }
}

test "AVIF speed presets" {
    const allocator = std.testing.allocator;

    // Create small test image
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
            pixel_data[idx + 0] = @intCast((x * 25) % 256);
            pixel_data[idx + 1] = @intCast((y * 25) % 256);
            pixel_data[idx + 2] = 100;
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

    // Test different speed presets
    const speeds = [_]c_int{ AVIF_SPEED_FASTEST, AVIF_SPEED_DEFAULT, AVIF_SPEED_SLOWEST };

    for (speeds) |speed| {
        const encoded = try encodeAVIFWithSpeed(allocator, &buffer, 85, speed);
        defer allocator.free(encoded);

        // Verify valid AVIF
        try std.testing.expect(encoded.len >= 12);

        // Verify can decode
        var decoded = try decodeAVIF(allocator, encoded);
        defer decoded.deinit();

        try std.testing.expectEqual(width, decoded.width);
        try std.testing.expectEqual(height, decoded.height);
    }
}

test "AVIF invalid data handling" {
    const allocator = std.testing.allocator;

    // Test invalid magic bytes (JPEG header)
    const invalid_data = [_]u8{ 0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46, 0x00, 0x01 };
    const result = decodeAVIF(allocator, &invalid_data);
    try std.testing.expectError(AVIFError.InvalidImage, result);

    // Test truncated data (less than 12 bytes - fails length check)
    const truncated = [_]u8{ 0x00, 0x00, 0x00, 0x20, 'f', 't', 'y', 'p' };
    const result2 = decodeAVIF(allocator, &truncated);
    try std.testing.expectError(AVIFError.InvalidImage, result2);
}
