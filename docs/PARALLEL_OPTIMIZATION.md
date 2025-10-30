# Parallel Candidate Generation - Design Document

**Status**: 📋 Design Phase (for 0.2.0 or later)
**Priority**: P2 (Performance Optimization)
**Complexity**: Medium
**Estimated Effort**: 2-3 days

---

## Current State (MVP 0.1.0)

**Implementation**: Sequential encoding in `src/optimizer.zig:217-237`

```zig
// Sequential encoding (MVP)
for (formats) |format| {
    const candidate = encodeCandidateForFormat(
        allocator,
        buffer,
        format,
        max_bytes,
    ) catch |err| {
        const warning = try std.fmt.allocPrint(
            allocator,
            "Failed to encode {s}: {}",
            .{ @tagName(format), err },
        );
        try warnings.append(allocator, warning);
        continue;
    };
    try candidates.append(allocator, candidate);
}
```

**Performance**:
- Average: ~50-100ms per image (4 formats × 12-25ms each)
- Bottleneck: Encoding is CPU-intensive, sequential leaves cores idle
- Opportunity: 4x speedup possible with parallel encoding

---

## Goals

### Primary Goals
1. **Reduce optimization time**: Target 4x speedup for multi-format encoding
2. **Respect concurrency limits**: Honor `job.concurrency` parameter
3. **Maintain safety**: No data races, bounded thread count
4. **Graceful degradation**: Errors in one format don't affect others

### Non-Goals (Deferred)
- Thread pool reuse across multiple images (batch optimization - 0.3.0)
- SIMD optimization of encoding (codec-specific - future)
- GPU acceleration (out of scope for MVP++)

---

## Design Overview

### Architecture: Thread Pool Pattern

```
┌─────────────────────────────────────────────────────────┐
│ optimizeImage()                                          │
│                                                          │
│  1. Decode image → ImageBuffer                          │
│  2. Create thread pool (size = min(formats.len,         │
│                                   job.concurrency))     │
│  3. Spawn threads, each encodes 1+ formats              │
│  4. Collect results from all threads                    │
│  5. Select best candidate                               │
└─────────────────────────────────────────────────────────┘

Thread 1: Encode AVIF    ─┐
Thread 2: Encode WebP    ─┼─→ Candidates
Thread 3: Encode JPEG    ─┤
Thread 4: Encode PNG     ─┘
```

### Thread Safety Strategy

1. **Per-thread allocators**: Each thread uses `ArenaAllocator` for isolation
2. **Immutable shared data**: `ImageBuffer` is read-only, safe to share
3. **Result collection**: Each thread writes to pre-allocated result slot (no races)
4. **Error handling**: Each thread's errors captured independently

---

## Implementation Plan

### Phase 1: Thread-Safe Candidate Encoding (1 day)

**File**: `src/optimizer.zig`

**Changes**:
1. Add `EncodingTask` struct
2. Add `encodingWorker()` thread function
3. Modify `generateCandidates()` to spawn threads

**New Structures**:

```zig
/// Task for a single encoding thread
const EncodingTask = struct {
    thread: std.Thread,
    format: ImageFormat,
    result: ?EncodedCandidate, // null if error
    error_msg: ?[]u8, // null if success
};

/// Worker function executed by each thread
fn encodingWorker(
    parent_allocator: Allocator,
    buffer: *const ImageBuffer,
    format: ImageFormat,
    max_bytes: ?u32,
) EncodingTask.Result {
    // Each thread gets its own arena
    var arena = std.heap.ArenaAllocator.init(parent_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const candidate = encodeCandidateForFormat(
        allocator,
        buffer,
        format,
        max_bytes,
    ) catch |err| {
        return .{
            .candidate = null,
            .error_msg = try parent_allocator.dupe(
                u8,
                @errorName(err),
            ),
        };
    };

    // Clone candidate to parent allocator (arena will be freed)
    const cloned = try cloneCandidate(parent_allocator, candidate);
    return .{
        .candidate = cloned,
        .error_msg = null,
    };
}
```

**Modified `generateCandidates()`**:

```zig
fn generateCandidates(
    allocator: Allocator,
    buffer: *const ImageBuffer,
    formats: []const ImageFormat,
    max_bytes: ?u32,
    max_workers: u8,
    warnings: *ArrayList([]u8),
) !ArrayList(EncodedCandidate) {
    std.debug.assert(formats.len > 0);
    std.debug.assert(max_workers > 0);

    var candidates = ArrayList(EncodedCandidate){};
    errdefer {
        for (candidates.items) |*candidate| candidate.deinit(allocator);
        candidates.deinit(allocator);
    }

    // Determine thread count
    const num_threads = @min(formats.len, max_workers);

    // Spawn threads
    var tasks = try allocator.alloc(EncodingTask, num_threads);
    defer allocator.free(tasks);

    for (tasks, 0..) |*task, i| {
        task.* = .{
            .format = formats[i],
            .result = null,
            .error_msg = null,
        };

        task.thread = try std.Thread.spawn(.{}, encodingWorker, .{
            allocator,
            buffer,
            formats[i],
            max_bytes,
        });
    }

    // Collect results
    for (tasks) |*task| {
        task.thread.join();

        if (task.result) |candidate| {
            try candidates.append(allocator, candidate);
        } else if (task.error_msg) |err_msg| {
            const warning = try std.fmt.allocPrint(
                allocator,
                "Failed to encode {s}: {s}",
                .{ @tagName(task.format), err_msg },
            );
            try warnings.append(allocator, warning);
            allocator.free(err_msg);
        }
    }

    return candidates;
}
```

### Phase 2: Performance Validation (0.5 days)

**Benchmarks to Add**:

```zig
// src/test/benchmark/parallel_encoding.zig

test "benchmark: sequential vs parallel encoding" {
    const allocator = testing.allocator;

    // Test image (medium size, 1920×1080)
    const buffer = try createTestImage(allocator, 1920, 1080);
    defer buffer.deinit();

    const formats = [_]ImageFormat{ .avif, .webp, .jpeg, .png };

    // Sequential benchmark
    const seq_start = std.time.nanoTimestamp();
    const seq_candidates = try generateCandidates(
        allocator,
        &buffer,
        &formats,
        null,
        1, // Force sequential
        &warnings,
    );
    const seq_time = std.time.nanoTimestamp() - seq_start;

    // Parallel benchmark
    const par_start = std.time.nanoTimestamp();
    const par_candidates = try generateCandidates(
        allocator,
        &buffer,
        &formats,
        null,
        4, // 4 threads
        &warnings,
    );
    const par_time = std.time.nanoTimestamp() - par_start;

    // Verify speedup
    const speedup = @as(f64, @floatFromInt(seq_time)) /
                    @as(f64, @floatFromInt(par_time));

    std.debug.print("Sequential: {d}ms\n", .{seq_time / 1_000_000});
    std.debug.print("Parallel:   {d}ms\n", .{par_time / 1_000_000});
    std.debug.print("Speedup:    {d:.2}x\n", .{speedup});

    // Should see >2x speedup on 4 cores
    try testing.expect(speedup > 2.0);
}
```

### Phase 3: Tiger Style Compliance (0.5 days)

**Checklist**:

1. **Bounded Concurrency**: ✅ Already bounded by `max_workers`
   ```zig
   const num_threads = @min(formats.len, max_workers);
   std.debug.assert(num_threads <= max_workers);
   ```

2. **Assertions**: Add pre/post-conditions to `encodingWorker()`
   ```zig
   fn encodingWorker(...) !Result {
       std.debug.assert(buffer.width > 0);
       std.debug.assert(buffer.data.len > 0);

       // ... encoding ...

       std.debug.assert(result.candidate != null or result.error_msg != null);
       return result;
   }
   ```

3. **Memory Safety**: Each thread uses arena allocator (automatic cleanup)
   ```zig
   var arena = std.heap.ArenaAllocator.init(parent_allocator);
   defer arena.deinit(); // All thread allocations freed
   ```

4. **Error Handling**: Thread errors don't crash main thread
   ```zig
   // Thread errors captured in task.error_msg
   // Main thread continues with other formats
   ```

5. **Function Length**: `encodingWorker()` should be <70 lines
   - Current design: ~40 lines ✅

---

## Performance Analysis

### Expected Speedup

**Assumptions**:
- 4 cores available
- 4 formats to encode (AVIF, WebP, JPEG, PNG)
- Each encoding takes ~20ms
- Thread overhead: ~1ms

**Sequential**:
```
Total = 4 × 20ms = 80ms
```

**Parallel (4 threads)**:
```
Total = max(20ms) + 1ms overhead = 21ms
Speedup = 80ms / 21ms = 3.8x
```

**Real-World Expectations**:
- Best case: 3-4x speedup (CPU-bound encoding)
- Typical: 2-3x speedup (memory bandwidth limits)
- Worst case: 1.5-2x speedup (thread contention)

### Trade-offs

**Pros**:
- ✅ 2-4x faster optimization
- ✅ Better CPU utilization
- ✅ Scales with core count

**Cons**:
- ❌ Increased memory usage (per-thread arenas)
- ❌ Thread spawn overhead (~1ms per thread)
- ❌ More complex code (harder to debug)

**When Parallel Wins**:
- Large images (>1MB): Encoding time dominates overhead
- Multi-format optimization: 4 formats = 4x parallelism
- Batch processing: Amortized thread creation

**When Sequential Wins**:
- Tiny images (<10KB): Overhead exceeds speedup
- Single format: No parallelism opportunity
- Low-end hardware: <4 cores, thread thrashing

---

## Testing Strategy

### Unit Tests

```zig
test "parallel encoding: produces same results as sequential" {
    // Verify parallel produces identical candidates (different order OK)
}

test "parallel encoding: handles errors gracefully" {
    // Inject encoding error for one format
    // Verify other formats still succeed
}

test "parallel encoding: respects max_workers limit" {
    // Set max_workers = 2, formats = 4
    // Verify only 2 threads spawn
}

test "parallel encoding: no memory leaks with thread arenas" {
    // Run 1000 times with testing.allocator
    // Verify no leaks
}
```

### Integration Tests

```zig
test "conformance: parallel vs sequential produce same pass rate" {
    // Run conformance suite with sequential
    // Run conformance suite with parallel
    // Verify identical pass rates
}
```

---

## Migration Path

### Backward Compatibility

**Option 1: Feature Flag** (Recommended for MVP++)

```zig
pub const OptimizationJob = struct {
    // ...
    concurrency: u8 = 4,
    parallel_encoding: bool = true, // New flag
};

fn generateCandidates(...) !ArrayList(EncodedCandidate) {
    if (job.parallel_encoding and formats.len > 1 and max_workers > 1) {
        return generateCandidatesParallel(...);
    } else {
        return generateCandidatesSequential(...);
    }
}
```

**Option 2: Auto-detect** (Simpler)

```zig
// Automatically use parallel if >1 format and >1 worker
const use_parallel = formats.len > 1 and max_workers > 1;
```

### Rollout Plan

1. **0.2.0**: Add parallel encoding with feature flag (default: false)
2. **0.2.1**: Enable by default, monitor for issues
3. **0.3.0**: Remove sequential codepath if no issues

---

## Tiger Style Compliance Checklist

- [ ] All loops bounded (thread count bounded by `max_workers`)
- [ ] 2+ assertions per function (`encodingWorker`, `generateCandidates`)
- [ ] Explicit error handling (thread errors captured, not ignored)
- [ ] Memory safety (per-thread arenas, no races)
- [ ] Function length ≤70 lines (break into helpers if needed)
- [ ] Performance justification (back-of-envelope: 2-4x speedup)
- [ ] Unit tests (4+ tests covering happy/error paths)
- [ ] No unbounded parallelism (respect `max_workers`)

---

## Alternative Approaches Considered

### 1. Thread Pool Reuse (Deferred to 0.3.0)

**Idea**: Reuse threads across multiple images in batch processing

**Pros**: Amortize thread creation cost
**Cons**: Adds complexity (job queue, synchronization)
**Decision**: Defer to batch optimization phase (0.3.0)

### 2. Async/Await (Future Consideration)

**Idea**: Use async/await instead of threads

**Pros**: Lighter weight than threads
**Cons**: Zig async is experimental, may change
**Decision**: Wait for Zig async stabilization

### 3. SIMD Encoding (Codec-Specific)

**Idea**: Optimize encoding with SIMD instructions

**Pros**: Single-threaded speedup
**Cons**: Codec-specific, requires deep knowledge
**Decision**: Out of scope for general optimizer

---

## Implementation Estimate

**Total Effort**: 2-3 days

| Phase | Effort | Risk |
|-------|--------|------|
| Thread-safe encoding | 1 day | Low (std.Thread is stable) |
| Performance validation | 0.5 day | Low (benchmarking is straightforward) |
| Tiger Style compliance | 0.5 day | Low (design already compliant) |
| Testing & debugging | 1 day | Medium (thread bugs can be subtle) |

**Dependencies**:
- None (uses only std.Thread from stdlib)

**Risks**:
- **Thread contention**: Mitigated by per-thread arenas
- **Debugging complexity**: Mitigated by feature flag (can fall back to sequential)
- **Platform differences**: Mitigated by Zig's cross-platform thread API

---

## Success Criteria

1. **Performance**: 2-4x speedup on multi-format optimization
2. **Correctness**: Conformance tests pass at same rate as sequential
3. **Safety**: No memory leaks, no data races
4. **Usability**: Transparent to users (just faster)
5. **Maintainability**: Code remains <70 lines per function

---

## References

- [Zig std.Thread Documentation](https://ziglang.org/documentation/master/std/#std.Thread)
- [Tiger Style Guide](../docs/TIGER_STYLE_GUIDE.md) - Bounded parallelism
- [src/CLAUDE.md](../src/CLAUDE.md) - Memory management patterns

---

**Last Updated**: 2025-10-30
**Status**: 📋 Design Complete - Ready for Implementation
