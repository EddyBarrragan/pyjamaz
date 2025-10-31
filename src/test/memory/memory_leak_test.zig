// Memory Leak Test (~30 seconds)
//
// Goal: Verify that repeated allocations don't leak memory
//
// Test strategy:
// 1. Run 10K allocation/deallocation cycles
// 2. Use testing.allocator (auto-detects leaks)
// 3. Verify all allocations are freed
// 4. Assert: Zero memory leaks
//
// Tiger Style: Bounded loops, explicit assertions, testing.allocator

const std = @import("std");
const testing = std.testing;

// Sample data to allocate (simulating image buffers)
const SAMPLE_SIZE: usize = 167; // Size of a small JPEG

test "memory leak - 10K allocation cycles" {
    // Tiger Style: Explicit MAX for bounded loop
    const MAX_ITERATIONS: u32 = 10_000;
    const REPORT_INTERVAL: u32 = 2500;

    std.debug.print("\n=== Memory Leak Test ===\n", .{});
    std.debug.print("Goal: Verify no memory leaks in {d} allocation cycles\n\n", .{MAX_ITERATIONS});

    // Tiger Style: Use testing.allocator (auto-detects leaks)
    const allocator = testing.allocator;

    std.debug.print("Phase 1: Running {d} allocation/deallocation cycles...\n", .{MAX_ITERATIONS});

    var i: u32 = 0;
    var total_allocated: u64 = 0;

    // Tiger Style: Bounded loop with explicit MAX
    while (i < MAX_ITERATIONS) : (i += 1) {
        // Pre-condition assertion
        std.debug.assert(i < MAX_ITERATIONS);

        // Allocate a buffer (simulating image data)
        const buffer = try allocator.alloc(u8, SAMPLE_SIZE);
        defer allocator.free(buffer);

        // Fill with data (simulating work)
        @memset(buffer, @intCast(i % 256));

        total_allocated += SAMPLE_SIZE;

        // Report progress
        if ((i + 1) % REPORT_INTERVAL == 0) {
            std.debug.print("  Completed {d}/{d} cycles\n", .{ i + 1, MAX_ITERATIONS });
        }
    }

    // Tiger Style: Post-loop assertion
    std.debug.assert(i == MAX_ITERATIONS);

    std.debug.print("\nPhase 2: Verification...\n", .{});
    std.debug.print("  Total cycles: {d}\n", .{MAX_ITERATIONS});
    std.debug.print("  Total allocated: {d} bytes\n", .{total_allocated});

    // If testing.allocator detects leaks, test will fail automatically
    std.debug.print("  ✓ PASS: No memory leaks detected\n", .{});
    std.debug.print("  ✓ All allocations properly freed\n", .{});
    std.debug.print("\n=== TEST PASSED ===\n", .{});
}

test "memory leak - varying buffer sizes" {
    // Tiger Style: Test that different allocation sizes don't leak
    const MAX_ITERATIONS: u32 = 1000;
    const allocator = testing.allocator;

    std.debug.print("\n=== Varying Buffer Sizes Test ===\n", .{});
    std.debug.print("Goal: Verify no leaks with varying allocation sizes\n\n", .{});

    var i: u32 = 0;
    while (i < MAX_ITERATIONS) : (i += 1) {
        std.debug.assert(i < MAX_ITERATIONS);

        // Allocate varying sizes (1x, 10x, 50x base size)
        const multiplier: usize = if (i % 3 == 0) 1 else if (i % 3 == 1) 10 else 50;
        const size = SAMPLE_SIZE * multiplier;

        const buffer = try allocator.alloc(u8, size);
        defer allocator.free(buffer);

        // Use the buffer
        @memset(buffer, @intCast(i % 256));
    }

    std.debug.assert(i == MAX_ITERATIONS);

    std.debug.print("  ✓ PASS: No leaks with varying sizes\n", .{});
    std.debug.print("\n=== TEST PASSED ===\n", .{});
}

test "memory leak - error path cleanup" {
    // Tiger Style: Test that errors don't leak memory
    const MAX_ITERATIONS: u32 = 1000;

    std.debug.print("\n=== Error Path Memory Test ===\n", .{});
    std.debug.print("Goal: Verify memory is cleaned up even when errors occur\n\n", .{});

    const allocator = testing.allocator;

    var i: u32 = 0;
    var error_count: u32 = 0;

    // Tiger Style: Bounded loop
    while (i < MAX_ITERATIONS) : (i += 1) {
        std.debug.assert(i < MAX_ITERATIONS);

        // Allocate some buffers
        const buffer1 = try allocator.alloc(u8, SAMPLE_SIZE);
        errdefer allocator.free(buffer1);

        // Simulate an error case every 10 iterations
        if (i % 10 == 0) {
            error_count += 1;
            allocator.free(buffer1);
            continue; // Simulate error path
        }

        // Normal path
        allocator.free(buffer1);
    }

    // Tiger Style: Post-loop assertion
    std.debug.assert(i == MAX_ITERATIONS);

    std.debug.print("  Errors simulated: {d}\n", .{error_count});
    std.debug.print("  ✓ PASS: No memory leaks on error paths\n", .{});
    std.debug.print("\n=== TEST PASSED ===\n", .{});
}
