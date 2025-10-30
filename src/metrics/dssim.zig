//! DSSIM (Structural Similarity) perceptual metric
//!
//! FFI bindings to dssim-core C library.
//! Computes perceptual difference between two images using multi-scale SSIM.
//!
//! Lower scores = more similar images
//! Typical thresholds:
//! - 0.0000 - 0.0005: Visually identical
//! - 0.0005 - 0.0020: Barely noticeable
//! - 0.0020 - 0.0100: Noticeable but acceptable
//! - 0.0100+: Clearly different
//!
//! References:
//! - https://github.com/kornelski/dssim
//! - https://en.wikipedia.org/wiki/Structural_similarity_index_measure

const std = @import("std");
const Allocator = std.mem.Allocator;
const ImageBuffer = @import("../types/image_buffer.zig").ImageBuffer;

// FFI declarations for dssim C API
const c = @cImport({
    @cInclude("dssim.h");
});

/// Compute DSSIM score between two images
///
/// Lower score = more similar images
/// Returns error if images have mismatched dimensions or invalid data
///
/// Tiger Style:
/// - Pre-condition: Images must have same width/height
/// - Pre-condition: Images must have RGB or RGBA data
/// - Bounded operation: O(width * height * channels)
pub fn compute(
    allocator: Allocator,
    baseline: *const ImageBuffer,
    candidate: *const ImageBuffer,
) !f64 {
    // Pre-conditions
    std.debug.assert(baseline.width > 0 and baseline.height > 0);
    std.debug.assert(candidate.width > 0 and candidate.height > 0);
    std.debug.assert(baseline.width == candidate.width);
    std.debug.assert(baseline.height == candidate.height);
    std.debug.assert(baseline.channels >= 3 and baseline.channels <= 4);
    std.debug.assert(candidate.channels >= 3 and candidate.channels <= 4);

    _ = allocator; // For future use

    // Create dssim context
    const ctx = c.dssim_new() orelse return error.DSSIMInitFailed;
    defer c.dssim_free(ctx);

    // Convert ImageBuffers to dssim format
    const baseline_img = try imageBufferToDSSIM(ctx, baseline);
    defer c.dssim_free_image(baseline_img);

    const candidate_img = try imageBufferToDSSIM(ctx, candidate);
    defer c.dssim_free_image(candidate_img);

    // Compute DSSIM
    const result = c.dssim_compare(ctx, baseline_img, candidate_img);

    // Post-condition: Valid DSSIM score (0.0 to ~1.0, can exceed 1.0 for very different images)
    std.debug.assert(result >= 0.0);
    std.debug.assert(!std.math.isNan(result));

    return result;
}

/// Convert ImageBuffer to DSSIM image format
///
/// Tiger Style:
/// - Pre-condition: buffer has valid dimensions and data
/// - Pre-condition: buffer has 3 or 4 channels
/// - Post-condition: Returns non-null DSSIM image pointer
fn imageBufferToDSSIM(ctx: *c.Dssim, buffer: *const ImageBuffer) !*c.DssimImage {
    std.debug.assert(buffer.width > 0 and buffer.height > 0);
    std.debug.assert(buffer.channels >= 3 and buffer.channels <= 4);
    std.debug.assert(buffer.data.len > 0);

    // DSSIM expects row-major RGBA or RGB pixels
    const img = if (buffer.channels == 4)
        c.dssim_create_image_rgba(
            ctx,
            buffer.data.ptr,
            buffer.width,
            buffer.height,
        )
    else
        c.dssim_create_image_rgb(
            ctx,
            buffer.data.ptr,
            buffer.width,
            buffer.height,
        );

    if (img == null) {
        return error.DSSIMImageCreationFailed;
    }

    // Post-condition: Valid DSSIM image
    std.debug.assert(img != null);

    return img.?;
}
