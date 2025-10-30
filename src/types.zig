//! Types module - re-exports all type definitions
//!
//! Tiger Style: Comptime validation ensures API stability

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const ImageBuffer = @import("types/image_buffer.zig").ImageBuffer;
pub const ImageMetadata = @import("types/image_metadata.zig").ImageMetadata;
pub const ImageFormat = @import("types/image_metadata.zig").ImageFormat;
pub const ExifOrientation = @import("types/image_metadata.zig").ExifOrientation;
pub const TransformParams = @import("types/transform_params.zig").TransformParams;
pub const ResizeMode = @import("types/transform_params.zig").ResizeMode;
pub const SharpenStrength = @import("types/transform_params.zig").SharpenStrength;
pub const IccMode = @import("types/transform_params.zig").IccMode;
pub const ExifMode = @import("types/transform_params.zig").ExifMode;
pub const TargetDimensions = @import("types/transform_params.zig").TargetDimensions;

// Metrics
pub const MetricType = @import("metrics.zig").MetricType;
pub const MetricError = @import("metrics.zig").MetricError;
pub const computePerceptualDiff = @import("metrics.zig").computePerceptualDiff;
pub const getRecommendedThreshold = @import("metrics.zig").getRecommendedThreshold;

// Tiger Style: Comptime validation of re-exported APIs
comptime {
    // Verify MetricType has expected variants
    const mt: MetricType = .butteraugli;
    _ = mt;
    const mt2: MetricType = .dssim;
    _ = mt2;
    const mt3: MetricType = .none;
    _ = mt3;

    // Verify function signatures match expected types
    const _computePerceptualDiff: fn (Allocator, *const ImageBuffer, *const ImageBuffer, MetricType) MetricError!f64 = computePerceptualDiff;
    _ = _computePerceptualDiff;

    const _getRecommendedThreshold: fn (MetricType) f64 = getRecommendedThreshold;
    _ = _getRecommendedThreshold;

    // Verify ImageFormat has expected variants
    const fmt: ImageFormat = .jpeg;
    _ = fmt;
    const fmt2: ImageFormat = .png;
    _ = fmt2;
    const fmt3: ImageFormat = .webp;
    _ = fmt3;
    const fmt4: ImageFormat = .avif;
    _ = fmt4;
}
