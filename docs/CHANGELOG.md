# Changelog

All notable changes to Pyjamaz will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Fixed - Polish & Code Quality Improvements (2025-10-31)

**Node.js Bindings**:
- Added `pyjamaz_cleanup` to FFI library definitions in `bindings/nodejs/src/bindings.ts`
- Cleanup function now properly calls native cleanup on process exit
- Added `PyjamazBindingError` class for FFI-layer error handling
- Standardized error types: FFI errors use `PyjamazBindingError`, API errors use `PyjamazError`

**Cache Safety**:
- Added bounds checking to `parseMetadata` in `src/cache.zig`
- Validates `start < json_bytes.len` before accessing string slices
- Validates `end > start` before creating slices
- Prevents panic on malformed cache metadata (7 validation points added)

**Python Bindings**:
- Added type hints to ctypes structures (`_OptimizeOptions`, `_OptimizeResult`)
  - `_fields_: List[Tuple[str, Any]]` for better IDE support
- Fixed bare except clause in `_find_library` function
  - Now catches specific `Exception` and logs warning to stderr
  - Cleaner error handling pattern

### Fixed - Tiger Style Compliance & Safety Improvements (2025-10-31)

**Critical Fixes (All 8 Resolved)**:

- **Bounded Loops**: Added `MAX_FORMATS = 10` constant to format parsing in `src/api.zig`
  - Loop now terminates after max 10 iterations with assertions
  - Pre/post-loop assertions verify bounded execution

- **Assertions at FFI Boundaries**: Added 4+ assertions to `pyjamaz_optimize` in `src/api.zig`
  - Pre-conditions: `input_len > 0`, `concurrency` in range 1-16
  - Post-conditions: result integrity (passed = output present)
  - Invariants: format list within bounds

- **Memory Leak Fix**: Added `error_message_allocated` flag to `OptimizeResult`
  - Explicit tracking of heap vs static error messages
  - Clean deallocation in `pyjamaz_free_result` based on flag
  - Eliminates fragile string comparison logic

- **Cache Eviction Safety**: Fixed loop assertion in `src/cache.zig:404-416`
  - Changed from checking loop index to checking eviction count
  - Prevents assertion failure when cache has >1000 entries

- **Type Safety**: Changed `file_size` from `u32` to `u64` throughout
  - `EncodedCandidate.file_size`: now supports files >4GB
  - `CacheMetadata.file_size`: consistent type across codebase
  - Updated conformance test runner to match

- **Python Bindings Validation**: Added comprehensive input validation
  - Parameter bounds: concurrency (1-16), max_bytes (≥0), max_diff (0.0-1.0)
  - File size limit: 100MB max before reading
  - Empty file/bytes rejection
  - Metric enum validation

- **Node.js Bindings Safety**: Added memory safety checks before FFI reads
  - Null pointer validation before `ref.reinterpret`
  - Size bounds: 100MB max output, 1KB max error messages
  - UTF-8 validation with try-catch for error messages
  - Graceful handling of invalid C memory

- **Function Length Compliance**: Refactored `optimizeImage` from 168 → 62 lines
  - Extracted `tryCacheHit()` helper (60 lines)
  - Extracted `storeCacheResult()` helper (48 lines)
  - Main function now ≤70 lines (Tiger Style compliant)

**Tiger Style Compliance**:

- All critical functions have ≥2 assertions
- All loops bounded with explicit MAX constants
- FFI boundaries validated on both sides (Zig + bindings)
- Function length: all ≤70 lines
- Explicit types: using u32/u64 appropriately

**Production Readiness**:

- ✅ Zero critical safety issues
- ✅ All tests passing
- ✅ Shared library builds successfully
- ✅ Ready for Python/Node.js bindings usage

**Remaining Polish Items** (4 non-critical):

1. Add `pyjamaz_cleanup` to Node.js FFI definitions
2. Add bounds checking to `parseMetadata` manual JSON parser
3. Add Python type hints to ctypes structures
4. Standardize Node.js error types

### Added - Intelligent Caching System (2025-10-31)

**Core Implementation**:

- Content-addressed caching with Blake3 hashing
- Cache key: `Blake3(input_bytes + max_bytes + max_diff + metric_type + format)`
- LRU eviction policy with configurable max size (default 1GB)
- Cache location: `~/.cache/pyjamaz/` or `$XDG_CACHE_HOME/pyjamaz/`
- 15-20x speedup on cache hits (~5ms vs 100ms full optimization)

**CLI Integration**:

- New flags: `--cache-dir`, `--no-cache`, `--cache-max-size`
- Added fields to `CliConfig`: `cache_dir`, `cache_enabled`, `cache_max_size`
- Cache enabled by default (can disable with `--no-cache`)

**Optimizer Integration**:

- Added `cache_ptr: ?*Cache` field to `OptimizationJob`
- Cache lookup at start of `optimizeImage()` and `optimizeImageFromBuffer()`
- Cache storage after successful optimization
- Optional caching (null pointer = disabled)
- Graceful degradation (cache failures don't break optimization)

**Test Coverage**:

- 18 tests: config, key computation, init/deinit, put/get, clear, metadata parsing
- Edge cases: large files (1MB), disabled cache, multiple formats
- All tests passing with zero memory leaks

**Technical Notes**:

- Tiger Style compliant (bounded loops, 2+ assertions per function)
- Zig 0.15 compatible (manual JSON serialization, direct file.writeAll())
- Same input + same options = same cache key = instant result
- Different options = different keys (no collisions)

**Future Enhancements**:

- Cache support for C API, Python bindings, Node.js bindings
- Cache statistics and monitoring
- Cache warming strategies
- Distributed cache (Redis, Memcached)

---

## [0.5.0] - 2025-10-31

### Added

- SSIMULACRA2 perceptual metric (native Zig via fssimu2)
- CLI flags: `--metric`, `--sharpen`, `--flatten`, `-v/-vv/-vvv`, `--seed`
- Exit codes: 0 (success), 1 (failure), 10-14 (specific errors)
- Manifest generation (JSONL format)
- Comprehensive error classification system

### Changed

- Conformance test pass rate: 197/211 (93%)
- Enhanced CLI help text with examples

---

## [0.4.0] - 2025-10-31

### Added

- DSSIM metric calculations (FFI bindings to libdssim)
- Dual-constraint validation (size + quality)
- Enhanced manifest output with perceptual scores
- Perceptual metrics framework

### Changed

- Conformance test pass rate: 197/211 (93%)

---

## [0.3.0] - 2025-10-30

### Added

- WebP encoder support (via libvips)
- AVIF encoder support (via libvips)
- Original file baseline candidate (prevents size regressions)
- Format preference ordering

### Changed

- Conformance test pass rate: 168/205 (92%)

---

## [0.2.0] - 2025-10-30

### Added

- Parallel candidate generation (1.2-1.4x speedup with 4 cores)
- Configurable concurrency (1-8 threads)
- Benchmark suite for performance testing

---

## [0.1.0] - 2025-10-30 (MVP)

### Added

- Core optimization pipeline (decode → transform → encode → select)
- libvips integration for image processing
- JPEG encoder (via libjpeg-turbo)
- PNG encoder (via libpng)
- Binary search for size targeting
- CLI tool with batch processing
- 67 unit tests, 208 conformance tests
- Tiger Style methodology (2+ assertions, bounded loops, ≤70 lines)

### Features

- Automatic format selection
- Size budget enforcement
- Perceptual quality metrics foundation
- Batch processing with directory discovery
- Zero memory leaks (verified with testing.allocator)

---

## Changelog Guidelines

### Format Rules

- **Use point-form** (bullets and sub-bullets, not paragraphs)
- **Be concise** (1-2 lines per bullet max)
- **Group related items** (use sub-bullets)
- **Technical details** (mention file names, line counts, key functions)

### When to Update

- After completing major milestone or feature
- Keep `[Unreleased]` section current during development
- Move to versioned section before release

### Structure

- `### Added` - New features, files, capabilities
- `### Changed` - Modifications to existing functionality
- `### Deprecated` - Soon-to-be-removed features
- `### Removed` - Deleted features or files
- `### Fixed` - Bug fixes
- `### Security` - Security vulnerability fixes

### Example Format

```markdown
### Added - Feature Name (YYYY-MM-DD)

**Core Implementation**:

- Key point 1
- Key point 2
  - Sub-point with detail
  - Sub-point with detail

**New Files**:

- `src/module.zig` (XXX lines) - Description
  - Key function 1
  - Key function 2

**Technical Notes**:

- Important implementation detail
- Performance characteristic
- Limitation or caveat
```

---

**Last Updated**: 2025-10-31
**Project**: Pyjamaz - High-performance image optimizer
