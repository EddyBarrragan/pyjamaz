//! Unit tests for cache.zig
//!
//! Tiger Style: Comprehensive test coverage for caching system

const std = @import("std");
const testing = std.testing;
const fs = std.fs;
const cache_mod = @import("../../cache.zig");
const Cache = cache_mod.Cache;
const CacheConfig = cache_mod.CacheConfig;
const CacheMetadata = cache_mod.CacheMetadata;
const types = @import("../../types.zig");
const ImageFormat = types.ImageFormat;
const MetricType = types.MetricType;

// Helper counter for unique test paths
var test_counter: u32 = 0;

/// Get unique test path in /tmp (avoids cluttering project root)
fn getTestCachePath(allocator: std.mem.Allocator) ![]const u8 {
    test_counter += 1;
    return std.fmt.allocPrint(allocator, "/tmp/pyjamaz-test-{d}", .{test_counter});
}

// ============================================================================
// CacheConfig Tests
// ============================================================================

test "CacheConfig.init creates default config" {
    const config = CacheConfig.init("/tmp/test-cache");

    try testing.expectEqualStrings("/tmp/test-cache", config.cache_dir);
    try testing.expectEqual(cache_mod.DEFAULT_MAX_CACHE_SIZE, config.max_size_bytes);
    try testing.expect(config.enabled);
}

test "CacheConfig.getDefaultCacheDir returns valid path" {
    const allocator = testing.allocator;

    const cache_dir = CacheConfig.getDefaultCacheDir(allocator) catch |err| {
        // It's OK if HOME/XDG_CACHE_HOME is not set in test environment
        if (err == error.NoCacheDir) return error.SkipZigTest;
        return err;
    };
    defer allocator.free(cache_dir);

    try testing.expect(cache_dir.len > 0);
    try testing.expect(std.mem.endsWith(u8, cache_dir, "pyjamaz"));
}

// ============================================================================
// Cache.computeKey Tests
// ============================================================================

test "Cache.computeKey is deterministic" {
    const input1 = "test image data 12345";
    const input2 = "test image data 12345"; // Same content
    const input3 = "different image data";

    const key1 = Cache.computeKey(input1, 1000, 0.01, .dssim, .jpeg);
    const key2 = Cache.computeKey(input2, 1000, 0.01, .dssim, .jpeg);
    const key3 = Cache.computeKey(input3, 1000, 0.01, .dssim, .jpeg);

    // Same input + options = same key
    try testing.expectEqual(key1, key2);

    // Different input = different key
    try testing.expect(!std.mem.eql(u8, &key1, &key3));
}

test "Cache.computeKey changes with options" {
    const input = "test image data";

    // Different max_bytes
    const key1 = Cache.computeKey(input, 1000, 0.01, .dssim, .jpeg);
    const key2 = Cache.computeKey(input, 2000, 0.01, .dssim, .jpeg);
    try testing.expect(!std.mem.eql(u8, &key1, &key2));

    // Different max_diff
    const key3 = Cache.computeKey(input, 1000, 0.02, .dssim, .jpeg);
    try testing.expect(!std.mem.eql(u8, &key1, &key3));

    // Different metric
    const key4 = Cache.computeKey(input, 1000, 0.01, .ssimulacra2, .jpeg);
    try testing.expect(!std.mem.eql(u8, &key1, &key4));

    // Different format
    const key5 = Cache.computeKey(input, 1000, 0.01, .dssim, .png);
    try testing.expect(!std.mem.eql(u8, &key1, &key5));
}

test "Cache.computeKey handles null options" {
    const input = "test image data";

    // null vs 0 should produce different keys
    const key_null = Cache.computeKey(input, null, null, .none, .jpeg);
    const key_zero = Cache.computeKey(input, 0, 0.0, .none, .jpeg);

    try testing.expect(!std.mem.eql(u8, &key_null, &key_zero));
}

// ============================================================================
// Cache.init/deinit Tests
// ============================================================================

test "Cache.init creates cache directory" {
    const allocator = testing.allocator;

    // Use /tmp to avoid cluttering project root
    const cache_path = try getTestCachePath(allocator);
    defer allocator.free(cache_path);
    defer fs.deleteTreeAbsolute(cache_path) catch {};

    const config = CacheConfig.init(cache_path);
    var test_cache = try Cache.init(allocator, config);
    defer test_cache.deinit();

    // Verify cache directory was created
    var dir = try fs.openDirAbsolute(cache_path, .{});
    dir.close();
}

test "Cache.init handles existing directory" {
    const allocator = testing.allocator;

    const cache_path = try getTestCachePath(allocator);
    defer allocator.free(cache_path);
    defer fs.deleteTreeAbsolute(cache_path) catch {};

    // Create directory first
    try std.fs.makeDirAbsolute(cache_path);

    // Should not error
    const config = CacheConfig.init(cache_path);
    var test_cache = try Cache.init(allocator, config);
    defer test_cache.deinit();
}

// ============================================================================
// Cache.put/get Tests
// ============================================================================

test "Cache.put stores and Cache.get retrieves data" {
    const allocator = testing.allocator;

    const cache_path = try getTestCachePath(allocator);
    defer allocator.free(cache_path);
    defer fs.deleteTreeAbsolute(cache_path) catch {};

    const config = CacheConfig.init(cache_path);
    var test_cache = try Cache.init(allocator, config);
    defer test_cache.deinit();

    // Create test data
    const input = "test image bytes";
    const output_bytes = "optimized jpeg bytes";
    const key = Cache.computeKey(input, 1000, 0.01, .dssim, .jpeg);

    const metadata = CacheMetadata{
        .format = .jpeg,
        .file_size = @intCast(output_bytes.len),
        .quality = 85,
        .diff_score = 0.0012,
        .passed_constraints = true,
        .timestamp = std.time.timestamp(),
        .access_count = 0,
    };

    // Put into cache
    try test_cache.put(key, .jpeg, output_bytes, metadata);

    // Get from cache
    const cached = test_cache.get(key, .jpeg);
    try testing.expect(cached != null);

    if (cached) |result| {
        defer allocator.free(result.bytes);

        try testing.expectEqualStrings(output_bytes, result.bytes);
        try testing.expectEqual(ImageFormat.jpeg, result.metadata.format);
        try testing.expectEqual(@as(u32, @intCast(output_bytes.len)), result.metadata.file_size);
        try testing.expectEqual(@as(u8, 85), result.metadata.quality);
        try testing.expectApproxEqAbs(@as(f64, 0.0012), result.metadata.diff_score, 0.0001);
        try testing.expect(result.metadata.passed_constraints);
    }
}

test "Cache.get returns null on cache miss" {
    const allocator = testing.allocator;

    const cache_path = try getTestCachePath(allocator);
    defer allocator.free(cache_path);
    defer fs.deleteTreeAbsolute(cache_path) catch {};

    const config = CacheConfig.init(cache_path);
    var test_cache = try Cache.init(allocator, config);
    defer test_cache.deinit();

    // Try to get non-existent entry
    const input = "test image bytes";
    const key = Cache.computeKey(input, 1000, 0.01, .dssim, .jpeg);

    const cached = test_cache.get(key, .jpeg);
    try testing.expect(cached == null);
}

test "Cache.put and get with multiple formats" {
    const allocator = testing.allocator;

    const cache_path = try getTestCachePath(allocator);
    defer allocator.free(cache_path);
    defer fs.deleteTreeAbsolute(cache_path) catch {};

    const config = CacheConfig.init(cache_path);
    var test_cache = try Cache.init(allocator, config);
    defer test_cache.deinit();

    const input = "test image bytes";

    // Store JPEG version
    const jpeg_key = Cache.computeKey(input, 1000, 0.01, .dssim, .jpeg);
    const jpeg_meta = CacheMetadata{
        .format = .jpeg,
        .file_size = 1234,
        .quality = 85,
        .diff_score = 0.001,
        .passed_constraints = true,
        .timestamp = std.time.timestamp(),
        .access_count = 0,
    };
    try test_cache.put(jpeg_key, .jpeg, "jpeg bytes", jpeg_meta);

    // Store PNG version
    const png_key = Cache.computeKey(input, 1000, 0.01, .dssim, .png);
    const png_meta = CacheMetadata{
        .format = .png,
        .file_size = 5678,
        .quality = 6,
        .diff_score = 0.0,
        .passed_constraints = true,
        .timestamp = std.time.timestamp(),
        .access_count = 0,
    };
    try test_cache.put(png_key, .png, "png bytes", png_meta);

    // Retrieve both
    const jpeg_cached = test_cache.get(jpeg_key, .jpeg);
    const png_cached = test_cache.get(png_key, .png);

    try testing.expect(jpeg_cached != null);
    try testing.expect(png_cached != null);

    if (jpeg_cached) |result| {
        defer allocator.free(result.bytes);
        try testing.expectEqualStrings("jpeg bytes", result.bytes);
        try testing.expectEqual(ImageFormat.jpeg, result.metadata.format);
    }

    if (png_cached) |result| {
        defer allocator.free(result.bytes);
        try testing.expectEqualStrings("png bytes", result.bytes);
        try testing.expectEqual(ImageFormat.png, result.metadata.format);
    }
}

// ============================================================================
// Cache.clear Tests
// ============================================================================

test "Cache.clear removes all entries" {
    const allocator = testing.allocator;

    const cache_path = try getTestCachePath(allocator);
    defer allocator.free(cache_path);
    defer fs.deleteTreeAbsolute(cache_path) catch {};

    const config = CacheConfig.init(cache_path);
    var test_cache = try Cache.init(allocator, config);
    defer test_cache.deinit();

    // Add multiple entries
    const input1 = "image 1";
    const input2 = "image 2";
    const input3 = "image 3";

    const key1 = Cache.computeKey(input1, 1000, 0.01, .dssim, .jpeg);
    const key2 = Cache.computeKey(input2, 2000, 0.02, .ssimulacra2, .png);
    const key3 = Cache.computeKey(input3, 3000, 0.03, .none, .webp);

    const meta = CacheMetadata{
        .format = .jpeg,
        .file_size = 100,
        .quality = 85,
        .diff_score = 0.001,
        .passed_constraints = true,
        .timestamp = std.time.timestamp(),
        .access_count = 0,
    };

    try test_cache.put(key1, .jpeg, "data1", meta);
    try test_cache.put(key2, .png, "data2", meta);
    try test_cache.put(key3, .webp, "data3", meta);

    // Verify entries exist
    try testing.expect(test_cache.get(key1, .jpeg) != null);
    try testing.expect(test_cache.get(key2, .png) != null);
    try testing.expect(test_cache.get(key3, .webp) != null);

    // Clear cache
    try test_cache.clear();

    // Verify all entries are gone
    try testing.expect(test_cache.get(key1, .jpeg) == null);
    try testing.expect(test_cache.get(key2, .png) == null);
    try testing.expect(test_cache.get(key3, .webp) == null);
}

// ============================================================================
// Metadata Parsing Tests
// ============================================================================

test "parseMetadata and writeMetadata round-trip" {
    const metadata = CacheMetadata{
        .format = .webp,
        .file_size = 98765,
        .quality = 75,
        .diff_score = 0.123456,
        .passed_constraints = false,
        .timestamp = 1234567890,
        .access_count = 42,
    };

    // Write to buffer
    var write_buf: [512]u8 = undefined;
    const json_str = try std.fmt.bufPrint(&write_buf,
        \\{{"format":"{s}","file_size":{d},"quality":{d},"diff_score":{d:.6},"passed":{s},"timestamp":{d},"access_count":{d}}}
    , .{
        "webp",
        metadata.file_size,
        metadata.quality,
        metadata.diff_score,
        if (metadata.passed_constraints) "true" else "false",
        metadata.timestamp,
        metadata.access_count,
    });

    // Parse back
    const parsed = try cache_mod.parseMetadata(json_str);

    try testing.expectEqual(metadata.format, parsed.format);
    try testing.expectEqual(metadata.file_size, parsed.file_size);
    try testing.expectEqual(metadata.quality, parsed.quality);
    try testing.expectApproxEqAbs(metadata.diff_score, parsed.diff_score, 0.000001);
    try testing.expectEqual(metadata.passed_constraints, parsed.passed_constraints);
    try testing.expectEqual(metadata.timestamp, parsed.timestamp);
    try testing.expectEqual(metadata.access_count, parsed.access_count);
}

test "parseMetadata handles all formats" {
    const formats = [_]struct { name: []const u8, format: ImageFormat }{
        .{ .name = "jpeg", .format = .jpeg },
        .{ .name = "png", .format = .png },
        .{ .name = "webp", .format = .webp },
        .{ .name = "avif", .format = .avif },
    };

    for (formats) |f| {
        var buf: [512]u8 = undefined;
        const json_str = try std.fmt.bufPrint(&buf,
            \\{{"format":"{s}","file_size":100,"quality":85,"diff_score":0.001,"passed":true,"timestamp":123,"access_count":0}}
        , .{f.name});

        const parsed = try cache_mod.parseMetadata(json_str);
        try testing.expectEqual(f.format, parsed.format);
    }
}

// ============================================================================
// Edge Cases and Error Handling
// ============================================================================

test "Cache.put handles large files" {
    const allocator = testing.allocator;

    const cache_path = try getTestCachePath(allocator);
    defer allocator.free(cache_path);
    defer fs.deleteTreeAbsolute(cache_path) catch {};

    const config = CacheConfig.init(cache_path);
    var test_cache = try Cache.init(allocator, config);
    defer test_cache.deinit();

    // Create 1MB test data
    const large_data = try allocator.alloc(u8, 1024 * 1024);
    defer allocator.free(large_data);

    // Fill with test pattern
    for (large_data, 0..) |*byte, i| {
        byte.* = @intCast(i % 256);
    }

    const input = "large image";
    const key = Cache.computeKey(input, null, null, .none, .jpeg);

    const metadata = CacheMetadata{
        .format = .jpeg,
        .file_size = @intCast(large_data.len),
        .quality = 85,
        .diff_score = 0.0,
        .passed_constraints = true,
        .timestamp = std.time.timestamp(),
        .access_count = 0,
    };

    // Should not error
    try test_cache.put(key, .jpeg, large_data, metadata);

    // Should retrieve correctly
    const cached = test_cache.get(key, .jpeg);
    try testing.expect(cached != null);

    if (cached) |result| {
        defer allocator.free(result.bytes);
        try testing.expectEqual(large_data.len, result.bytes.len);
        try testing.expectEqualSlices(u8, large_data, result.bytes);
    }
}

test "Cache with disabled config returns null" {
    const allocator = testing.allocator;

    const cache_path = try getTestCachePath(allocator);
    defer allocator.free(cache_path);
    defer fs.deleteTreeAbsolute(cache_path) catch {};

    var config = CacheConfig.init(cache_path);
    config.enabled = false; // Disable caching

    var test_cache = try Cache.init(allocator, config);
    defer test_cache.deinit();

    const input = "test";
    const key = Cache.computeKey(input, null, null, .none, .jpeg);
    const metadata = CacheMetadata{
        .format = .jpeg,
        .file_size = 100,
        .quality = 85,
        .diff_score = 0.0,
        .passed_constraints = true,
        .timestamp = std.time.timestamp(),
        .access_count = 0,
    };

    // Put should be no-op when disabled
    try test_cache.put(key, .jpeg, "data", metadata);

    // Get should return null
    const cached = test_cache.get(key, .jpeg);
    try testing.expect(cached == null);
}
