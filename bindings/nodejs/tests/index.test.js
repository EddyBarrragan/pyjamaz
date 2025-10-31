/**
 * JavaScript tests for Pyjamaz Node.js bindings
 *
 * These tests verify that the bindings work correctly from plain JavaScript
 * without TypeScript type checking.
 */

const pyjamaz = require('../dist/index');

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

describe('Pyjamaz JavaScript Bindings', () => {
  describe('getVersion (JS)', () => {
    it('should return version string', () => {
      const version = pyjamaz.getVersion();
      expect(typeof version).toBe('string');
      expect(version.length).toBeGreaterThan(0);
    });
  });

  describe('optimizeImageFromBufferSync (JS)', () => {
    it('should optimize image with basic options', () => {
      const result = pyjamaz.optimizeImageFromBufferSync(SAMPLE_JPEG, {
        maxBytes: 100000,
        metric: 'none',
      });

      expect(result).toBeDefined();
      expect(Buffer.isBuffer(result.data)).toBe(true);
      expect(result.size).toBeGreaterThan(0);
      expect(typeof result.format).toBe('string');
      expect(typeof result.diffValue).toBe('number');
      expect(typeof result.passed).toBe('boolean');
    });

    it('should work with minimal options', () => {
      const result = pyjamaz.optimizeImageFromBufferSync(SAMPLE_JPEG, {
        metric: 'none',
      });

      expect(result).toBeDefined();
      expect(result.size).toBeGreaterThan(0);
    });

    it('should work without any options', () => {
      const result = pyjamaz.optimizeImageFromBufferSync(SAMPLE_JPEG);

      expect(result).toBeDefined();
      expect(result.size).toBeGreaterThan(0);
    });

    it('should support format selection in JS', () => {
      const result = pyjamaz.optimizeImageFromBufferSync(SAMPLE_JPEG, {
        formats: ['jpeg', 'webp'],
        metric: 'none',
      });

      expect(['jpeg', 'webp']).toContain(result.format);
    });

    it('should support different concurrency levels', () => {
      const result1 = pyjamaz.optimizeImageFromBufferSync(SAMPLE_JPEG, {
        concurrency: 1,
        metric: 'none',
      });

      const result2 = pyjamaz.optimizeImageFromBufferSync(SAMPLE_JPEG, {
        concurrency: 4,
        metric: 'none',
      });

      expect(result1.size).toBeGreaterThan(0);
      expect(result2.size).toBeGreaterThan(0);
    });

    it('should respect cache settings', () => {
      // Cache enabled
      const result1 = pyjamaz.optimizeImageFromBufferSync(SAMPLE_JPEG, {
        cacheEnabled: true,
        metric: 'none',
      });

      // Cache disabled
      const result2 = pyjamaz.optimizeImageFromBufferSync(SAMPLE_JPEG, {
        cacheEnabled: false,
        metric: 'none',
      });

      expect(result1.size).toBe(result2.size);
    });
  });

  describe('optimizeImageFromBuffer async (JS)', () => {
    it('should optimize image asynchronously', async () => {
      const result = await pyjamaz.optimizeImageFromBuffer(SAMPLE_JPEG, {
        maxBytes: 50000,
        metric: 'none',
      });

      expect(result).toBeDefined();
      expect(Buffer.isBuffer(result.data)).toBe(true);
      expect(result.size).toBeGreaterThan(0);
    });

    it('should work with promises', () => {
      return pyjamaz.optimizeImageFromBuffer(SAMPLE_JPEG, {
        metric: 'none',
      }).then((result) => {
        expect(result).toBeDefined();
        expect(result.size).toBeGreaterThan(0);
      });
    });
  });

  describe('Result methods (JS)', () => {
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

    it('should have size property', () => {
      const result = pyjamaz.optimizeImageFromBufferSync(SAMPLE_JPEG, {
        metric: 'none',
      });

      expect(typeof result.size).toBe('number');
      expect(result.size).toBe(result.data.length);
    });
  });

  describe('Error handling (JS)', () => {
    it('should throw error for invalid input', () => {
      expect(() => {
        pyjamaz.optimizeImageFromBufferSync(Buffer.from([0x00, 0x00]), {
          metric: 'none',
        });
      }).toThrow();
    });
  });

  describe('Multiple formats (JS)', () => {
    it('should try multiple formats', () => {
      const formats = ['jpeg', 'png', 'webp', 'avif'];

      const result = pyjamaz.optimizeImageFromBufferSync(SAMPLE_JPEG, {
        formats: formats,
        metric: 'none',
      });

      expect(formats).toContain(result.format);
    });
  });

  describe('Metrics (JS)', () => {
    it('should support dssim metric', () => {
      const result = pyjamaz.optimizeImageFromBufferSync(SAMPLE_JPEG, {
        metric: 'dssim',
        maxBytes: 100000,
      });

      expect(result).toBeDefined();
      expect(typeof result.diffValue).toBe('number');
    });

    it('should support ssimulacra2 metric', () => {
      const result = pyjamaz.optimizeImageFromBufferSync(SAMPLE_JPEG, {
        metric: 'ssimulacra2',
        maxBytes: 100000,
      });

      expect(result).toBeDefined();
      expect(typeof result.diffValue).toBe('number');
    });

    it('should support none metric', () => {
      const result = pyjamaz.optimizeImageFromBufferSync(SAMPLE_JPEG, {
        metric: 'none',
        maxBytes: 100000,
      });

      expect(result).toBeDefined();
    });
  });

  describe('Constraints (JS)', () => {
    it('should respect maxBytes', () => {
      const maxBytes = 1000000;
      const result = pyjamaz.optimizeImageFromBufferSync(SAMPLE_JPEG, {
        maxBytes: maxBytes,
        metric: 'none',
      });

      expect(result.size).toBeLessThanOrEqual(maxBytes);
    });

    it('should respect maxDiff', () => {
      const maxDiff = 0.01;
      const result = pyjamaz.optimizeImageFromBufferSync(SAMPLE_JPEG, {
        maxDiff: maxDiff,
        metric: 'dssim',
      });

      expect(result.diffValue).toBeLessThanOrEqual(maxDiff);
    });

    it('should handle both constraints', () => {
      const result = pyjamaz.optimizeImageFromBufferSync(SAMPLE_JPEG, {
        maxBytes: 50000,
        maxDiff: 0.01,
        metric: 'dssim',
      });

      expect(result.size).toBeLessThanOrEqual(50000);
      expect(result.diffValue).toBeLessThanOrEqual(0.01);
    });
  });
});
