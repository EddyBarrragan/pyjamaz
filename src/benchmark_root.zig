//! Benchmark root - provides main() for benchmark runner

// Re-export modules for benchmarks
pub const optimizer = @import("optimizer.zig");
pub const vips = @import("vips.zig");
pub const types = @import("types.zig");
pub const codecs = @import("codecs.zig");

// Benchmark runner implementation
const std = @import("std");
const ImageFormat = types.ImageFormat;
const parallel_bench = @import("test/benchmark/parallel_encoding.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Initialize libvips
    var vips_ctx = try vips.VipsContext.init();
    defer vips_ctx.deinit();

    std.debug.print("\n=== Pyjamaz Parallel Encoding Benchmark ===\n\n", .{});

    // Benchmark 1: Small PNG (1.3KB)
    {
        std.debug.print("Benchmark 1: Small PNG (basn3p08.png, 1.3KB)\n", .{});
        const config = parallel_bench.BenchmarkConfig{
            .image_path = "testdata/conformance/pngsuite/basn3p08.png",
            .formats = &[_]ImageFormat{ .jpeg, .png },
            .max_bytes = null,
            .iterations = 10,
        };

        const result = try parallel_bench.benchmarkParallelEncoding(allocator, config);
        parallel_bench.printBenchmarkResults(result);
    }

    // Benchmark 2: Larger WebP (30KB)
    {
        std.debug.print("\nBenchmark 2: Larger WebP (1.webp, 30KB)\n", .{});
        const config = parallel_bench.BenchmarkConfig{
            .image_path = "testdata/conformance/webp/1.webp",
            .formats = &[_]ImageFormat{ .jpeg, .png, .webp },
            .max_bytes = null,
            .iterations = 5,
        };

        const result = try parallel_bench.benchmarkParallelEncoding(allocator, config);
        parallel_bench.printBenchmarkResults(result);
    }

    std.debug.print("\n=== Benchmark Complete ===\n\n", .{});
}
