// Memory Test Root
//
// Entry point for memory tests. Imports all memory test files.
// Tiger Style: Comprehensive memory safety verification
//
// Run with: zig build memory-test-zig

// Import all memory test files
test {
    _ = @import("test/memory/memory_leak_test.zig");
    _ = @import("test/memory/arena_allocator_test.zig");
    _ = @import("test/memory/error_recovery_test.zig");
}
