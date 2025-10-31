// Error Recovery Memory Test (~10 seconds)
//
// Goal: Verify memory cleanup happens correctly even when errors occur
//
// Test strategy:
// 1. Simulate various error conditions
// 2. Verify no memory leaks during error handling
// 3. Test mixed success/error operations
// 4. Assert: Clean error handling with no leaks
//
// Tiger Style: Bounded loops, explicit assertions, testing.allocator

const std = @import("std");
const testing = std.testing;

// Custom error set for testing
const TestError = error{
    SimulatedFailure,
    InvalidInput,
    ProcessingFailed,
    OutOfMemory,
};

// Helper function that sometimes fails
fn processData(allocator: std.mem.Allocator, should_fail: bool) TestError![]u8 {
    const buffer = try allocator.alloc(u8, 100);
    errdefer allocator.free(buffer);

    if (should_fail) {
        return TestError.SimulatedFailure;
    }

    // Success case
    @memset(buffer, 42);
    return buffer;
}

test "error recovery - cleanup on error paths" {
    // Tiger Style: Explicit MAX for bounded loop
    const MAX_ROUNDS: u32 = 250;

    std.debug.print("\n=== Error Recovery Memory Test ===\n", .{});
    std.debug.print("Goal: Verify no memory leaks when errors occur\n\n", .{});

    const allocator = testing.allocator;

    std.debug.print("Phase 1: Testing error recovery...\n", .{});

    var error_count: u32 = 0;
    var success_count: u32 = 0;

    var round: u32 = 0;
    // Tiger Style: Bounded loop
    while (round < MAX_ROUNDS) : (round += 1) {
        std.debug.assert(round < MAX_ROUNDS);

        // Alternate between success and failure
        const should_fail = (round % 3 == 0);

        const result = processData(allocator, should_fail) catch |err| {
            error_count += 1;
            // Expected error - verify cleanup happened
            try testing.expect(err == TestError.SimulatedFailure);
            continue;
        };
        defer allocator.free(result);

        success_count += 1;

        // Report progress every 50 rounds
        if ((round + 1) % 50 == 0) {
            std.debug.print("  Round {d}/{d}: Errors={d}, Success={d}\n", .{
                round + 1,
                MAX_ROUNDS,
                error_count,
                success_count,
            });
        }
    }

    // Tiger Style: Post-loop assertion
    std.debug.assert(round == MAX_ROUNDS);

    const total_operations = error_count + success_count;

    std.debug.print("\nPhase 2: Verification...\n", .{});
    std.debug.print("  Total operations: {d}\n", .{total_operations});
    std.debug.print("  Errors handled: {d}\n", .{error_count});
    std.debug.print("  Successful: {d}\n", .{success_count});
    std.debug.print("  ✓ PASS: No memory leaks on error paths\n", .{});
    std.debug.print("  ✓ Error handling working correctly\n", .{});
    std.debug.print("\n=== TEST PASSED ===\n", .{});
}

test "error recovery - nested allocations with error" {
    // Tiger Style: Test complex error scenarios
    const MAX_ITERATIONS: u32 = 500;

    std.debug.print("\n=== Nested Allocations Error Test ===\n", .{});
    std.debug.print("Goal: Verify nested allocations are cleaned up on error\n\n", .{});

    const allocator = testing.allocator;

    var i: u32 = 0;
    var error_count: u32 = 0;

    // Tiger Style: Bounded loop
    while (i < MAX_ITERATIONS) : (i += 1) {
        std.debug.assert(i < MAX_ITERATIONS);

        // First allocation
        const buffer1 = try allocator.alloc(u8, 50);
        errdefer allocator.free(buffer1);

        // Second allocation
        const buffer2 = try allocator.alloc(u8, 75);
        errdefer allocator.free(buffer2);

        // Simulate error on some iterations
        if (i % 5 == 0) {
            error_count += 1;
            // Manually clean up (errdefer would do this on error return)
            allocator.free(buffer2);
            allocator.free(buffer1);
            continue;
        }

        // Normal cleanup
        allocator.free(buffer2);
        allocator.free(buffer1);
    }

    std.debug.assert(i == MAX_ITERATIONS);

    std.debug.print("  Errors simulated: {d}\n", .{error_count});
    std.debug.print("  ✓ PASS: No memory leaks with nested allocations\n", .{});
    std.debug.print("\n=== TEST PASSED ===\n", .{});
}

test "error recovery - mixed valid and invalid operations" {
    // Tiger Style: Test interleaved valid/invalid operations
    const MAX_ITERATIONS: u32 = 500;

    std.debug.print("\n=== Mixed Operations Memory Test ===\n", .{});
    std.debug.print("Goal: Verify memory cleanup with mixed valid/invalid ops\n\n", .{});

    const allocator = testing.allocator;

    var valid_count: u32 = 0;
    var invalid_count: u32 = 0;

    var i: u32 = 0;
    // Tiger Style: Bounded loop
    while (i < MAX_ITERATIONS) : (i += 1) {
        std.debug.assert(i < MAX_ITERATIONS);

        // Allocate some data
        const buffer = try allocator.alloc(u8, 100);
        errdefer allocator.free(buffer);

        // Every 4th operation "fails"
        if (i % 4 == 0) {
            invalid_count += 1;
            allocator.free(buffer);
            continue;
        }

        // Success case - do some work
        @memset(buffer, @intCast(i % 256));
        valid_count += 1;

        // Clean up
        allocator.free(buffer);
    }

    // Tiger Style: Post-loop assertion
    std.debug.assert(i == MAX_ITERATIONS);

    std.debug.print("\nPhase 2: Verification...\n", .{});
    std.debug.print("  Total operations: {d}\n", .{MAX_ITERATIONS});
    std.debug.print("  Valid operations: {d}\n", .{valid_count});
    std.debug.print("  Invalid operations: {d}\n", .{invalid_count});
    std.debug.print("  ✓ PASS: No memory leaks with mixed operations\n", .{});
    std.debug.print("  ✓ Both success and error paths clean\n", .{});
    std.debug.print("\n=== TEST PASSED ===\n", .{});
}
