# Perceptual Metrics Design (v0.4.0)

**Status**: Planning Phase
**Last Updated**: 2025-10-30

---

## Overview

This document outlines the design for integrating real perceptual image quality metrics into Pyjamaz, replacing the stub implementations in v0.3.0.

## Goals

1. Add real perceptual quality measurement (not stubs)
2. Support pluggable metrics (DSSIM initially, Butteraugli future)
3. Maintain Tiger Style compliance (bounded operations, explicit safety)
4. Enable dual-constraint validation (size + diff)

## Non-Goals

- Video quality metrics (future work)
- Custom metric development (use existing libraries)
- GPU acceleration (CPU-only for MVP)

---

## Architecture

### Current State (v0.3.0)

```zig
// src/metrics.zig - STUB IMPLEMENTATION
pub fn computeButteraugli(baseline: *const ImageBuffer, candidate: *const ImageBuffer) !f64 {
    _ = baseline;
    _ = candidate;
    return 0.0; // Stub: Always returns perfect score
}

pub fn computeDSSIM(baseline: *const ImageBuffer, candidate: *const ImageBuffer) !f64 {
    _ = baseline;
    _ = candidate;
    return 0.0; // Stub: Always returns perfect score
}
```

### Target State (v0.4.0)

```zig
// src/metrics.zig - REAL IMPLEMENTATION
pub const MetricType = enum {
    butteraugli,  // Future
    dssim,        // Phase 1
};

pub fn computeMetric(
    allocator: Allocator,
    metric_type: MetricType,
    baseline: *const ImageBuffer,
    candidate: *const ImageBuffer,
) !f64 {
    return switch (metric_type) {
        .dssim => try dssim.compute(allocator, baseline, candidate),
        .butteraugli => error.NotImplemented, // v0.5.0+
    };
}
```

---

## Phase 1: DSSIM Integration

### Decision Rationale

**Why DSSIM?**
- ✅ Provides C FFI via `dssim-core` library
- ✅ Zig has excellent C interop (simpler than C++)
- ✅ Actively maintained (v3.3.4, Jan 2025)
- ✅ Can install via cargo or pkg-config
- ✅ Well-documented SSIM algorithm
- ✅ Supports RGBA (important for PNG/WebP)

**Why not Butteraugli first?**
- ❌ C++ library (more complex FFI in Zig)
- ❌ No existing C wrapper
- ❌ Would require building custom C shim layer

**Future**: Add Butteraugli in v0.5.0 after DSSIM proves the architecture.

### Implementation Plan

#### Step 1: Install dssim-core

```bash
# Option A: Via cargo (requires Rust toolchain)
cargo install dssim

# Option B: Build from source
git clone https://github.com/kornelski/dssim.git
cd dssim
cargo build --release --features=c-ffi

# Option C: Via Homebrew (macOS)
brew install dssim

# Verify installation
pkg-config --libs --cflags dssim
```

#### Step 2: Create FFI Bindings

**File**: `src/metrics/dssim.zig`

```zig
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
    const ctx = c.dssim_create() orelse return error.DSSIMInitFailed;
    defer c.dssim_destroy(ctx);

    // Convert ImageBuffers to dssim format
    const baseline_img = try imageBufferToDSSIM(ctx, baseline);
    defer c.dssim_dealloc_image(baseline_img);

    const candidate_img = try imageBufferToDSSIM(ctx, candidate);
    defer c.dssim_dealloc_image(candidate_img);

    // Compute DSSIM
    const result = c.dssim_compare(ctx, baseline_img, candidate_img);

    // Post-condition: Valid DSSIM score (0.0 to ~1.0, can exceed 1.0 for very different images)
    std.debug.assert(result >= 0.0);
    std.debug.assert(!std.math.isNan(result));

    return result;
}

fn imageBufferToDSSIM(ctx: *c.dssim_context, buffer: *const ImageBuffer) !*c.dssim_image {
    // Implementation depends on dssim C API
    // Pseudo-code:
    // 1. Create dssim_image with width, height, channels
    // 2. Copy buffer.data into dssim internal format
    // 3. Return dssim_image pointer
    _ = ctx;
    _ = buffer;
    return error.NotImplemented; // TODO: Implement based on actual dssim.h API
}
```

#### Step 3: Update build.zig

```zig
// Add dssim-core to build
const exe = b.addExecutable(.{
    .name = "pyjamaz",
    .root_source_file = b.path("src/main.zig"),
    .target = target,
    .optimize = optimize,
});

// Link dssim-core
exe.linkSystemLibrary("dssim");
exe.addIncludePath(.{ .cwd_relative = "/usr/local/include" }); // Adjust path
exe.addLibraryPath(.{ .cwd_relative = "/usr/local/lib" });     // Adjust path

// Or use pkg-config
try exe.runPkgConfig("dssim");
```

#### Step 4: Update src/metrics.zig

Replace stub with real implementation:

```zig
pub fn computeButteraugli(baseline: *const ImageBuffer, candidate: *const ImageBuffer) !f64 {
    // TODO: v0.5.0 - Still stubbed
    _ = baseline;
    _ = candidate;
    return 0.0;
}

pub fn computeDSSIM(baseline: *const ImageBuffer, candidate: *const ImageBuffer) !f64 {
    // Real implementation via FFI
    return try dssim.compute(std.heap.page_allocator, baseline, candidate);
}
```

#### Step 5: Unit Tests

**File**: `src/test/unit/metrics_dssim_test.zig`

```zig
test "DSSIM: identical images return ~0.0" {
    const allocator = testing.allocator;

    // Create identical images
    const img1 = try createTestImage(allocator, 100, 100, .{ 128, 128, 128 });
    defer img1.deinit();

    const img2 = try createTestImage(allocator, 100, 100, .{ 128, 128, 128 });
    defer img2.deinit();

    const score = try dssim.compute(allocator, &img1, &img2);

    // Identical images should have DSSIM ≈ 0.0
    try testing.expect(score < 0.0001);
}

test "DSSIM: very different images return high score" {
    const allocator = testing.allocator;

    // Black image
    const img1 = try createTestImage(allocator, 100, 100, .{ 0, 0, 0 });
    defer img1.deinit();

    // White image
    const img2 = try createTestImage(allocator, 100, 100, .{ 255, 255, 255 });
    defer img2.deinit();

    const score = try dssim.compute(allocator, &img1, &img2);

    // Very different images should have DSSIM > 0.1
    try testing.expect(score > 0.1);
}

test "DSSIM: dimension mismatch returns error" {
    const allocator = testing.allocator;

    const img1 = try createTestImage(allocator, 100, 100, .{ 128, 128, 128 });
    defer img1.deinit();

    const img2 = try createTestImage(allocator, 200, 200, .{ 128, 128, 128 });
    defer img2.deinit();

    const result = dssim.compute(allocator, &img1, &img2);
    try testing.expectError(error.DimensionMismatch, result);
}
```

---

## Phase 2: Dual-Constraint Validation

Once DSSIM is integrated, update optimizer to actually use the metric:

### Update optimizer.zig

```zig
// Step 3: Score candidates with real metrics
for (candidates.items) |*candidate| {
    // Decode candidate to compare against original
    const decoded = try decodeCandidate(allocator, candidate);
    defer decoded.deinit();

    // Compute real perceptual difference
    const diff_score = switch (job.metric_type) {
        .dssim => try metrics.computeDSSIM(&buffer, &decoded),
        .butteraugli => return error.NotImplemented,
    };

    candidate.diff_score = diff_score;

    // Update passed_constraints based on real diff
    if (job.max_diff) |max| {
        if (diff_score > max) {
            candidate.passed_constraints = false;
        }
    }
}
```

### Update selectBestCandidate

```zig
fn selectBestCandidate(...) !?EncodedCandidate {
    // ...existing size filtering...

    // Filter: Check diff constraint (NOW REAL!)
    if (max_diff) |limit| {
        if (candidate.diff_score > limit) {
            std.log.debug("    Rejected: diff {d} > limit {d}", .{
                candidate.diff_score,
                limit,
            });
            continue;
        }
    }

    // ...rest of selection logic...
}
```

---

## Testing Strategy

### Unit Tests
- ✅ DSSIM FFI bindings work correctly
- ✅ Identical images → score ≈ 0.0
- ✅ Very different images → score > threshold
- ✅ Dimension mismatches → error
- ✅ Memory safety (no leaks with testing.allocator)

### Integration Tests
- ✅ Optimizer uses real metrics
- ✅ Candidates correctly scored
- ✅ Dual-constraint filtering works
- ✅ --max-diff flag respected

### Conformance Tests
- ✅ PNGSuite with diff constraints
- ✅ Verify perceptual quality preserved
- ✅ Document typical DSSIM scores for each suite

---

## Performance Considerations

### DSSIM Performance

From dssim-core documentation:
- **Single-threaded**: ~5-10ms for 1024x768 image (typical)
- **Memory usage**: ~3x image size (working buffers)
- **Scaling**: O(width * height * channels)

### Optimization Strategies

1. **Skip metric for identical formats**
   - Original PNG → PNG at quality=100 → skip (diff=0.0)

2. **Parallel candidate scoring**
   - Score multiple candidates concurrently
   - Per-thread DSSIM context (not thread-safe)

3. **Subsample for large images**
   - Option: `--metric-subsample 2` (score every 2nd pixel)
   - Tradeoff: 4x faster, slightly less accurate

4. **Early termination**
   - If candidate fails size constraint, skip metric computation

---

## Thresholds & Guidance

### Recommended DSSIM Thresholds

Based on empirical testing and literature:

| Use Case | max_diff (DSSIM) | Description |
|----------|------------------|-------------|
| Archival | 0.0005 | Near-lossless, visually identical |
| Web (high quality) | 0.0020 | Barely noticeable differences |
| Web (standard) | 0.0050 | Acceptable quality |
| Thumbnails | 0.0100 | Noticeable but acceptable |
| Aggressive | 0.0200+ | Clearly different, use with caution |

### CLI Examples

```bash
# Archival quality (near-lossless)
pyjamaz input.png --max-diff 0.0005

# Web standard (good balance)
pyjamaz input.png --max-kb 200 --max-diff 0.005

# Aggressive compression (size priority)
pyjamaz input.png --max-kb 100 --max-diff 0.02
```

---

## Future Work (v0.5.0+)

### Butteraugli Integration

- Create C wrapper for Butteraugli C++ library
- Implement `src/metrics/butteraugli.zig`
- Add `--metric butteraugli` flag
- Document Butteraugli thresholds (different scale than DSSIM)

### Additional Metrics

- VMAF (video quality, but works for images)
- MS-SSIM (multi-scale SSIM variant)
- PSNR (peak signal-to-noise ratio, simpler)

### Performance Optimizations

- GPU acceleration (Metal/CUDA)
- SIMD optimizations for metric computation
- Caching of metric scores (keyed by content hash)

---

## References

- [DSSIM GitHub](https://github.com/kornelski/dssim)
- [DSSIM C FFI docs](https://docs.rs/dssim-core/latest/dssim_core/)
- [SSIM Wikipedia](https://en.wikipedia.org/wiki/Structural_similarity_index_measure)
- [Butteraugli GitHub](https://github.com/google/butteraugli)
- [Image Quality Assessment Survey](https://ieeexplore.ieee.org/document/5432019)

---

**Status**: Ready for implementation
**Next Step**: Install dssim-core and create FFI bindings
