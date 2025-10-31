# Pyjamaz Node.js API Reference

**Complete API documentation for the Pyjamaz Node.js bindings (TypeScript-first)**

Version: 1.0.0
Last Updated: 2025-10-31

---

## Table of Contents

- [Installation](#installation)
- [Quick Start](#quick-start)
- [API Reference](#api-reference)
  - [Functions](#functions)
  - [Types](#types)
  - [Interfaces](#interfaces)
- [Usage Examples](#usage-examples)
  - [Basic Optimization](#basic-optimization)
  - [Quality Constraints](#quality-constraints)
  - [Format Selection](#format-selection)
  - [Batch Processing](#batch-processing)
  - [Caching](#caching)
- [Integration Examples](#integration-examples)
  - [Express Server](#express-server)
  - [Fastify Server](#fastify-server)
  - [CLI Tool](#cli-tool)
- [Performance Tips](#performance-tips)
- [Troubleshooting](#troubleshooting)

---

## Installation

### From Source (Development)

```bash
# Build the Pyjamaz shared library
cd /path/to/pyjamaz
zig build

# Install Node.js bindings
cd bindings/nodejs
npm install
npm run build

# Run tests
npm test

# Run examples
npm run build && node dist/examples/basic.js
```

### From npm (Coming Soon)

```bash
npm install @pyjamaz/nodejs
```

---

## Quick Start

### TypeScript

```typescript
import * as pyjamaz from '@pyjamaz/nodejs';

// Optimize with size constraint
const result = await pyjamaz.optimizeImage('input.jpg', {
  maxBytes: 100_000,
});

if (result.passed) {
  await result.save('output.jpg');
  console.log(`Optimized to ${result.size} bytes`);
}
```

### JavaScript

```javascript
const pyjamaz = require('@pyjamaz/nodejs');

// Optimize with size constraint
const result = await pyjamaz.optimizeImage('input.jpg', {
  maxBytes: 100000,
});

if (result.passed) {
  await result.save('output.jpg');
  console.log(`Optimized to ${result.size} bytes`);
}
```

---

## API Reference

### Functions

#### `getVersion()`

Get the Pyjamaz library version.

```typescript
function getVersion(): string
```

**Returns:** Version string (e.g., `"1.0.0"`)

**Example:**
```typescript
const version = pyjamaz.getVersion();
console.log(`Pyjamaz version: ${version}`);
```

---

#### `optimizeImage()`

Optimize an image from file path (async).

```typescript
async function optimizeImage(
  inputPath: string,
  options?: OptimizeOptions
): Promise<OptimizeResult>
```

**Parameters:**
- `inputPath`: Path to input image file
- `options`: Optimization options (optional)

**Returns:** Promise resolving to `OptimizeResult`

**Throws:** `PyjamazError` if optimization fails

**Example:**
```typescript
const result = await pyjamaz.optimizeImage('input.jpg', {
  maxBytes: 100_000,
  metric: 'dssim',
});
```

---

#### `optimizeImageSync()`

Optimize an image from file path (sync).

```typescript
function optimizeImageSync(
  inputPath: string,
  options?: OptimizeOptions
): OptimizeResult
```

**Parameters:**
- `inputPath`: Path to input image file
- `options`: Optimization options (optional)

**Returns:** `OptimizeResult`

**Throws:** `PyjamazError` if optimization fails

**Example:**
```typescript
const result = pyjamaz.optimizeImageSync('input.jpg', {
  maxBytes: 100_000,
});
```

---

#### `optimizeImageFromBuffer()`

Optimize an image from Buffer (async).

```typescript
async function optimizeImageFromBuffer(
  buffer: Buffer,
  options?: OptimizeOptions
): Promise<OptimizeResult>
```

**Parameters:**
- `buffer`: Input image data as Buffer
- `options`: Optimization options (optional)

**Returns:** Promise resolving to `OptimizeResult`

**Throws:** `PyjamazError` if optimization fails

**Example:**
```typescript
const inputData = await fs.promises.readFile('input.jpg');
const result = await pyjamaz.optimizeImageFromBuffer(inputData, {
  maxBytes: 100_000,
});
```

---

#### `optimizeImageFromBufferSync()`

Optimize an image from Buffer (sync).

```typescript
function optimizeImageFromBufferSync(
  buffer: Buffer,
  options?: OptimizeOptions
): OptimizeResult
```

**Parameters:**
- `buffer`: Input image data as Buffer
- `options`: Optimization options (optional)

**Returns:** `OptimizeResult`

**Throws:** `PyjamazError` if optimization fails

**Example:**
```typescript
const inputData = fs.readFileSync('input.jpg');
const result = pyjamaz.optimizeImageFromBufferSync(inputData, {
  maxBytes: 50_000,
});
```

---

### Types

#### `ImageFormat`

Supported image formats.

```typescript
type ImageFormat = 'jpeg' | 'png' | 'webp' | 'avif';
```

---

#### `MetricType`

Perceptual quality metrics.

```typescript
type MetricType = 'dssim' | 'ssimulacra2' | 'none';
```

- `'dssim'`: Structural dissimilarity (default)
- `'ssimulacra2'`: Advanced perceptual metric
- `'none'`: Fast mode without quality checks

---

### Interfaces

#### `OptimizeOptions`

Options for image optimization.

```typescript
interface OptimizeOptions {
  maxBytes?: number;
  maxDiff?: number;
  metric?: MetricType;
  formats?: ImageFormat[];
  concurrency?: number;
  cacheEnabled?: boolean;
  cacheDir?: string;
  cacheMaxSize?: number;
}
```

**Properties:**

| Property | Type | Default | Description |
|----------|------|---------|-------------|
| `maxBytes` | `number \| undefined` | `undefined` | Maximum output size in bytes (undefined = no limit) |
| `maxDiff` | `number \| undefined` | `undefined` | Maximum perceptual difference (undefined = no limit) |
| `metric` | `MetricType` | `'dssim'` | Perceptual metric to use |
| `formats` | `ImageFormat[]` | `['jpeg', 'png', 'webp', 'avif']` | Formats to try |
| `concurrency` | `number` | `4` | Parallel encoding threads (1-8) |
| `cacheEnabled` | `boolean` | `true` | Enable caching for speedup |
| `cacheDir` | `string \| undefined` | `~/.cache/pyjamaz` | Custom cache directory |
| `cacheMaxSize` | `number` | `1073741824` | Max cache size in bytes (1GB) |

---

#### `OptimizeResult`

Result of image optimization.

```typescript
interface OptimizeResult {
  data: Buffer;
  format: ImageFormat;
  diffValue: number;
  passed: boolean;
  errorMessage?: string;
  readonly size: number;
  save(outputPath: string): Promise<void>;
  saveSync(outputPath: string): void;
}
```

**Properties:**

| Property | Type | Description |
|----------|------|-------------|
| `data` | `Buffer` | Optimized image data |
| `format` | `ImageFormat` | Selected output format |
| `diffValue` | `number` | Perceptual difference score |
| `passed` | `boolean` | Whether optimization met all constraints |
| `errorMessage` | `string \| undefined` | Error message if failed |
| `size` | `number` | Size of optimized image in bytes (readonly) |

**Methods:**

- `save(outputPath: string): Promise<void>` - Save to file (async)
- `saveSync(outputPath: string): void` - Save to file (sync)

---

## Usage Examples

### Basic Optimization

**Size constraint:**
```typescript
const result = await pyjamaz.optimizeImage('input.jpg', {
  maxBytes: 100_000,
});

if (result.passed) {
  await result.save('output.jpg');
  console.log(`Optimized to ${result.size} bytes`);
}
```

**Quality constraint:**
```typescript
const result = await pyjamaz.optimizeImage('input.png', {
  maxDiff: 0.002,
  metric: 'ssimulacra2',
});

console.log(`Quality score: ${result.diffValue}`);
```

**Dual constraints:**
```typescript
const result = await pyjamaz.optimizeImage('input.jpg', {
  maxBytes: 80_000,
  maxDiff: 0.001,
  metric: 'dssim',
});
```

---

### Quality Constraints

**DSSIM metric (structural dissimilarity):**
```typescript
const result = await pyjamaz.optimizeImage('input.jpg', {
  maxDiff: 0.001,
  metric: 'dssim',
});

if (result.diffValue <= 0.001) {
  console.log('Quality target met!');
}
```

**SSIMULACRA2 metric (perceptually optimized):**
```typescript
const result = await pyjamaz.optimizeImage('input.png', {
  maxDiff: 0.002,
  metric: 'ssimulacra2',
});
```

**Fast mode (no quality check):**
```typescript
const result = await pyjamaz.optimizeImage('input.jpg', {
  maxBytes: 50_000,
  metric: 'none', // Skip quality calculation for speed
});
```

---

### Format Selection

**Try all formats (default):**
```typescript
const result = await pyjamaz.optimizeImage('input.jpg', {
  maxBytes: 100_000,
});

console.log(`Best format: ${result.format}`);
```

**Modern formats only:**
```typescript
const result = await pyjamaz.optimizeImage('input.jpg', {
  formats: ['webp', 'avif'],
  maxBytes: 50_000,
});
```

**Specific format:**
```typescript
const result = await pyjamaz.optimizeImage('input.png', {
  formats: ['png'],
  maxBytes: 100_000,
});
```

---

### Batch Processing

**Parallel processing with async/await:**
```typescript
import * as fs from 'fs';
import * as path from 'path';

async function optimizeBatch(
  inputDir: string,
  outputDir: string,
  maxBytes: number
): Promise<void> {
  const files = await fs.promises.readdir(inputDir);
  const images = files.filter(f => /\.(jpg|png|webp)$/i.test(f));

  // Process in parallel
  const promises = images.map(async (filename) => {
    const inputPath = path.join(inputDir, filename);
    const result = await pyjamaz.optimizeImage(inputPath, {
      maxBytes,
      cacheEnabled: true,
    });

    if (result.passed) {
      const outputPath = path.join(
        outputDir,
        `${path.parse(filename).name}.${result.format}`
      );
      await result.save(outputPath);
      console.log(`✓ ${filename}: ${result.size} bytes`);
    } else {
      console.log(`✗ ${filename}: ${result.errorMessage}`);
    }
  });

  await Promise.all(promises);
}

// Usage
await optimizeBatch('images', 'optimized', 100_000);
```

**Sequential processing with progress:**
```typescript
async function optimizeSequential(
  images: string[],
  maxBytes: number
): Promise<void> {
  for (let i = 0; i < images.length; i++) {
    const result = await pyjamaz.optimizeImage(images[i], { maxBytes });

    if (result.passed) {
      await result.save(`output_${i}.${result.format}`);
      console.log(`[${i + 1}/${images.length}] ✓ ${result.size} bytes`);
    }
  }
}
```

---

### Caching

**Enable caching (default):**
```typescript
const result = await pyjamaz.optimizeImage('input.jpg', {
  maxBytes: 100_000,
  cacheEnabled: true, // Default
});
```

**Disable caching:**
```typescript
const result = await pyjamaz.optimizeImage('input.jpg', {
  maxBytes: 100_000,
  cacheEnabled: false,
});
```

**Custom cache directory:**
```typescript
const result = await pyjamaz.optimizeImage('input.jpg', {
  maxBytes: 100_000,
  cacheDir: '/tmp/my-cache',
});
```

**Custom cache size:**
```typescript
const result = await pyjamaz.optimizeImage('input.jpg', {
  maxBytes: 100_000,
  cacheMaxSize: 2 * 1024 * 1024 * 1024, // 2GB
});
```

**Measure cache speedup:**
```typescript
// First run (cache miss)
const start1 = Date.now();
const result1 = await pyjamaz.optimizeImage('input.jpg', {
  maxBytes: 100_000,
});
const time1 = Date.now() - start1;

// Second run (cache hit)
const start2 = Date.now();
const result2 = await pyjamaz.optimizeImage('input.jpg', {
  maxBytes: 100_000,
});
const time2 = Date.now() - start2;

console.log(`First run: ${time1}ms`);
console.log(`Second run: ${time2}ms (${(time1 / time2).toFixed(1)}x faster)`);
```

---

## Integration Examples

### Express Server

```typescript
import express from 'express';
import multer from 'multer';
import * as pyjamaz from '@pyjamaz/nodejs';

const app = express();
const upload = multer();

app.post('/optimize', upload.single('image'), async (req, res) => {
  try {
    if (!req.file) {
      return res.status(400).json({ error: 'No image provided' });
    }

    const result = await pyjamaz.optimizeImageFromBuffer(req.file.buffer, {
      maxBytes: 100_000,
      metric: 'ssimulacra2',
    });

    if (!result.passed) {
      return res.status(400).json({ error: result.errorMessage });
    }

    res.set('Content-Type', `image/${result.format}`);
    res.send(result.data);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

app.listen(3000, () => console.log('Server running on port 3000'));
```

---

### Fastify Server

```typescript
import Fastify from 'fastify';
import multipart from '@fastify/multipart';
import * as pyjamaz from '@pyjamaz/nodejs';

const fastify = Fastify();
await fastify.register(multipart);

fastify.post('/optimize', async (request, reply) => {
  try {
    const data = await request.file();
    if (!data) {
      return reply.code(400).send({ error: 'No image provided' });
    }

    const buffer = await data.toBuffer();
    const result = await pyjamaz.optimizeImageFromBuffer(buffer, {
      maxBytes: 100_000,
    });

    if (!result.passed) {
      return reply.code(400).send({ error: result.errorMessage });
    }

    reply.type(`image/${result.format}`).send(result.data);
  } catch (error) {
    reply.code(500).send({ error: error.message });
  }
});

await fastify.listen({ port: 3000 });
```

---

### CLI Tool

```typescript
#!/usr/bin/env node
import * as pyjamaz from '@pyjamaz/nodejs';
import { program } from 'commander';

program
  .name('optimize-image')
  .description('Optimize images with Pyjamaz')
  .argument('<input>', 'Input image path')
  .option('-o, --output <path>', 'Output path')
  .option('-s, --size <bytes>', 'Max size in bytes', parseInt)
  .option('-q, --quality <diff>', 'Max diff', parseFloat)
  .option('-m, --metric <type>', 'Metric type', 'dssim')
  .action(async (input, options) => {
    try {
      const result = await pyjamaz.optimizeImage(input, {
        maxBytes: options.size,
        maxDiff: options.quality,
        metric: options.metric,
      });

      if (result.passed) {
        const output = options.output || `output.${result.format}`;
        await result.save(output);
        console.log(`✓ Optimized to ${result.size} bytes as ${result.format}`);
      } else {
        console.error(`✗ Failed: ${result.errorMessage}`);
        process.exit(1);
      }
    } catch (error) {
      console.error(`✗ Error: ${error.message}`);
      process.exit(1);
    }
  });

program.parse();
```

---

## Performance Tips

### 1. Use Caching

Enable caching for 15-20x speedup on repeated optimizations:

```typescript
const result = await pyjamaz.optimizeImage('input.jpg', {
  cacheEnabled: true, // Default
});
```

### 2. Adjust Concurrency

Optimize concurrency based on CPU cores:

```typescript
const cpus = require('os').cpus().length;

const result = await pyjamaz.optimizeImage('input.jpg', {
  concurrency: Math.min(cpus, 8), // Max 8
});
```

### 3. Use Sync for Batch

For batch processing, use sync API to avoid promise overhead:

```typescript
for (const image of images) {
  const result = pyjamaz.optimizeImageSync(image, options);
  // Process result
}
```

### 4. Skip Quality Checks

Use `metric: 'none'` when quality is not critical:

```typescript
const result = await pyjamaz.optimizeImage('input.jpg', {
  maxBytes: 100_000,
  metric: 'none', // Faster
});
```

### 5. Limit Formats

Try fewer formats for faster optimization:

```typescript
const result = await pyjamaz.optimizeImage('input.jpg', {
  formats: ['jpeg', 'webp'], // Only 2 formats
});
```

---

## Troubleshooting

### Library Not Found

**Error:** `Could not find libpyjamaz shared library`

**Solution:**

1. Build the shared library:
   ```bash
   cd /path/to/pyjamaz
   zig build
   ```

2. Set environment variable:
   ```bash
   export PYJAMAZ_LIB_PATH=/path/to/pyjamaz/zig-out/lib/libpyjamaz.dylib
   ```

3. Or install system-wide:
   ```bash
   sudo cp zig-out/lib/libpyjamaz.* /usr/local/lib/
   ```

---

### Type Errors

**Error:** TypeScript compilation errors

**Solution:**

1. Ensure TypeScript is installed:
   ```bash
   npm install typescript --save-dev
   ```

2. Build the project:
   ```bash
   npm run build
   ```

3. Check `tsconfig.json` settings

---

### Import Errors

**Error:** `Cannot find module '@pyjamaz/nodejs'`

**Solution:**

1. Install dependencies:
   ```bash
   npm install
   ```

2. Build the project:
   ```bash
   npm run build
   ```

3. Use correct import:
   ```typescript
   import * as pyjamaz from '@pyjamaz/nodejs';
   ```

---

### FFI Errors

**Error:** FFI-related errors

**Solution:**

1. Ensure `ffi-napi` is installed:
   ```bash
   npm install ffi-napi ref-napi
   ```

2. Check Node.js version (≥14.0.0):
   ```bash
   node --version
   ```

3. Rebuild native modules:
   ```bash
   npm rebuild
   ```

---

## Requirements

- **Node.js**: 14.0.0 or higher
- **TypeScript**: 5.0+ (for development)
- **libpyjamaz**: Shared library (built from Zig source)
- **System dependencies**: libvips, libjpeg-turbo, libdssim

---

## License

MIT License - see [LICENSE](../LICENSE) for details.

---

## Links

- **GitHub**: [https://github.com/yourusername/pyjamaz](https://github.com/yourusername/pyjamaz)
- **Issues**: [https://github.com/yourusername/pyjamaz/issues](https://github.com/yourusername/pyjamaz/issues)
- **Main Documentation**: [README.md](../README.md)
- **Python API**: [PYTHON_API.md](./PYTHON_API.md)

---

**Last Updated**: 2025-10-31
**Version**: 1.0.0
**Status**: Production-ready
