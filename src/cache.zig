//! Cache module - Content-addressed caching for optimized images
//!
//! Tiger Style: Safety-first caching with bounded operations
//!
//! Design:
//! - Content-addressed keys: Blake3(input_bytes + options)
//! - Cache location: ~/.cache/pyjamaz/ (or XDG_CACHE_HOME)
//! - Cache format: {hash}.{format} + {hash}.meta.json
//! - Eviction: LRU with configurable max size
//! - Expected speedup: 15-20x on cache hits

const std = @import("std");
const Allocator = std.mem.Allocator;
const fs = std.fs;
const Blake3 = std.crypto.hash.Blake3;

const types = @import("types.zig");
const ImageFormat = types.ImageFormat;
const MetricType = types.MetricType;

/// Maximum cache size in bytes (default: 1GB)
pub const DEFAULT_MAX_CACHE_SIZE: u64 = 1024 * 1024 * 1024;

/// Maximum cache entries (safety bound)
pub const MAX_CACHE_ENTRIES: u32 = 100_000;

/// Cache key (Blake3 hash)
pub const CacheKey = [32]u8;

/// Cached entry metadata
pub const CacheMetadata = struct {
    /// Format of cached output
    format: ImageFormat,

    /// Output file size in bytes (u64 supports files >4GB)
    file_size: u64,

    /// Quality level used
    quality: u8,

    /// Perceptual diff score
    diff_score: f64,

    /// Whether constraints were met
    passed_constraints: bool,

    /// Timestamp of cache entry (Unix time)
    timestamp: i64,

    /// Access count (for LRU)
    access_count: u64,
};

/// Cache configuration
pub const CacheConfig = struct {
    /// Cache directory path
    cache_dir: []const u8,

    /// Maximum cache size in bytes (0 = unlimited)
    max_size_bytes: u64,

    /// Enable cache (default: true)
    enabled: bool,

    pub fn init(cache_dir: []const u8) CacheConfig {
        return .{
            .cache_dir = cache_dir,
            .max_size_bytes = DEFAULT_MAX_CACHE_SIZE,
            .enabled = true,
        };
    }

    /// Get default cache directory (~/.cache/pyjamaz or XDG_CACHE_HOME/pyjamaz)
    pub fn getDefaultCacheDir(allocator: Allocator) ![]u8 {
        // Try XDG_CACHE_HOME first
        if (std.process.getEnvVarOwned(allocator, "XDG_CACHE_HOME")) |xdg_cache| {
            defer allocator.free(xdg_cache);
            return std.fmt.allocPrint(allocator, "{s}/pyjamaz", .{xdg_cache});
        } else |_| {
            // Fall back to ~/.cache/pyjamaz
            const home = std.process.getEnvVarOwned(allocator, "HOME") catch |err| {
                std.log.warn("Failed to get HOME directory: {}", .{err});
                return error.NoCacheDir;
            };
            defer allocator.free(home);
            return std.fmt.allocPrint(allocator, "{s}/.cache/pyjamaz", .{home});
        }
    }
};

/// Cached result (retrieved from cache)
pub const CachedResult = struct {
    /// Cached image bytes
    bytes: []u8,

    /// Metadata
    metadata: CacheMetadata,

    pub fn deinit(self: *CachedResult, allocator: Allocator) void {
        allocator.free(self.bytes);
    }
};

/// Cache manager
pub const Cache = struct {
    config: CacheConfig,
    allocator: Allocator,
    cache_dir: std.fs.Dir,

    /// Initialize cache (creates directory if needed)
    ///
    /// Tiger Style: Bounded initialization, graceful fallback
    pub fn init(allocator: Allocator, config: CacheConfig) !Cache {
        std.debug.assert(config.cache_dir.len > 0);
        std.debug.assert(config.max_size_bytes >= 0);

        // Create cache directory if it doesn't exist
        fs.cwd().makePath(config.cache_dir) catch |err| {
            std.log.warn("Failed to create cache directory {s}: {}", .{config.cache_dir, err});
            return err;
        };

        const cache_dir = try fs.cwd().openDir(config.cache_dir, .{});

        const cache = Cache{
            .config = config,
            .allocator = allocator,
            .cache_dir = cache_dir,
        };

        // Post-condition: cache is initialized
        std.debug.assert(cache.config.cache_dir.len > 0);

        return cache;
    }

    pub fn deinit(self: *Cache) void {
        self.cache_dir.close();
    }

    /// Compute cache key from input bytes and options
    ///
    /// Tiger Style: Deterministic hashing, bounded input
    pub fn computeKey(
        input_bytes: []const u8,
        max_bytes: ?u32,
        max_diff: ?f64,
        metric_type: MetricType,
        format: ImageFormat,
    ) CacheKey {
        std.debug.assert(input_bytes.len > 0);

        var hasher = Blake3.init(.{});

        // Hash input bytes
        hasher.update(input_bytes);

        // Hash options (deterministic)
        const max_bytes_value = max_bytes orelse 0;
        hasher.update(std.mem.asBytes(&max_bytes_value));

        const max_diff_value = max_diff orelse 0.0;
        hasher.update(std.mem.asBytes(&max_diff_value));

        const metric_tag = @intFromEnum(metric_type);
        hasher.update(std.mem.asBytes(&metric_tag));

        const format_tag = @intFromEnum(format);
        hasher.update(std.mem.asBytes(&format_tag));

        var key: CacheKey = undefined;
        hasher.final(&key);

        return key;
    }

    /// Get cached result if exists
    ///
    /// Tiger Style: Bounded file I/O, graceful miss
    pub fn get(
        self: *Cache,
        key: CacheKey,
        format: ImageFormat,
    ) ?CachedResult {
        if (!self.config.enabled) return null;

        // Build cache file path
        const key_hex = std.fmt.bytesToHex(key, .lower);
        const format_ext = format.fileExtension()[1..]; // Remove leading '.'

        // Try to read cached bytes
        const cached_path = std.fmt.allocPrint(
            self.allocator,
            "{s}.{s}",
            .{&key_hex, format_ext}
        ) catch return null;
        defer self.allocator.free(cached_path);

        const cached_bytes = self.cache_dir.readFileAlloc(
            self.allocator,
            cached_path,
            100 * 1024 * 1024, // Max 100MB per cached file
        ) catch {
            // Cache miss
            return null;
        };
        errdefer self.allocator.free(cached_bytes);

        // Try to read metadata
        const meta_path = std.fmt.allocPrint(
            self.allocator,
            "{s}.meta.json",
            .{&key_hex}
        ) catch {
            self.allocator.free(cached_bytes);
            return null;
        };
        defer self.allocator.free(meta_path);

        const meta_bytes = self.cache_dir.readFileAlloc(
            self.allocator,
            meta_path,
            1024, // Max 1KB metadata
        ) catch {
            self.allocator.free(cached_bytes);
            return null;
        };
        defer self.allocator.free(meta_bytes);

        const metadata = parseMetadata(meta_bytes) catch {
            self.allocator.free(cached_bytes);
            return null;
        };

        // Update access timestamp and count
        self.touchEntry(key) catch {};

        std.log.info("Cache HIT: key={s}, format={s}, size={d}", .{
            &key_hex,
            format_ext,
            cached_bytes.len,
        });

        return CachedResult{
            .bytes = cached_bytes,
            .metadata = metadata,
        };
    }

    /// Put result into cache
    ///
    /// Tiger Style: Bounded writes, eviction on overflow
    pub fn put(
        self: *Cache,
        key: CacheKey,
        format: ImageFormat,
        bytes: []const u8,
        metadata: CacheMetadata,
    ) !void {
        if (!self.config.enabled) return;

        std.debug.assert(bytes.len > 0);
        std.debug.assert(bytes.len < 100 * 1024 * 1024); // Max 100MB

        // Check if cache needs eviction
        try self.maybeEvict(bytes.len);

        const key_hex = std.fmt.bytesToHex(key, .lower);
        const format_ext = format.fileExtension()[1..]; // Remove leading '.'

        // Write cached bytes
        const cached_path = try std.fmt.allocPrint(
            self.allocator,
            "{s}.{s}",
            .{&key_hex, format_ext}
        );
        defer self.allocator.free(cached_path);

        const file = try self.cache_dir.createFile(cached_path, .{});
        defer file.close();
        try file.writeAll(bytes);

        // Write metadata
        const meta_path = try std.fmt.allocPrint(
            self.allocator,
            "{s}.meta.json",
            .{&key_hex}
        );
        defer self.allocator.free(meta_path);

        // Format metadata to string
        var meta_buf: [512]u8 = undefined;
        const meta_json = try std.fmt.bufPrint(&meta_buf,
            \\{{"format":"{s}","file_size":{d},"quality":{d},"diff_score":{d:.6},"passed":{s},"timestamp":{d},"access_count":{d}}}
        , .{
            switch (metadata.format) {
                .jpeg => "jpeg",
                .png => "png",
                .webp => "webp",
                .avif => "avif",
                .unknown => "unknown",
            },
            metadata.file_size,
            metadata.quality,
            metadata.diff_score,
            if (metadata.passed_constraints) "true" else "false",
            metadata.timestamp,
            metadata.access_count,
        });

        const meta_file = try self.cache_dir.createFile(meta_path, .{});
        defer meta_file.close();
        try meta_file.writeAll(meta_json);

        std.log.debug("Cache PUT: key={s}, format={s}, size={d}", .{
            &key_hex,
            format_ext,
            bytes.len,
        });
    }

    /// Touch cache entry (update access time and count)
    fn touchEntry(self: *Cache, key: CacheKey) !void {
        const key_hex = std.fmt.bytesToHex(key, .lower);
        const meta_path = try std.fmt.allocPrint(
            self.allocator,
            "{s}.meta.json",
            .{&key_hex}
        );
        defer self.allocator.free(meta_path);

        // Read current metadata
        const meta_bytes = try self.cache_dir.readFileAlloc(
            self.allocator,
            meta_path,
            1024,
        );
        defer self.allocator.free(meta_bytes);

        var metadata = try parseMetadata(meta_bytes);

        // Update access info
        metadata.timestamp = std.time.timestamp();
        metadata.access_count += 1;

        // Format metadata to string
        var meta_buf: [512]u8 = undefined;
        const meta_json = try std.fmt.bufPrint(&meta_buf,
            \\{{"format":"{s}","file_size":{d},"quality":{d},"diff_score":{d:.6},"passed":{s},"timestamp":{d},"access_count":{d}}}
        , .{
            switch (metadata.format) {
                .jpeg => "jpeg",
                .png => "png",
                .webp => "webp",
                .avif => "avif",
                .unknown => "unknown",
            },
            metadata.file_size,
            metadata.quality,
            metadata.diff_score,
            if (metadata.passed_constraints) "true" else "false",
            metadata.timestamp,
            metadata.access_count,
        });

        // Write back
        const meta_file = try self.cache_dir.createFile(meta_path, .{});
        defer meta_file.close();
        try meta_file.writeAll(meta_json);
    }

    /// Evict old entries if cache size exceeds limit
    ///
    /// Tiger Style: Bounded eviction, LRU policy
    fn maybeEvict(self: *Cache, incoming_size: usize) !void {
        if (self.config.max_size_bytes == 0) return; // Unlimited

        const current_size = try self.getCacheSize();
        const required_space = current_size + incoming_size;

        if (required_space <= self.config.max_size_bytes) {
            return; // No eviction needed
        }

        std.log.info("Cache eviction triggered: current={d}, incoming={d}, limit={d}", .{
            current_size,
            incoming_size,
            self.config.max_size_bytes,
        });

        // Get all cache entries sorted by LRU
        var entries = try self.listEntriesByLRU();
        defer {
            for (entries.items) |entry| self.allocator.free(entry.filename);
            entries.deinit(self.allocator);
        }

        // Evict oldest entries until we have space
        var freed: u64 = 0;
        var evicted_count: u32 = 0;
        const target_freed = required_space - self.config.max_size_bytes;

        // Tiger Style: Bounded loop with correct invariant
        const MAX_EVICTIONS: u32 = 1000;
        for (entries.items) |entry| {
            if (freed >= target_freed or evicted_count >= MAX_EVICTIONS) break;
            std.debug.assert(evicted_count < MAX_EVICTIONS); // Loop invariant on eviction count

            self.cache_dir.deleteFile(entry.filename) catch |err| {
                std.log.warn("Failed to delete cache entry {s}: {}", .{entry.filename, err});
                continue;
            };

            freed += entry.size;
            evicted_count += 1;
        }

        std.log.info("Cache evicted {d} entries, freed {d} bytes", .{evicted_count, freed});

        // Post-loop assertion
        std.debug.assert(evicted_count <= MAX_EVICTIONS);
    }

    /// Get total cache size in bytes
    fn getCacheSize(self: *Cache) !u64 {
        var total: u64 = 0;
        var iter = self.cache_dir.iterate();

        // Tiger Style: Bounded iteration
        var count: u32 = 0;
        while (try iter.next()) |entry| : (count += 1) {
            std.debug.assert(count < MAX_CACHE_ENTRIES);

            if (entry.kind != .file) continue;

            const stat = self.cache_dir.statFile(entry.name) catch continue;
            total += stat.size;
        }

        std.debug.assert(count <= MAX_CACHE_ENTRIES);
        return total;
    }

    /// List cache entries sorted by LRU (oldest first)
    fn listEntriesByLRU(self: *Cache) !std.ArrayList(CacheEntry) {
        var entries = std.ArrayList(CacheEntry){};
        errdefer {
            for (entries.items) |entry| self.allocator.free(entry.filename);
            entries.deinit(self.allocator);
        }

        var iter = self.cache_dir.iterate();

        // Tiger Style: Bounded iteration
        var count: u32 = 0;
        while (try iter.next()) |entry| : (count += 1) {
            std.debug.assert(count < MAX_CACHE_ENTRIES);

            if (entry.kind != .file) continue;
            if (std.mem.endsWith(u8, entry.name, ".meta.json")) continue;

            const stat = try self.cache_dir.statFile(entry.name);
            const filename = try self.allocator.dupe(u8, entry.name);

            try entries.append(self.allocator, .{
                .filename = filename,
                .size = stat.size,
                .mtime = stat.mtime,
            });
        }

        // Sort by modification time (oldest first)
        std.mem.sort(CacheEntry, entries.items, {}, cacheEntryLessThan);

        std.debug.assert(count <= MAX_CACHE_ENTRIES);
        return entries;
    }

    /// Clear all cache entries
    pub fn clear(self: *Cache) !void {
        var iter = self.cache_dir.iterate();

        // Tiger Style: Bounded deletion
        var count: u32 = 0;
        const MAX_DELETIONS: u32 = 100_000;

        while (try iter.next()) |entry| : (count += 1) {
            std.debug.assert(count < MAX_DELETIONS);

            if (entry.kind != .file) continue;

            self.cache_dir.deleteFile(entry.name) catch |err| {
                std.log.warn("Failed to delete {s}: {}", .{entry.name, err});
            };
        }

        std.log.info("Cache cleared: {d} entries deleted", .{count});
        std.debug.assert(count <= MAX_DELETIONS);
    }
};

/// Cache entry for LRU sorting
const CacheEntry = struct {
    filename: []const u8,
    size: u64,
    mtime: i128,
};

fn cacheEntryLessThan(_: void, a: CacheEntry, b: CacheEntry) bool {
    return a.mtime < b.mtime;
}

/// Parse metadata from JSON (public for testing)
pub fn parseMetadata(json_bytes: []const u8) !CacheMetadata {
    // Simple manual JSON parsing for MVP (Tiger Style: avoid external deps)
    // Format: {"format":"jpeg","file_size":1234,"quality":85,"diff_score":0.001,"passed":true,"timestamp":1234567890,"access_count":5}

    // For MVP, use a simple parser
    // In production, use std.json when Zig 0.15 API stabilizes

    var metadata: CacheMetadata = undefined;

    // Parse format
    if (std.mem.indexOf(u8, json_bytes, "\"format\":\"")) |idx| {
        const start = idx + 10;
        // Tiger Style: Validate bounds before accessing
        if (start >= json_bytes.len) return error.InvalidMetadata;
        const end = std.mem.indexOfPos(u8, json_bytes, start, "\"") orelse return error.InvalidMetadata;
        // Validate end > start
        if (end <= start) return error.InvalidMetadata;
        const format_str = json_bytes[start..end];
        metadata.format = ImageFormat.fromString(format_str) orelse return error.InvalidMetadata;
    } else return error.InvalidMetadata;

    // Parse file_size
    if (std.mem.indexOf(u8, json_bytes, "\"file_size\":")) |idx| {
        const start = idx + 12;
        // Tiger Style: Validate bounds before accessing
        if (start >= json_bytes.len) return error.InvalidMetadata;
        const end = std.mem.indexOfAnyPos(u8, json_bytes, start, ",}") orelse return error.InvalidMetadata;
        // Validate end > start
        if (end <= start) return error.InvalidMetadata;
        metadata.file_size = try std.fmt.parseInt(u32, json_bytes[start..end], 10);
    } else return error.InvalidMetadata;

    // Parse quality
    if (std.mem.indexOf(u8, json_bytes, "\"quality\":")) |idx| {
        const start = idx + 10;
        // Tiger Style: Validate bounds before accessing
        if (start >= json_bytes.len) return error.InvalidMetadata;
        const end = std.mem.indexOfAnyPos(u8, json_bytes, start, ",}") orelse return error.InvalidMetadata;
        // Validate end > start
        if (end <= start) return error.InvalidMetadata;
        metadata.quality = try std.fmt.parseInt(u8, json_bytes[start..end], 10);
    } else return error.InvalidMetadata;

    // Parse diff_score
    if (std.mem.indexOf(u8, json_bytes, "\"diff_score\":")) |idx| {
        const start = idx + 13;
        // Tiger Style: Validate bounds before accessing
        if (start >= json_bytes.len) return error.InvalidMetadata;
        const end = std.mem.indexOfAnyPos(u8, json_bytes, start, ",}") orelse return error.InvalidMetadata;
        // Validate end > start
        if (end <= start) return error.InvalidMetadata;
        metadata.diff_score = try std.fmt.parseFloat(f64, json_bytes[start..end]);
    } else return error.InvalidMetadata;

    // Parse passed_constraints
    if (std.mem.indexOf(u8, json_bytes, "\"passed\":")) |idx| {
        const start = idx + 9;
        // Tiger Style: Validate bounds before accessing
        if (start >= json_bytes.len) return error.InvalidMetadata;
        const end = std.mem.indexOfAnyPos(u8, json_bytes, start, ",}") orelse return error.InvalidMetadata;
        // Validate end > start
        if (end <= start) return error.InvalidMetadata;
        const passed_str = json_bytes[start..end];
        metadata.passed_constraints = std.mem.eql(u8, passed_str, "true");
    } else return error.InvalidMetadata;

    // Parse timestamp
    if (std.mem.indexOf(u8, json_bytes, "\"timestamp\":")) |idx| {
        const start = idx + 12;
        // Tiger Style: Validate bounds before accessing
        if (start >= json_bytes.len) return error.InvalidMetadata;
        const end = std.mem.indexOfAnyPos(u8, json_bytes, start, ",}") orelse return error.InvalidMetadata;
        // Validate end > start
        if (end <= start) return error.InvalidMetadata;
        metadata.timestamp = try std.fmt.parseInt(i64, json_bytes[start..end], 10);
    } else return error.InvalidMetadata;

    // Parse access_count
    if (std.mem.indexOf(u8, json_bytes, "\"access_count\":")) |idx| {
        const start = idx + 15;
        // Tiger Style: Validate bounds before accessing
        if (start >= json_bytes.len) return error.InvalidMetadata;
        const end = std.mem.indexOfAnyPos(u8, json_bytes, start, ",}") orelse return error.InvalidMetadata;
        // Validate end > start
        if (end <= start) return error.InvalidMetadata;
        metadata.access_count = try std.fmt.parseInt(u64, json_bytes[start..end], 10);
    } else return error.InvalidMetadata;

    return metadata;
}

/// Write metadata to JSON
fn writeMetadata(writer: anytype, metadata: CacheMetadata) !void {
    // Use lowercase format name for JSON (compatible with fromString())
    const format_name = switch (metadata.format) {
        .jpeg => "jpeg",
        .png => "png",
        .webp => "webp",
        .avif => "avif",
        .unknown => "unknown",
    };

    try writer.print(
        \\{{"format":"{s}","file_size":{d},"quality":{d},"diff_score":{d:.6},"passed":{s},"timestamp":{d},"access_count":{d}}}
    , .{
        format_name,
        metadata.file_size,
        metadata.quality,
        metadata.diff_score,
        if (metadata.passed_constraints) "true" else "false",
        metadata.timestamp,
        metadata.access_count,
    });
}

// ============================================================================
// Unit Tests
// ============================================================================

const testing = std.testing;

test "CacheConfig.init creates default config" {
    const config = CacheConfig.init("/tmp/cache");
    try testing.expectEqualStrings("/tmp/cache", config.cache_dir);
    try testing.expectEqual(DEFAULT_MAX_CACHE_SIZE, config.max_size_bytes);
    try testing.expect(config.enabled);
}

test "Cache.computeKey is deterministic" {
    const input1 = "test image data";
    const input2 = "test image data";
    const input3 = "different data";

    const key1 = Cache.computeKey(input1, 1000, 0.01, .dssim, .jpeg);
    const key2 = Cache.computeKey(input2, 1000, 0.01, .dssim, .jpeg);
    const key3 = Cache.computeKey(input3, 1000, 0.01, .dssim, .jpeg);
    const key4 = Cache.computeKey(input1, 2000, 0.01, .dssim, .jpeg); // Different max_bytes

    // Same input -> same key
    try testing.expectEqual(key1, key2);

    // Different input -> different key
    try testing.expect(!std.mem.eql(u8, &key1, &key3));

    // Different options -> different key
    try testing.expect(!std.mem.eql(u8, &key1, &key4));
}

test "parseMetadata and writeMetadata round-trip" {
    const metadata = CacheMetadata{
        .format = .jpeg,
        .file_size = 12345,
        .quality = 85,
        .diff_score = 0.001234,
        .passed_constraints = true,
        .timestamp = 1234567890,
        .access_count = 42,
    };

    var buffer: [512]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buffer);
    try writeMetadata(fbs.writer(), metadata);

    const json_bytes = fbs.getWritten();
    const parsed = try parseMetadata(json_bytes);

    try testing.expectEqual(metadata.format, parsed.format);
    try testing.expectEqual(metadata.file_size, parsed.file_size);
    try testing.expectEqual(metadata.quality, parsed.quality);
    try testing.expectApproxEqAbs(metadata.diff_score, parsed.diff_score, 0.000001);
    try testing.expectEqual(metadata.passed_constraints, parsed.passed_constraints);
    try testing.expectEqual(metadata.timestamp, parsed.timestamp);
    try testing.expectEqual(metadata.access_count, parsed.access_count);
}

test "Cache: init and deinit" {
    // Simple approach: Use hardcoded /tmp path (no random dirs in project root)
    const cache_path = "/tmp/pyjamaz-cache-test";

    const config = CacheConfig.init(cache_path);
    var cache = try Cache.init(testing.allocator, config);
    defer cache.deinit();

    // Verify cache directory was created
    var dir = try fs.openDirAbsolute(cache_path, .{});
    dir.close();

    // Cleanup
    try fs.deleteDirAbsolute(cache_path);
}
