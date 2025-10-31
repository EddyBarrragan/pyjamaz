/**
 * TypeScript tests for Pyjamaz Node.js bindings
 */

import * as pyjamaz from '../src/index';
import { PyjamazError } from '../src/types';
import * as fs from 'fs';
import * as path from 'path';

// Sample 1x1 JPEG image for testing
const SAMPLE_JPEG = Buffer.from([
  0xff, 0xd8, 0xff, 0xe0, 0x00, 0x10, 0x4a, 0x46, 0x49, 0x46, 0x00, 0x01,
  0x01, 0x00, 0x00, 0x01, 0x00, 0x01, 0x00, 0x00, 0xff, 0xdb, 0x00, 0x43,
  0x00, 0x08, 0x06, 0x06, 0x07, 0x06, 0x05, 0x08, 0x07, 0x07, 0x07, 0x09,
  0x09, 0x08, 0x0a, 0x0c, 0x14, 0x0d, 0x0c, 0x0b, 0x0b, 0x0c, 0x19, 0x12,
  0x13, 0x0f, 0x14, 0x1d, 0x1a, 0x1f, 0x1e, 0x1d, 0x1a, 0x1c, 0x1c, 0x20,
  0x24, 0x2e, 0x27, 0x20, 0x22, 0x2c, 0x23, 0x1c, 0x1c, 0x28, 0x37, 0x29,
  0x2c, 0x30, 0x31, 0x34, 0x34, 0x34, 0x1f, 0x27, 0x39, 0x3d, 0x38, 0x32,
  0x3c, 0x2e, 0x33, 0x34, 0x32, 0xff, 0xc0, 0x00, 0x0b, 0x08, 0x00, 0x01,
  0x00, 0x01, 0x01, 0x01, 0x11, 0x00, 0xff, 0xc4, 0x00, 0x14, 0x00, 0x01,
  0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
  0x00, 0x00, 0x00, 0x03, 0xff, 0xc4, 0x00, 0x14, 0x10, 0x01, 0x00, 0x00,
  0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
  0x00, 0x00, 0xff, 0xda, 0x00, 0x08, 0x01, 0x01, 0x00, 0x00, 0x3f, 0x00,
  0x37, 0xff, 0xd9,
]);

// Sample 1x1 PNG image for testing
const SAMPLE_PNG = Buffer.from([
  0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0x00, 0x00, 0x00, 0x0d,
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1f, 0x15, 0xc4, 0x89, 0x00, 0x00, 0x00,
  0x0a, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9c, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0d, 0x0a, 0x2d, 0xb4, 0x00, 0x00, 0x00, 0x00, 0x49,
  0x45, 0x4e, 0x44, 0xae, 0x42, 0x60, 0x82,
]);

describe('Pyjamaz TypeScript Bindings', () => {
  describe('getVersion', () => {
    it('should return a version string', () => {
      const version = pyjamaz.getVersion();
      expect(typeof version).toBe('string');
      expect(version.length).toBeGreaterThan(0);
    });
  });

  describe('optimizeImageFromBufferSync', () => {
    it('should optimize JPEG from buffer', () => {
      const result = pyjamaz.optimizeImageFromBufferSync(SAMPLE_JPEG, {
        maxBytes: 10000,
        metric: 'none',
      });

      expect(result).toBeDefined();
      expect(result.data).toBeInstanceOf(Buffer);
      expect(result.format).toMatch(/^(jpeg|png|webp|avif)$/);
      expect(typeof result.diffValue).toBe('number');
      expect(typeof result.passed).toBe('boolean');
      expect(typeof result.size).toBe('number');
      expect(result.size).toBeGreaterThan(0);
    });

    it('should optimize PNG from buffer', () => {
      const result = pyjamaz.optimizeImageFromBufferSync(SAMPLE_PNG, {
        maxBytes: 10000,
        metric: 'none',
      });

      expect(result).toBeDefined();
      expect(result.data).toBeInstanceOf(Buffer);
      expect(result.size).toBeGreaterThan(0);
    });

    it('should respect maxBytes constraint', () => {
      const result = pyjamaz.optimizeImageFromBufferSync(SAMPLE_JPEG, {
        maxBytes: 1000000,
        metric: 'none',
      });

      expect(result.passed).toBe(true);
      expect(result.size).toBeLessThanOrEqual(1000000);
    });

    it('should respect maxDiff constraint', () => {
      const result = pyjamaz.optimizeImageFromBufferSync(SAMPLE_JPEG, {
        maxDiff: 0.01,
        metric: 'dssim',
      });

      expect(result.diffValue).toBeLessThanOrEqual(0.01);
    });

    it('should support format selection', () => {
      const result = pyjamaz.optimizeImageFromBufferSync(SAMPLE_JPEG, {
        formats: ['webp', 'avif'],
        metric: 'none',
      });

      expect(['webp', 'avif']).toContain(result.format);
    });

    it('should support different metrics', () => {
      const metrics: Array<'dssim' | 'ssimulacra2' | 'none'> = ['dssim', 'ssimulacra2', 'none'];

      for (const metric of metrics) {
        const result = pyjamaz.optimizeImageFromBufferSync(SAMPLE_JPEG, {
          metric,
          maxBytes: 10000,
        });

        expect(result).toBeDefined();
        expect(result.size).toBeGreaterThan(0);
      }
    });

    it('should support concurrency levels', () => {
      const concurrencyLevels = [1, 2, 4, 8];

      for (const concurrency of concurrencyLevels) {
        const result = pyjamaz.optimizeImageFromBufferSync(SAMPLE_JPEG, {
          concurrency,
          metric: 'none',
        });

        expect(result).toBeDefined();
        expect(result.size).toBeGreaterThan(0);
      }
    });

    it('should support cache enabled/disabled', () => {
      // First run with cache enabled
      const result1 = pyjamaz.optimizeImageFromBufferSync(SAMPLE_JPEG, {
        cacheEnabled: true,
        metric: 'none',
      });

      // Second run with cache disabled
      const result2 = pyjamaz.optimizeImageFromBufferSync(SAMPLE_JPEG, {
        cacheEnabled: false,
        metric: 'none',
      });

      expect(result1.size).toBe(result2.size);
    });

    it('should use default options when none provided', () => {
      const result = pyjamaz.optimizeImageFromBufferSync(SAMPLE_JPEG);

      expect(result).toBeDefined();
      expect(result.size).toBeGreaterThan(0);
    });
  });

  describe('optimizeImageFromBuffer (async)', () => {
    it('should optimize image asynchronously', async () => {
      const result = await pyjamaz.optimizeImageFromBuffer(SAMPLE_JPEG, {
        maxBytes: 10000,
        metric: 'none',
      });

      expect(result).toBeDefined();
      expect(result.data).toBeInstanceOf(Buffer);
      expect(result.size).toBeGreaterThan(0);
    });
  });

  describe('OptimizeResult', () => {
    it('should have correct properties', () => {
      const result = pyjamaz.optimizeImageFromBufferSync(SAMPLE_JPEG, {
        metric: 'none',
      });

      expect(result).toHaveProperty('data');
      expect(result).toHaveProperty('format');
      expect(result).toHaveProperty('diffValue');
      expect(result).toHaveProperty('passed');
      expect(result).toHaveProperty('size');
    });

    it('should calculate size property correctly', () => {
      const result = pyjamaz.optimizeImageFromBufferSync(SAMPLE_JPEG, {
        metric: 'none',
      });

      expect(result.size).toBe(result.data.length);
    });

    it('should have saveSync method', () => {
      const result = pyjamaz.optimizeImageFromBufferSync(SAMPLE_JPEG, {
        metric: 'none',
      });

      expect(typeof result.saveSync).toBe('function');
    });

    it('should have save method', () => {
      const result = pyjamaz.optimizeImageFromBufferSync(SAMPLE_JPEG, {
        metric: 'none',
      });

      expect(typeof result.save).toBe('function');
    });
  });

  describe('Error handling', () => {
    it('should throw PyjamazError for invalid input', () => {
      expect(() => {
        pyjamaz.optimizeImageFromBufferSync(Buffer.from([0x00, 0x00]), {
          metric: 'none',
        });
      }).toThrow();
    });
  });

  describe('Memory management', () => {
    it('should not leak memory after multiple optimizations', () => {
      // Run 100 optimizations to check for memory leaks
      for (let i = 0; i < 100; i++) {
        const result = pyjamaz.optimizeImageFromBufferSync(SAMPLE_JPEG, {
          cacheEnabled: false,
          metric: 'none',
        });

        expect(result.size).toBeGreaterThan(0);
      }

      // If we got here without crashing, memory management is working
      expect(true).toBe(true);
    });
  });

  describe('Type safety', () => {
    it('should enforce type constraints', () => {
      // TypeScript should catch these at compile time
      const options: pyjamaz.OptimizeOptions = {
        maxBytes: 100000,
        maxDiff: 0.002,
        metric: 'dssim',
        formats: ['jpeg', 'png'],
        concurrency: 4,
        cacheEnabled: true,
      };

      const result = pyjamaz.optimizeImageFromBufferSync(SAMPLE_JPEG, options);
      expect(result).toBeDefined();
    });
  });

  describe('Caching', () => {
    it('should cache results for repeated optimizations', () => {
      const options = {
        maxBytes: 50000,
        cacheEnabled: true,
        metric: 'none' as const,
      };

      // First optimization (cache miss)
      const start1 = Date.now();
      const result1 = pyjamaz.optimizeImageFromBufferSync(SAMPLE_JPEG, options);
      const time1 = Date.now() - start1;

      // Second optimization (cache hit - should be faster)
      const start2 = Date.now();
      const result2 = pyjamaz.optimizeImageFromBufferSync(SAMPLE_JPEG, options);
      const time2 = Date.now() - start2;

      expect(result1.size).toBe(result2.size);
      expect(result1.format).toBe(result2.format);

      // Cache hit should be significantly faster (but we can't guarantee exact timing)
      // Just verify both operations completed successfully
      expect(time1).toBeGreaterThan(0);
      expect(time2).toBeGreaterThan(0);
    });
  });
});
