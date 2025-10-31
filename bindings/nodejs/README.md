# Pyjamaz Node.js Bindings

**High-performance image optimizer with perceptual quality guarantees for Node.js.**

TypeScript-first Node.js bindings for [Pyjamaz](https://github.com/yourusername/pyjamaz) - a blazing-fast CLI image optimizer built with Zig.

## Features

- 🚀 **Blazing Fast**: 50-100ms per image with parallel encoding
- 💾 **Intelligent Caching**: 15-20x speedup on repeated optimizations
- 🎯 **Smart Optimization**: Automatic format selection (JPEG/PNG/WebP/AVIF)
- 📊 **Perceptual Quality**: DSSIM & SSIMULACRA2 metrics
- 🔒 **Size Guarantees**: Never exceed maxBytes constraint
- 🧹 **Auto Memory Management**: No manual cleanup required
- 📘 **TypeScript-First**: Full type safety with IntelliSense support
- 🐍 **Dual API**: Both sync and async variants

## Installation

### From Source (Development)

```bash
# Clone the repository
git clone https://github.com/yourusername/pyjamaz.git
cd pyjamaz

# Build the shared library
zig build

# Install Node.js bindings
cd bindings/nodejs
npm install
npm run build
```

### From npm (Coming Soon)

```bash
npm install @pyjamaz/nodejs
```

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

## API Reference

### Core Functions

#### `optimizeImage(inputPath, options?)`

Optimize an image from file path (async).

```typescript
async function optimizeImage(
  inputPath: string,
  options?: OptimizeOptions
): Promise<OptimizeResult>
```

**Example:**
```typescript
const result = await pyjamaz.optimizeImage('input.jpg', {
  maxBytes: 100_000,
  metric: 'dssim',
});
```

---

#### `optimizeImageSync(inputPath, options?)`

Optimize an image from file path (sync).

```typescript
function optimizeImageSync(
  inputPath: string,
  options?: OptimizeOptions
): OptimizeResult
```

**Example:**
```typescript
const result = pyjamaz.optimizeImageSync('input.jpg', {
  maxBytes: 100_000,
});
```

---

#### `optimizeImageFromBuffer(buffer, options?)`

Optimize an image from Buffer (async).

```typescript
async function optimizeImageFromBuffer(
  buffer: Buffer,
  options?: OptimizeOptions
): Promise<OptimizeResult>
```

**Example:**
```typescript
const inputData = await fs.promises.readFile('input.jpg');
const result = await pyjamaz.optimizeImageFromBuffer(inputData, {
  maxBytes: 100_000,
});
```

---

#### `getVersion()`

Get the Pyjamaz library version.

```typescript
function getVersion(): string
```

**Example:**
```typescript
console.log(`Pyjamaz version: ${pyjamaz.getVersion()}`);
```

---

### OptimizeOptions

```typescript
interface OptimizeOptions {
  maxBytes?: number;           // Max output size (undefined = no limit)
  maxDiff?: number;            // Max perceptual difference
  metric?: MetricType;         // 'dssim' | 'ssimulacra2' | 'none'
  formats?: ImageFormat[];     // ['jpeg', 'png', 'webp', 'avif']
  concurrency?: number;        // Parallel threads (1-8, default 4)
  cacheEnabled?: boolean;      // Enable caching (default true)
  cacheDir?: string;           // Custom cache directory
  cacheMaxSize?: number;       // Max cache size in bytes (default 1GB)
}
```

---

### OptimizeResult

```typescript
interface OptimizeResult {
  data: Buffer;                // Optimized image data
  format: ImageFormat;         // Selected format
  diffValue: number;           // Perceptual difference score
  passed: boolean;             // Whether constraints met
  errorMessage?: string;       // Error message if failed
  readonly size: number;       // Size in bytes

  save(path: string): Promise<void>;     // Save async
  saveSync(path: string): void;          // Save sync
}
```

## Usage Examples

### Basic Optimization

```typescript
// Size constraint
const result = await pyjamaz.optimizeImage('input.jpg', {
  maxBytes: 100_000,
});

// Quality constraint
const result = await pyjamaz.optimizeImage('input.png', {
  maxDiff: 0.002,
  metric: 'ssimulacra2',
});

// Dual constraints
const result = await pyjamaz.optimizeImage('input.jpg', {
  maxBytes: 80_000,
  maxDiff: 0.001,
  metric: 'dssim',
});
```

### Format Selection

```typescript
// Try all formats (default)
const result = await pyjamaz.optimizeImage('input.jpg', {
  maxBytes: 100_000,
});
console.log(`Best format: ${result.format}`);

// Modern formats only
const result = await pyjamaz.optimizeImage('input.jpg', {
  formats: ['webp', 'avif'],
  maxBytes: 50_000,
});
```

### From Buffer

```typescript
// Optimize from memory
const inputData = await fs.promises.readFile('input.jpg');
const result = await pyjamaz.optimizeImageFromBuffer(inputData, {
  maxBytes: 100_000,
});

// Save result
await fs.promises.writeFile('output.webp', result.data);
// or
await result.save('output.webp');
```

### Batch Processing

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

### Caching

```typescript
// Enable caching (default)
const result = await pyjamaz.optimizeImage('input.jpg', {
  maxBytes: 100_000,
  cacheEnabled: true,
});

// Disable caching
const result = await pyjamaz.optimizeImage('input.jpg', {
  maxBytes: 100_000,
  cacheEnabled: false,
});

// Custom cache settings
const result = await pyjamaz.optimizeImage('input.jpg', {
  cacheEnabled: true,
  cacheDir: '/tmp/my-cache',
  cacheMaxSize: 2 * 1024 * 1024 * 1024, // 2GB
});

// Measure cache speedup
const start1 = Date.now();
const result1 = await pyjamaz.optimizeImage('input.jpg', { maxBytes: 100_000 });
const time1 = Date.now() - start1;

const start2 = Date.now();
const result2 = await pyjamaz.optimizeImage('input.jpg', { maxBytes: 100_000 });
const time2 = Date.now() - start2;

console.log(`First run: ${time1}ms`);
console.log(`Second run: ${time2}ms (${(time1 / time2).toFixed(1)}x faster)`);
```

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

app.listen(3000);
```

### Fastify Server

```typescript
import Fastify from 'fastify';
import multipart from '@fastify/multipart';
import * as pyjamaz from '@pyjamaz/nodejs';

const fastify = Fastify();
await fastify.register(multipart);

fastify.post('/optimize', async (request, reply) => {
  const data = await request.file();
  const buffer = await data.toBuffer();

  const result = await pyjamaz.optimizeImageFromBuffer(buffer, {
    maxBytes: 100_000,
  });

  if (!result.passed) {
    return reply.code(400).send({ error: result.errorMessage });
  }

  reply.type(`image/${result.format}`).send(result.data);
});

await fastify.listen({ port: 3000 });
```

## Development

### Running Tests

```bash
# Install dependencies
npm install

# Build TypeScript
npm run build

# Run all tests
npm test

# Run TypeScript tests only
npm run test:ts

# Run JavaScript tests only
npm run test:js

# With coverage
npm run test:coverage
```

### Code Quality

```bash
# Format code
npm run format

# Lint
npm run lint

# Type checking
tsc --noEmit
```

## Performance

**Platform**: Apple M1 Pro, macOS 15.0

| Operation | Time | Notes |
|-----------|------|-------|
| Optimize (first run) | 50-100ms | Full optimization |
| Optimize (cache hit) | 5-10ms | 15-20x faster |
| Batch (100 images, parallel) | ~3s | 4 workers |

## Requirements

- **Node.js**: 14.0.0 or higher
- **TypeScript**: 5.0+ (for development)
- **libpyjamaz**: Shared library (built from Zig source)
- **System dependencies**: libvips, libjpeg-turbo, libdssim

## Troubleshooting

### Library Not Found

If you get `Could not find libpyjamaz shared library`:

1. Build the shared library:
   ```bash
   cd /path/to/pyjamaz
   zig build
   ```

2. Set `PYJAMAZ_LIB_PATH`:
   ```bash
   export PYJAMAZ_LIB_PATH=/path/to/pyjamaz/zig-out/lib/libpyjamaz.dylib
   ```

3. Or install system-wide:
   ```bash
   sudo cp zig-out/lib/libpyjamaz.* /usr/local/lib/
   ```

### Import Errors

Make sure you've built the TypeScript code:

```bash
npm run build
```

Then use correct import:

```typescript
// TypeScript/ESM
import * as pyjamaz from '@pyjamaz/nodejs';

// CommonJS
const pyjamaz = require('@pyjamaz/nodejs');
```

## License

MIT License - see [LICENSE](../../LICENSE) for details.

## Contributing

Contributions welcome! See [CONTRIBUTING.md](../../docs/CONTRIBUTING.md) for guidelines.

## Links

- **Complete API Documentation**: [docs/NODEJS_API.md](../../docs/NODEJS_API.md)
- **Main Documentation**: [README.md](../../README.md)
- **Python Bindings**: [bindings/python/](../python/)
- **Issues**: [GitHub Issues](https://github.com/yourusername/pyjamaz/issues)
- **Discussions**: [GitHub Discussions](https://github.com/yourusername/pyjamaz/discussions)
