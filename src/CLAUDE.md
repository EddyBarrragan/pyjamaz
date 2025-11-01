# Source Code Implementation Guide

**Purpose**: Quick reference for implementation patterns, code organization, and Zig-specific guidelines.

---

## Table of Contents

1. [Source Organization](#source-organization)
2. [Cross-Language API Consistency](#cross-language-api-consistency)
3. [Tiger Style Enforcement](#tiger-style-enforcement)
4. [Type Conventions](#type-conventions)
5. [Memory Management](#memory-management)
6. [Error Handling](#error-handling)
7. [Testing](#testing)
8. [Documentation Updates](#documentation-updates)

---

## Source Organization

### Directory Structure
- `src/main.zig` - Entry point
- `src/[module]/` - Feature modules (one per directory)
- `src/test/unit/` - Unit tests (mirrors src/ structure)
- `src/test/integration/` - Integration tests
- `src/test/benchmark/` - Performance tests

### File Organization
- **One module per directory** - Group related functionality
- **Mirror test structure** - `src/foo/bar.zig` → `src/test/unit/foo/bar_test.zig`
- **Keep files focused** - Single, clear purpose per file
- **Public API first** - Export functions/types at top

---

## Cross-Language API Consistency

**CRITICAL**: This project provides bindings for multiple languages. ALL changes must propagate across language boundaries.

### The Rule
When you modify core Zig functionality, you MUST:

1. **Update Node.js bindings** (`bindings/node/`)
   - Update TypeScript types in `.d.ts` files
   - Update FFI calls in implementation
   - Add tests in `bindings/node/test/`
   - Update examples if API changed

2. **Update Python bindings** (`bindings/python/`)
   - Update Python wrapper in `pyjamaz/` module
   - Update type hints
   - Add tests in `bindings/python/tests/`
   - Update examples if API changed

3. **Test ALL languages**
   ```bash
   # Zig tests
   zig build test

   # Node.js tests
   cd bindings/node && npm test

   # Python tests
   cd bindings/python && python -m pytest tests/
   ```

### Examples of Changes That Propagate

**New Feature** → Add to Zig, Node.js wrapper, Python wrapper + tests in all three

**API Change** → Update function signature in all three + update all tests

**Bug Fix** → Fix in Zig, add regression test in all three languages

**Performance Optimization** → Add benchmark in all three languages

### Checklist Before Commit
- [ ] Zig implementation complete
- [ ] Zig tests pass (`zig build test`)
- [ ] Node.js wrapper updated
- [ ] Node.js tests pass (`npm test`)
- [ ] Python wrapper updated
- [ ] Python tests pass (`pytest`)
- [ ] Examples updated (if API changed)
- [ ] Documentation updated in all three

**Remember**: Users may consume this library from any language. Consistency across bindings is NOT optional - it's a requirement for quality.

---

## Tiger Style Enforcement

### The Four Pillars
1. **Safety First** - 2+ assertions per function
2. **Predictable Performance** - Bounded loops, known complexity
3. **Developer Experience** - ≤70 lines per function, clear naming
4. **Zero Dependencies** - Only Zig stdlib (except system libraries)

### Safety Requirements

**Assertions (2+ per function)**:
- Pre-conditions - Validate inputs
- Post-conditions - Validate outputs
- Invariants - Validate state throughout
- Post-loop - Verify loop termination

**Bounded Loops**:
- ❌ `while (condition)` - Could run forever
- ✅ `while (i < MAX and condition) : (i += 1)` - Explicit upper bound
- Always assert after loops: `std.debug.assert(i <= MAX);`

**Function Size**:
- ≤70 lines per function
- Break large functions into focused smaller ones
- Each function should do one thing well

---

## Type Conventions

### Use Explicit Types
- ✅ `const count: u32 = 100;` - Platform-independent
- ✅ `const size_bytes: u64 = 1024 * 1024;` - Clear intent
- ❌ `const count: usize = 100;` - Changes between 32/64-bit

### When to Use `usize`
- Memory addresses: `@intFromPtr()`, `@ptrFromInt()`
- Array/slice lengths: `array.len` returns `usize`
- Allocator APIs: `allocator.alloc()` takes `usize`
- **Pattern**: Use `u32` for business logic, cast to `usize` at API boundaries

---

## Memory Management

### Allocator Patterns

**1. General Purpose Allocator (GPA)**
- Use for: Long-lived allocations, variable sizes
- Cleanup: Individual `free()` calls required

**2. Arena Allocator**
- Use for: Many small allocations, batch cleanup
- Cleanup: Single `arena.deinit()` frees everything
- Best for: Temporary allocations in function scope

**3. Fixed Buffer Allocator**
- Use for: Stack-based allocation, known max size
- Cleanup: None needed (stack-allocated buffer)

### Memory Ownership

**Caller-Allocated (Preferred)**:
- Pros: No allocations, fast
- Cons: Caller provides buffer
- Example: `fn format(data: Data, buffer: []u8) !usize`

**Function-Allocated**:
- Pros: Convenient
- Cons: Caller must free
- Example: `fn allocAndFormat(allocator: Allocator, data: Data) ![]u8`
- Document: "Caller owns returned memory and must free it"

**Arena-Allocated**:
- Pros: Batch cleanup, no individual frees
- Cons: Memory held until arena deinit
- Use for: Multiple temporary allocations in one function

### Memory Leak Detection
- Use `testing.allocator` in all tests
- Automatically fails if leaks detected
- Run operations 1000+ times to catch leaks

---

## Error Handling

### Patterns

**1. Propagate (Default)**:
- `const result = try inner();` - Propagate on error

**2. Handle Specific Errors**:
- Use `switch` to handle specific errors differently
- Propagate unhandled errors

**3. Convert Errors**:
- Catch and return domain-specific error
- Log original error for debugging

**4. Critical Section (Use Sparingly)**:
- `const result = operation() catch unreachable;`
- Only when you can PROVE it won't fail
- Document why it's safe

---

## Testing

### Test Organization
- **Unit Tests**: `src/test/unit/[module]/[file]_test.zig`
- **Integration Tests**: `src/test/integration/`
- **Benchmarks**: `src/test/benchmark/`
- **Conformance**: `src/test/conformance_runner.zig` (if applicable)

### Test Requirements
- Use `testing.allocator` - Catches memory leaks
- Test error conditions, not just success paths
- Run operations 1000+ times to catch intermittent issues
- Test edge cases (empty input, max values, etc.)

### Common Patterns
- Setup/Teardown: Use `defer` for cleanup
- Multiple Assertions: Test all aspects of result
- Error Testing: Use `testing.expectError(error.Type, result)`

---

## Documentation Updates

### Checklist Before Commit
- [ ] `zig fmt src/` - Format code
- [ ] `zig build test` - All tests pass
- [ ] No compiler warnings
- [ ] Documentation updated (if API changed)
- [ ] TODO.md updated (if task completed)

### Checklist After Milestone Completion

**CRITICAL**: Update these files for every significant milestone:

1. **../README.md** - User-facing documentation
   - Add new features to "Features" section
   - Update performance stats and benchmarks
   - Add code examples for new APIs
   - Update badges (test count, pass rate, coverage)

2. **../docs/CHANGELOG.md** - Complete change history
   - Add entry under `[Unreleased]` with date
   - **Use point-form format** (concise bullets, not paragraphs)
   - Structure: `### Added`, `### Changed`, `### Fixed`
   - Include technical details but keep brief
   - Document breaking changes
   - Use present tense ("Add", "Change") for unreleased

3. **../docs/TODO.md** - Milestone tracking
   - Mark completed tasks `[x]`
   - Update milestone status (IN PROGRESS → COMPLETE)
   - Add completion date
   - Update "Current Status" summary

**Milestone Documentation Example**:

After implementing caching:
- README.md: Add "💾 Intelligent Caching" to features, CLI examples
- CHANGELOG.md: Point-form entry with implementation details
- TODO.md: Mark Phase 1 complete, update status

**When NOT to Update**:
- Minor bug fixes (unless critical)
- Internal refactoring (unless performance impact)
- Test additions (unless revealing new capabilities)
- Documentation typo fixes

**Remember**: Documentation updates are part of the milestone!

---

## Quick Reference

### Tiger Style Checklist (Every Function)
- [ ] ≤70 lines
- [ ] 2+ assertions (pre/post/invariants)
- [ ] All loops bounded (explicit MAX)
- [ ] Post-loop assertions
- [ ] Clear ownership documented
- [ ] Explicit types (u32, not usize)
- [ ] Error handling (try/catch, not silent)
- [ ] Tests written

### Type Checklist
- [ ] Use `u32` for counts/indices (not `usize`)
- [ ] Use `u64` for byte sizes
- [ ] Use `usize` only for memory addresses/stdlib APIs
- [ ] Cast at API boundaries: `@intCast(u32_value)`

### Memory Checklist
- [ ] Allocator passed explicitly
- [ ] Ownership documented in comments
- [ ] `defer` cleanup immediately after allocation
- [ ] Use Arena for batch allocations
- [ ] Test with `testing.allocator`

### Test Checklist
- [ ] Unit test for every public function
- [ ] Error cases tested
- [ ] Edge cases covered
- [ ] Memory leaks checked (testing.allocator)
- [ ] Run 1000+ iterations for intermittent issues

---

## Critical Learnings

### Image Processing Safety (2025-10-30)

**Bound File I/O**:
- Always use `MAX_HASH_SIZE` when reading files
- Assert `total_read <= MAX` after loop

**Validate Image Dimensions**:
- Check `width > 0`, `height > 0`
- Check `width <= MAX_DIMENSION`, `height <= MAX_DIMENSION`
- Check `total_pixels <= MAX_PIXELS` (prevent decompression bombs)

**libvips Memory Management**:
- Use `defer` for C FFI cleanup
- Always `defer if (buffer_ptr != null) g_free(buffer_ptr);`

**Validate Codec Output**:
- Check magic numbers after encoding
- JPEG: `[0xFF, 0xD8]` (SOI marker)
- PNG: `[0x89, 0x50, 0x4E, 0x47]` (PNG signature)

**Binary Search Invariants**:
- Loop invariants inside binary search
- Assert `q_min <= q_max` at loop start
- Assert `q_mid >= q_min and q_mid <= q_max`

**Warn on Lossy Transformations**:
- Warn when encoding RGBA to format without alpha support
- Log when operations will lose data

### FFI Boundary Safety (2025-10-31)

**Validate ALL Inputs at FFI Boundaries**:
- Check file sizes before reading (MAX: 100MB for images)
- Validate array lengths are non-zero and reasonable
- Check pointers are non-null before dereferencing
- Validate enum values are in valid range
- Validate UTF-8 before converting C strings

**Python ctypes Safety**:
```python
# ✅ VALIDATE before FFI call
MAX_INPUT_SIZE = 100 * 1024 * 1024
if len(input_bytes) == 0:
    raise ValueError("Input cannot be empty")
if len(input_bytes) > MAX_INPUT_SIZE:
    raise ValueError(f"Input too large: {len(input_bytes)}")
if concurrency < 1 or concurrency > 16:
    raise ValueError(f"concurrency must be 1-16, got {concurrency}")
```

**Node.js ref-napi Safety**:
```typescript
// ✅ VALIDATE C memory before reading
if (result.output_len > 0) {
    if (result.output_bytes.isNull()) {
        throw new Error('Invalid: output_bytes null but length > 0');
    }
    const MAX_OUTPUT_SIZE = 100 * 1024 * 1024;
    if (result.output_len > MAX_OUTPUT_SIZE) {
        throw new Error(`Output too large: ${result.output_len}`);
    }
    const outputData = ref.reinterpret(result.output_bytes, result.output_len, 0);
    data = Buffer.from(outputData);
}
```

**Zig FFI Export Safety**:
- Add assertions at entry: validate options, check nulls
- Bounded loops for string parsing (format lists, etc.)
- Use explicit MAX constants: `MAX_FORMATS = 10`
- Assert after parsing: `formats_list.items.len > 0 and <= MAX`
- Never trust input sizes - clamp to reasonable limits

**Memory Ownership at FFI Boundary**:
- Track allocation source: heap vs static string
- Add `_allocated` flag to result structs if needed
- Document who owns memory (caller vs callee)
- Free consistently based on ownership flags

### Zig 0.15 Changes (2025-10-30)

**ArrayList Unmanaged API**:
- ✅ `var list = ArrayList(T){}; list.deinit(allocator);`
- ✅ `list.append(allocator, item);`
- ❌ Old: `ArrayList(T).init(allocator)`

**File I/O Changes**:
- ✅ `file.writeAll(bytes);`
- ❌ Old: `file.writer().writeAll(bytes)`

**Manual JSON Serialization**:
- Zig 0.15 std.json API changed
- Use manual serialization for stability
- Escape strings: `\\`, `\"`, `\n`

### Native Codec Integration (2025-11-01)

**C Library FFI Best Practices**:
- Copy C-allocated memory to Zig allocator immediately
- Always `defer` cleanup for C resources (jpeg_destroy, WebPFree, avifRWDataFree)
- Validate C pointer results before dereferencing
- Check return codes from C functions, convert to Zig errors

**Magic Number Defense-in-Depth**:
- Validate on decode (input validation)
- Validate on encode (output verification)
- Example: `api.zig:78` - verify after encoding for defense

**Format-Specific Limits**:
- JPEG/PNG: 65535 max dimension (16-bit)
- WebP: 16383 max dimension (14-bit + 1)
- AVIF: 65536 max dimension
- All: 100MB max input size (decompression bomb protection)

**Channel Handling**:
- JPEG: Always RGB (3 channels), RGBA→RGB conversion required
- PNG: Preserves channel count (RGB=3, RGBA=4)
- WebP: Decode always returns RGBA (4 channels) for consistency
- AVIF: Decode always returns RGBA (4 channels) for consistency
- Document channel changes in function comments

**Lossless Encoding Triggers**:
- WebP: `quality == 100` triggers `WebPEncodeLosslessRGB/RGBA`
- AVIF: `quality == 100` uses quality=100 (near-lossless)
- PNG: Always lossless, quality controls compression level (0-9)
- JPEG: Always lossy, no lossless mode

**RAII Pattern for C FFI**:
```zig
// ✅ GOOD: Cleanup immediately after allocation
const png_ptr = png_create_write_struct(...) orelse return Error.InitFailed;
var png_ptr_opt: ?*png_structp = png_ptr;
defer png_destroy_write_struct(&png_ptr_opt, &info_ptr_opt);

const encoder = avifEncoderCreate() orelse return Error.InitFailed;
defer avifEncoderDestroy(encoder);
```

**Stack vs Heap Allocation**:
- Small buffers (<4KB): Stack allocation OK
- Large buffers (>4KB): Use heap allocation to avoid stack overflow
- Example: JPEG RGB conversion buffer (196KB) should use heap
- Rule: If buffer size depends on user input (dimensions), use heap

**Error Propagation from C Callbacks**:
```zig
// ❌ BAD: Silent failure in C callback
fn callback(...) callconv(.c) void {
    operation() catch return; // Error lost!
}

// ✅ GOOD: Track error in context, check after callback returns
const Context = struct {
    data: ArrayList(u8),
    had_error: bool = false,
};
fn callback(...) callconv(.c) void {
    ctx.data.append(...) catch {
        ctx.had_error = true;
        return;
    };
}
// After C operation:
if (ctx.had_error) return Error.OperationFailed;
```

---

## Resources

- [Zig Language Reference](https://ziglang.org/documentation/master/)
- [Zig Standard Library](https://ziglang.org/documentation/master/std/)
- [Tiger Style Guide](../docs/TIGER_STYLE_GUIDE.md)
- [Project Architecture](../docs/ARCHITECTURE.md)

---

**Last Updated**: 2025-11-01
**Version**: 2.1 (Milestone 3: Native Codecs)
