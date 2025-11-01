# Changelog

All notable changes to Pyjamaz will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added - Milestone 3: Native Codec Integration (2025-11-01)

**Native Codecs (2,157 lines total):**
- JPEG (`src/codecs/jpeg.zig`, 642 lines): libjpeg-turbo 3.x, quality 0-100, RGBA→RGB conversion, magic validation
- PNG (`src/codecs/png.zig`, 473 lines): libpng 1.6, compression 0-9, C callback error tracking, lossless
- WebP (`src/codecs/webp.zig`, 457 lines): libwebp 1.6, lossless at quality=100, always returns RGBA
- AVIF (`src/codecs/avif.zig`, 585 lines): libavif 1.3, speed presets -1 to 10, YUV420, always returns RGBA
- Unified API (`src/codecs/api.zig`, 440 lines): Format detection, magic number defense-in-depth, capability queries

**Performance & Safety:**
- Heap allocation for RGBA conversion (was 196KB stack, now dynamic)
- C callback error propagation (PNG OOM tracking, no silent corruption)
- Tiger Style: 4-8 assertions/function, bounded loops, RAII cleanup, zero leaks
- Tests: 126/127 passing (99.2%), 16 codec tests, zero memory leaks

**Documentation:**
- Added `TO-FIX.md`: Comprehensive Tiger Style review report
- Added `FIXES-APPLIED.md`: Detailed fix documentation
- Updated `src/CLAUDE.md`: Native codec FFI patterns, stack vs heap rules, C callback error handling

### Added - Comprehensive Memory Testing Suite (2025-10-31)

- 12 test files: 3 Zig + 4 Node.js + 4 Python (~3,200 lines)
- Zig: `memory_leak_test.zig` (10K cycles), `arena_allocator_test.zig` (5K ops), `error_recovery_test.zig` (3 tests)
- Node.js: GC verification (10K ops), FFI tracking (5K ops), error recovery, buffer management
- Python: GC verification (psutil), ctypes tracking, exception cleanup, buffer management
- Build integration: `zig build memory-test` (~1 min), manual binding tests
- Documentation: `MEMORY_TESTS.md` (600+ lines), updated README/TODO
- Results: 8/8 Zig tests passing, 0 memory leaks, Tiger Style compliant

### Fixed - Polish & Code Quality Improvements (2025-10-31)

- Node.js: Added `pyjamaz_cleanup` FFI binding, `PyjamazBindingError` class, standardized error types
- Cache: Bounds checking in `parseMetadata` (7 validation points), prevents panic on malformed data
- Python: Type hints for ctypes structures, fixed bare except clause in `_find_library`

### Fixed - Tiger Style Compliance & Safety Improvements (2025-10-31)

- Bounded loops: `MAX_FORMATS = 10` in `src/api.zig` with pre/post assertions
- FFI assertions: 4+ checks in `pyjamaz_optimize` (input_len, concurrency, result integrity)
- Memory leak fix: `error_message_allocated` flag for heap vs static messages
- Cache eviction: Fixed assertion for >1000 entries (`src/cache.zig:404-416`)
- Type safety: `file_size` changed from `u32` to `u64` (supports >4GB files)
- Python validation: Parameter bounds, 100MB file limit, empty file rejection, metric enum checks
- Node.js safety: Null pointer checks, size bounds (100MB output, 1KB errors), UTF-8 validation
- Function length: `optimizeImage` refactored 168→62 lines (extracted `tryCacheHit`, `storeCacheResult`)
- Result: Zero critical issues, all tests passing, production ready

### Added - Intelligent Caching System (2025-10-31)

- Blake3 content-addressed caching, LRU eviction (default 1GB), 15-20x speedup (5ms vs 100ms)
- CLI flags: `--cache-dir`, `--no-cache`, `--cache-max-size`
- Optimizer: `cache_ptr` field, lookup/storage in `optimizeImage()`, graceful degradation
- 18 tests passing (config, key computation, put/get, metadata parsing, zero leaks)
- Cache location: `~/.cache/pyjamaz/` or `$XDG_CACHE_HOME/pyjamaz/`

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

- Core pipeline (decode → transform → encode → select), libvips integration
- JPEG (libjpeg-turbo), PNG (libpng) encoders, binary search size targeting
- CLI tool with batch processing, directory discovery
- 67 unit tests, 208 conformance tests, zero memory leaks
- Tiger Style: 2+ assertions, bounded loops, ≤70 lines
- Automatic format selection, size budget enforcement

---

**Last Updated**: 2025-11-01
