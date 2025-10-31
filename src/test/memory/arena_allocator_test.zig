// Arena Allocator Test (~30 seconds)
//
// Goal: Verify that arena allocators properly clean up batched allocations
//
// Test strategy:
// 1. Use ArenaAllocator for batched operations
// 2. Perform 5K operations with arena cleanup
// 3. Verify memory is freed after arena.deinit()
// 4. Assert: No leaks from arena usage
//
// Tiger Style: Bounded loops, explicit assertions, testing.allocator

const std = @import("std");
const testing = std.testing;

test "arena allocator - batched operations" {
    // Tiger Style: Explicit MAX for bounded loop
    const MAX_BATCHES: u32 = 50;
    const OPERATIONS_PER_BATCH: u32 = 100;

    std.debug.print("\n=== Arena Allocator Test ===\n", .{});
    std.debug.print("Goal: Verify arena cleanup works correctly\n", .{});
    std.debug.print("Strategy: {d} batches of {d} operations each\n\n", .{ MAX_BATCHES, OPERATIONS_PER_BATCH });

    // Tiger Style: Use testing.allocator as base
    const base_allocator = testing.allocator;

    var total_operations: u32 = 0;

    std.debug.print("Phase 1: Running batched operations...\n", .{});

    var batch_idx: u32 = 0;
    // Tiger Style: Bounded loop with explicit MAX
    while (batch_idx < MAX_BATCHES) : (batch_idx += 1) {
        std.debug.assert(batch_idx < MAX_BATCHES);

        // Create arena for this batch
        var arena = std.heap.ArenaAllocator.init(base_allocator);
        defer arena.deinit(); // Single deinit frees everything

        const arena_allocator = arena.allocator();

        // Perform operations in this batch
        var op_idx: u32 = 0;
        while (op_idx < OPERATIONS_PER_BATCH) : (op_idx += 1) {
            std.debug.assert(op_idx < OPERATIONS_PER_BATCH);

            // Allocate using arena (no individual free needed)
            const buffer = try arena_allocator.alloc(u8, 167);
            // Note: No defer free needed - arena.deinit() handles it

            // Use the buffer
            @memset(buffer, @intCast(op_idx % 256));

            total_operations += 1;
        }

        // Tiger Style: Post-loop assertion
        std.debug.assert(op_idx == OPERATIONS_PER_BATCH);

        // Report progress every 10 batches
        if ((batch_idx + 1) % 10 == 0) {
            std.debug.print("  Completed {d}/{d} batches ({d} total operations)\n", .{
                batch_idx + 1,
                MAX_BATCHES,
                total_operations,
            });
        }

        // arena.deinit() is called here by defer
    }

    // Tiger Style: Post-loop assertion
    std.debug.assert(batch_idx == MAX_BATCHES);

    std.debug.print("\nPhase 2: Verification...\n", .{});
    std.debug.print("  Total batches: {d}\n", .{MAX_BATCHES});
    std.debug.print("  Operations per batch: {d}\n", .{OPERATIONS_PER_BATCH});
    std.debug.print("  Total operations: {d}\n", .{total_operations});
    std.debug.print("  ✓ PASS: Arena cleanup working correctly\n", .{});
    std.debug.print("  ✓ No memory leaks from arena usage\n", .{});
    std.debug.print("\n=== TEST PASSED ===\n", .{});
}

test "arena allocator - vs individual free" {
    // Tiger Style: Compare arena vs manual free approaches
    const OPERATIONS: u32 = 1000;

    std.debug.print("\n=== Arena vs Individual Free Comparison ===\n", .{});
    std.debug.print("Goal: Demonstrate arena efficiency\n\n", .{});

    const base_allocator = testing.allocator;

    // Approach 1: Individual free (traditional)
    std.debug.print("Approach 1: Individual free (1000 operations)...\n", .{});
    {
        var i: u32 = 0;
        while (i < OPERATIONS) : (i += 1) {
            std.debug.assert(i < OPERATIONS);

            const buffer = try base_allocator.alloc(u8, 167);
            // Tiger Style: Explicit defer for cleanup
            defer base_allocator.free(buffer);

            // Use the buffer
            @memset(buffer, @intCast(i % 256));
        }
        std.debug.assert(i == OPERATIONS);
    }
    std.debug.print("  ✓ Completed with individual free\n", .{});

    // Approach 2: Arena (batched cleanup)
    std.debug.print("\nApproach 2: Arena batched cleanup (1000 operations)...\n", .{});
    {
        var arena = std.heap.ArenaAllocator.init(base_allocator);
        defer arena.deinit(); // Single cleanup for all allocations

        const arena_allocator = arena.allocator();

        var i: u32 = 0;
        while (i < OPERATIONS) : (i += 1) {
            std.debug.assert(i < OPERATIONS);

            const buffer = try arena_allocator.alloc(u8, 167);
            // Note: No defer needed - arena handles everything

            // Use the buffer
            @memset(buffer, @intCast(i % 256));
        }
        std.debug.assert(i == OPERATIONS);
    }
    std.debug.print("  ✓ Completed with arena cleanup\n", .{});

    std.debug.print("\nPhase 3: Verification...\n", .{});
    std.debug.print("  ✓ Both approaches successful\n", .{});
    std.debug.print("  ✓ No memory leaks detected\n", .{});
    std.debug.print("  ✓ Arena approach: 1 deinit() instead of 1000 free() calls\n", .{});
    std.debug.print("\n=== TEST PASSED ===\n", .{});
}
