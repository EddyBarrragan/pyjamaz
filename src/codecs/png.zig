const std = @import("std");
const Allocator = std.mem.Allocator;
const ImageBuffer = @import("../types/image_buffer.zig").ImageBuffer;

/// PNG codec using libpng
///
/// This module provides PNG encoding and decoding using the libpng API.
///
/// Tiger Style: All operations bounded, explicit error handling, memory safety.

// ============================================================================
// C FFI Declarations (libpng)
// ============================================================================

const png_structp = opaque {};
const png_infop = opaque {};
const png_bytep = [*c]u8;
const png_bytepp = [*c][*c]u8;

// libpng constants
const PNG_COLOR_TYPE_GRAY: c_int = 0;
const PNG_COLOR_TYPE_RGB: c_int = 2;
const PNG_COLOR_TYPE_PALETTE: c_int = 3;
const PNG_COLOR_TYPE_GRAY_ALPHA: c_int = 4;
const PNG_COLOR_TYPE_RGB_ALPHA: c_int = 6;

const PNG_INTERLACE_NONE: c_int = 0;
const PNG_COMPRESSION_TYPE_DEFAULT: c_int = 0;
const PNG_FILTER_TYPE_DEFAULT: c_int = 0;

const PNG_TRANSFORM_IDENTITY: c_int = 0x0000;
const PNG_TRANSFORM_STRIP_16: c_int = 0x0001;
const PNG_TRANSFORM_PACKING: c_int = 0x0004;
const PNG_TRANSFORM_EXPAND: c_int = 0x0010;

// External C functions from libpng
extern "c" fn png_create_write_struct(user_png_ver: [*c]const u8, error_ptr: ?*anyopaque, error_fn: ?*const anyopaque, warn_fn: ?*const anyopaque) ?*png_structp;
extern "c" fn png_create_info_struct(png_ptr: ?*png_structp) ?*png_infop;
extern "c" fn png_destroy_write_struct(png_ptr_ptr: *?*png_structp, info_ptr_ptr: *?*png_infop) void;
extern "c" fn png_set_write_fn(png_ptr: ?*png_structp, io_ptr: ?*anyopaque, write_data_fn: ?*const anyopaque, output_flush_fn: ?*const anyopaque) void;
extern "c" fn png_set_IHDR(png_ptr: ?*png_structp, info_ptr: ?*png_infop, width: u32, height: u32, bit_depth: c_int, color_type: c_int, interlace_method: c_int, compression_method: c_int, filter_method: c_int) void;
extern "c" fn png_set_compression_level(png_ptr: ?*png_structp, level: c_int) void;
extern "c" fn png_write_info(png_ptr: ?*png_structp, info_ptr: ?*png_infop) void;
extern "c" fn png_write_row(png_ptr: ?*png_structp, row: png_bytep) void;
extern "c" fn png_write_end(png_ptr: ?*png_structp, info_ptr: ?*png_infop) void;

extern "c" fn png_create_read_struct(user_png_ver: [*c]const u8, error_ptr: ?*anyopaque, error_fn: ?*const anyopaque, warn_fn: ?*const anyopaque) ?*png_structp;
extern "c" fn png_destroy_read_struct(png_ptr_ptr: *?*png_structp, info_ptr_ptr: *?*png_infop, end_info_ptr_ptr: *?*png_infop) void;
extern "c" fn png_set_read_fn(png_ptr: ?*png_structp, io_ptr: ?*anyopaque, read_data_fn: ?*const anyopaque) void;
extern "c" fn png_get_io_ptr(png_ptr: ?*const png_structp) ?*anyopaque;
extern "c" fn png_read_info(png_ptr: ?*png_structp, info_ptr: ?*png_infop) void;
extern "c" fn png_get_IHDR(png_ptr: ?*const png_structp, info_ptr: ?*const png_infop, width: *u32, height: *u32, bit_depth: *c_int, color_type: *c_int, interlace_method: *c_int, compression_method: *c_int, filter_method: *c_int) u32;
extern "c" fn png_read_update_info(png_ptr: ?*png_structp, info_ptr: ?*png_infop) void;
extern "c" fn png_read_image(png_ptr: ?*png_structp, image: png_bytepp) void;
extern "c" fn png_read_end(png_ptr: ?*png_structp, info_ptr: ?*png_infop) void;
extern "c" fn png_set_expand(png_ptr: ?*png_structp) void;
extern "c" fn png_set_strip_16(png_ptr: ?*png_structp) void;
extern "c" fn png_set_gray_to_rgb(png_ptr: ?*png_structp) void;
extern "c" fn png_set_palette_to_rgb(png_ptr: ?*png_structp) void;
extern "c" fn png_get_rowbytes(png_ptr: ?*const png_structp, info_ptr: ?*const png_infop) usize;
extern "c" fn png_sig_cmp(sig: [*c]const u8, start: usize, num_to_check: usize) c_int;

const PNG_LIBPNG_VER_STRING = "1.6.43";

// ============================================================================
// Error Handling
// ============================================================================

pub const PngError = error{
    InitFailed,
    EncodeFailed,
    DecodeFailed,
    OutOfMemory,
    InvalidCompression,
    InvalidImage,
};

// ============================================================================
// Memory Buffer for Write Callback
// ============================================================================

const WriteContext = struct {
    buffer: std.ArrayList(u8),
    allocator: Allocator,
    had_error: bool = false, // Track errors in callback for later propagation
};

// PNG write callback
fn pngWriteCallback(png_ptr: ?*png_structp, data: png_bytep, length: usize) callconv(.c) void {
    const io_ptr = png_get_io_ptr(png_ptr) orelse return;
    const ctx = @as(*WriteContext, @ptrCast(@alignCast(io_ptr)));

    // Append data to buffer
    // Tiger Style: Track errors in C callbacks, check after C operation completes
    ctx.buffer.appendSlice(ctx.allocator, data[0..length]) catch {
        ctx.had_error = true; // Mark error for propagation
        return;
    };
}

fn pngFlushCallback(_: ?*png_structp) callconv(.c) void {
    // No-op for memory buffer
}

// ============================================================================
// Memory Buffer for Read Callback
// ============================================================================

const ReadContext = struct {
    data: []const u8,
    offset: usize,
};

fn pngReadCallback(png_ptr: ?*png_structp, out_bytes: png_bytep, byte_count: usize) callconv(.c) void {
    const io_ptr = png_get_io_ptr(png_ptr) orelse return;
    const ctx = @as(*ReadContext, @ptrCast(@alignCast(io_ptr)));

    // Copy data from buffer
    const remaining = ctx.data.len - ctx.offset;
    const to_read = @min(byte_count, remaining);

    if (to_read > 0) {
        @memcpy(out_bytes[0..to_read], ctx.data[ctx.offset..][0..to_read]);
        ctx.offset += to_read;
    }
}

// ============================================================================
// PNG Encoding
// ============================================================================

/// Encode ImageBuffer to PNG with given compression level
///
/// Compression: 0-9 (0 = no compression, 9 = best compression)
///
/// Safety: Returns owned slice, caller must free with allocator
/// Tiger Style: Compression bounded 0-9, explicit error handling
pub fn encodePNG(
    allocator: Allocator,
    buffer: *const ImageBuffer,
    compression: u8,
) ![]u8 {
    // Assertions (Tiger Style: 2+)
    std.debug.assert(buffer.width > 0 and buffer.width <= 65535);
    std.debug.assert(buffer.height > 0 and buffer.height <= 65535);
    std.debug.assert(buffer.channels == 3 or buffer.channels == 4);
    std.debug.assert(compression <= 9);

    // Create PNG write struct
    const png_ptr = png_create_write_struct(
        PNG_LIBPNG_VER_STRING.ptr,
        null,
        null,
        null,
    ) orelse return PngError.InitFailed;

    var png_ptr_opt: ?*png_structp = png_ptr;

    // Create PNG info struct
    const info_ptr = png_create_info_struct(png_ptr) orelse return PngError.InitFailed;
    var info_ptr_opt: ?*png_infop = info_ptr;
    defer png_destroy_write_struct(&png_ptr_opt, &info_ptr_opt);

    // Set up write callback to memory buffer
    var write_ctx = WriteContext{
        .buffer = std.ArrayList(u8){},
        .allocator = allocator,
    };
    defer write_ctx.buffer.deinit(allocator);

    png_set_write_fn(
        png_ptr,
        @ptrCast(&write_ctx),
        @ptrCast(&pngWriteCallback),
        @ptrCast(&pngFlushCallback),
    );

    // Set image parameters
    const color_type: c_int = if (buffer.channels == 4) PNG_COLOR_TYPE_RGB_ALPHA else PNG_COLOR_TYPE_RGB;

    png_set_IHDR(
        png_ptr,
        info_ptr,
        buffer.width,
        buffer.height,
        8, // bit depth
        color_type,
        PNG_INTERLACE_NONE,
        PNG_COMPRESSION_TYPE_DEFAULT,
        PNG_FILTER_TYPE_DEFAULT,
    );

    // Set compression level
    png_set_compression_level(png_ptr, @intCast(compression));

    // Write PNG header
    png_write_info(png_ptr, info_ptr);

    // Write scanlines
    var row: u32 = 0;

    while (row < buffer.height) : (row += 1) {
        const row_data = buffer.getRow(row);
        png_write_row(png_ptr, @constCast(row_data.ptr));
    }

    std.debug.assert(row == buffer.height); // Post-loop assertion

    // Finish writing
    png_write_end(png_ptr, info_ptr);

    // Check for errors that occurred in C callback
    // Tiger Style: Propagate errors from C callbacks after operation completes
    if (write_ctx.had_error) {
        return PngError.EncodeFailed; // OOM or other allocation failure in callback
    }

    // Get the encoded data
    if (write_ctx.buffer.items.len == 0) {
        return PngError.EncodeFailed;
    }

    // Return owned copy
    const result = try allocator.dupe(u8, write_ctx.buffer.items);

    // Post-conditions
    std.debug.assert(result.len > 0);
    std.debug.assert(result.len >= 8);
    std.debug.assert(result[0] == 0x89); // PNG signature
    std.debug.assert(result[1] == 0x50 and result[2] == 0x4E and result[3] == 0x47);

    return result;
}

// ============================================================================
// PNG Decoding
// ============================================================================

/// Decode PNG bytes to ImageBuffer
///
/// Input: PNG-encoded bytes
/// Output: ImageBuffer with RGB or RGBA data
///
/// Safety: Returns owned ImageBuffer, caller must call .deinit()
/// Tiger Style: Bounded dimensions, explicit error handling
pub fn decodePNG(
    allocator: Allocator,
    png_data: []const u8,
) !ImageBuffer {
    // Pre-conditions (Tiger Style)
    std.debug.assert(png_data.len > 0);
    std.debug.assert(png_data.len < 100 * 1024 * 1024); // Max 100MB

    // Verify PNG signature (first 8 bytes)
    if (png_data.len < 8) {
        return PngError.DecodeFailed;
    }

    const sig_check = png_sig_cmp(png_data.ptr, 0, 8);
    if (sig_check != 0) {
        return PngError.DecodeFailed;
    }

    // Create PNG read struct
    const png_ptr = png_create_read_struct(
        PNG_LIBPNG_VER_STRING.ptr,
        null,
        null,
        null,
    ) orelse return PngError.InitFailed;

    var png_ptr_opt: ?*png_structp = png_ptr;
    defer {
        var dummy1: ?*png_infop = null;
        var dummy2: ?*png_infop = null;
        _ = &dummy1;
        _ = &dummy2;
        png_destroy_read_struct(&png_ptr_opt, &dummy1, &dummy2);
    }

    // Create PNG info struct
    const info_ptr = png_create_info_struct(png_ptr) orelse return PngError.InitFailed;

    // Set up read callback from memory buffer
    var read_ctx = ReadContext{
        .data = png_data,
        .offset = 0,
    };

    png_set_read_fn(png_ptr, @ptrCast(&read_ctx), @ptrCast(&pngReadCallback));

    // Read PNG header
    png_read_info(png_ptr, info_ptr);

    // Get image info
    var width: u32 = 0;
    var height: u32 = 0;
    var bit_depth: c_int = 0;
    var color_type: c_int = 0;
    var interlace_method: c_int = 0;
    var compression_method: c_int = 0;
    var filter_method: c_int = 0;

    _ = png_get_IHDR(
        png_ptr,
        info_ptr,
        &width,
        &height,
        &bit_depth,
        &color_type,
        &interlace_method,
        &compression_method,
        &filter_method,
    );

    // Validate dimensions (Tiger Style: bounded)
    if (width == 0 or height == 0) {
        return PngError.InvalidImage;
    }
    if (width > 65535 or height > 65535) {
        return PngError.InvalidImage;
    }

    // Convert to RGB/RGBA format
    if (color_type == PNG_COLOR_TYPE_PALETTE) {
        png_set_palette_to_rgb(png_ptr);
    }
    if (color_type == PNG_COLOR_TYPE_GRAY and bit_depth < 8) {
        png_set_expand(png_ptr);
    }
    if (bit_depth == 16) {
        png_set_strip_16(png_ptr);
    }
    if (color_type == PNG_COLOR_TYPE_GRAY or color_type == PNG_COLOR_TYPE_GRAY_ALPHA) {
        png_set_gray_to_rgb(png_ptr);
    }

    // Update info after transformations
    png_read_update_info(png_ptr, info_ptr);

    // Get row bytes
    const row_bytes = png_get_rowbytes(png_ptr, info_ptr);
    const channels: u8 = @intCast(row_bytes / width);

    std.debug.assert(channels == 3 or channels == 4);
    std.debug.assert(width > 0 and width <= 65535);
    std.debug.assert(height > 0 and height <= 65535);

    // Allocate image buffer
    var img_buffer = try ImageBuffer.init(allocator, width, height, channels);
    errdefer img_buffer.deinit();

    // Allocate row pointers
    const row_pointers = try allocator.alloc([*c]u8, height);
    defer allocator.free(row_pointers);

    // Set row pointers to ImageBuffer rows
    var row: u32 = 0;
    while (row < height) : (row += 1) {
        const row_data = img_buffer.getRow(row);
        row_pointers[row] = @constCast(row_data.ptr);
    }

    std.debug.assert(row == height); // Post-loop assertion

    // Read image data
    png_read_image(png_ptr, @ptrCast(row_pointers.ptr));

    // Finish reading
    png_read_end(png_ptr, info_ptr);

    // Post-conditions
    std.debug.assert(img_buffer.width == width);
    std.debug.assert(img_buffer.height == height);
    std.debug.assert(img_buffer.channels == channels);

    return img_buffer;
}

// ============================================================================
// Unit Tests
// ============================================================================

test "PNG encoding with valid compression" {
    const testing = std.testing;

    // Create small test image (10x10 RGB)
    var buffer_img = try ImageBuffer.init(testing.allocator, 10, 10, 3);
    defer buffer_img.deinit();

    // Fill with blue color
    var i: usize = 0;
    while (i < buffer_img.data.len) : (i += 3) {
        buffer_img.data[i + 0] = 0; // R
        buffer_img.data[i + 1] = 0; // G
        buffer_img.data[i + 2] = 255; // B
    }

    // Encode at various compression levels
    const compressions = [_]u8{ 0, 3, 6, 9 };
    for (compressions) |comp| {
        const png_data = try encodePNG(testing.allocator, &buffer_img, comp);
        defer testing.allocator.free(png_data);

        // Verify PNG signature
        try testing.expect(png_data.len > 8);
        try testing.expectEqual(@as(u8, 0x89), png_data[0]);
        try testing.expectEqual(@as(u8, 0x50), png_data[1]);
        try testing.expectEqual(@as(u8, 0x4E), png_data[2]);
        try testing.expectEqual(@as(u8, 0x47), png_data[3]);
    }
}

test "PNG encoding handles RGBA with alpha" {
    const testing = std.testing;

    // Create small RGBA image
    var buffer_img = try ImageBuffer.init(testing.allocator, 10, 10, 4);
    defer buffer_img.deinit();

    // Fill with semi-transparent green
    var i: usize = 0;
    while (i < buffer_img.data.len) : (i += 4) {
        buffer_img.data[i + 0] = 0; // R
        buffer_img.data[i + 1] = 255; // G
        buffer_img.data[i + 2] = 0; // B
        buffer_img.data[i + 3] = 128; // A (semi-transparent)
    }

    const png_data = try encodePNG(testing.allocator, &buffer_img, 6);
    defer testing.allocator.free(png_data);

    try testing.expect(png_data.len > 0);
}

test "PNG decode and encode roundtrip" {
    const testing = std.testing;

    // Create test image (16x16 RGB)
    var buffer_img = try ImageBuffer.init(testing.allocator, 16, 16, 3);
    defer buffer_img.deinit();

    // Fill with gradient pattern
    var y: u32 = 0;
    while (y < 16) : (y += 1) {
        var x: u32 = 0;
        while (x < 16) : (x += 1) {
            const offset = (y * 16 + x) * 3;
            buffer_img.data[offset + 0] = @truncate(x * 16); // R gradient
            buffer_img.data[offset + 1] = @truncate(y * 16); // G gradient
            buffer_img.data[offset + 2] = 128; // B constant
        }
    }

    // Encode
    const png_data = try encodePNG(testing.allocator, &buffer_img, 6);
    defer testing.allocator.free(png_data);

    // Decode
    var decoded = try decodePNG(testing.allocator, png_data);
    defer decoded.deinit();

    // Verify dimensions
    try testing.expectEqual(@as(u32, 16), decoded.width);
    try testing.expectEqual(@as(u32, 16), decoded.height);
    try testing.expectEqual(@as(u8, 3), decoded.channels);

    // PNG is lossless, so data should match exactly
    try testing.expectEqualSlices(u8, buffer_img.data, decoded.data);
}

test "PNG decode detects invalid data" {
    const testing = std.testing;

    // Try to decode invalid PNG data
    const invalid_data = [_]u8{ 0x00, 0x00, 0x00, 0x00 };
    const result = decodePNG(testing.allocator, &invalid_data);

    try testing.expectError(PngError.DecodeFailed, result);
}
