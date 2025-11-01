/**
 * FFI bindings layer for Pyjamaz shared library using koffi
 */

import koffi from 'koffi';
import path from 'path';
import fs from 'fs';

/**
 * Error thrown by FFI binding layer
 */
export class PyjamazBindingError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'PyjamazBindingError';
  }
}

// Define C structures using koffi (matching Zig api.zig)
const OptimizeOptions = koffi.struct('OptimizeOptions', {
  input_bytes: koffi.pointer('uint8_t'),  // [*]const u8 in Zig
  input_len: 'size_t',
  max_bytes: 'uint32_t',
  max_diff: 'double',
  metric_type: koffi.pointer('char'),     // [*:0]const u8 (null-terminated string)
  formats: koffi.pointer('char'),         // [*:0]const u8 (null-terminated string)
  concurrency: 'uint8_t',
  cache_enabled: 'uint8_t',
  cache_dir: koffi.pointer('char'),       // [*:0]const u8 (null-terminated string)
  cache_max_size: 'uint64_t',
});

const OptimizeResult = koffi.struct('OptimizeResult', {
  output_bytes: koffi.pointer('uint8_t'),
  output_len: 'size_t',
  format: koffi.pointer('char'),        // null-terminated string
  diff_value: 'double',
  passed: 'uint8_t',
  error_message: koffi.pointer('char'), // null-terminated string
});

/**
 * Find the Pyjamaz shared library
 *
 * Search order:
 * 1. PYJAMAZ_LIB_PATH environment variable
 * 2. Bundled library (for npm package installations)
 * 3. Development build (zig-out/lib)
 * 4. System paths
 */
function findLibrary(): string {
  // 1. Check environment variable first (highest priority)
  const envPath = process.env.PYJAMAZ_LIB_PATH;
  if (envPath && fs.existsSync(envPath)) {
    return envPath;
  }

  const possiblePaths: string[] = [];

  // 2. Check bundled library (npm package installation)
  // When installed via npm, libraries are in ../native/ relative to dist/
  const bundledPaths = [
    path.join(__dirname, '..', 'native', 'libpyjamaz.dylib'),
    path.join(__dirname, '..', 'native', 'libpyjamaz.so'),
    path.join(__dirname, '..', 'native', 'pyjamaz.dll'),
  ];
  possiblePaths.push(...bundledPaths);

  // 3. Check development build (from source)
  // From bindings/nodejs/dist to zig-out/lib
  const devPaths = [
    path.join(__dirname, '..', '..', '..', 'zig-out', 'lib', 'libpyjamaz.dylib'),
    path.join(__dirname, '..', '..', '..', 'zig-out', 'lib', 'libpyjamaz.so'),
    path.join(__dirname, '..', '..', '..', 'zig-out', 'lib', 'pyjamaz.dll'),
  ];
  possiblePaths.push(...devPaths);

  // 4. Check system paths
  const systemPaths = [
    '/usr/local/lib/libpyjamaz.dylib',
    '/usr/local/lib/libpyjamaz.so',
    '/usr/lib/libpyjamaz.so',
  ];
  possiblePaths.push(...systemPaths);

  // Try all paths in order
  for (const libPath of possiblePaths) {
    if (fs.existsSync(libPath)) {
      return libPath;
    }
  }

  throw new Error(
    'Could not find libpyjamaz shared library. Tried:\n' +
    possiblePaths.map(p => `  - ${p}`).join('\n') + '\n\n' +
    'Please either:\n' +
    '  1. Install via npm (npm install pyjamaz)\n' +
    '  2. Build from source (zig build)\n' +
    '  3. Set PYJAMAZ_LIB_PATH environment variable'
  );
}

/**
 * Load the Pyjamaz shared library
 */
const libPath = findLibrary();
const lib = koffi.load(libPath);

// Define FFI functions
const pyjamaz_version = lib.func('pyjamaz_version', 'string', []);
const pyjamaz_optimize = lib.func('pyjamaz_optimize', koffi.pointer(OptimizeResult), [koffi.pointer(OptimizeOptions)]);
const pyjamaz_free_result = lib.func('pyjamaz_free_result', 'void', [koffi.pointer(OptimizeResult)]);
const pyjamaz_cleanup = lib.func('pyjamaz_cleanup', 'void', []);

/**
 * Cleanup function to be called on process exit
 */
let cleanupRegistered = false;

export function registerCleanup(): void {
  if (cleanupRegistered) return;
  cleanupRegistered = true;

  // Register cleanup handlers
  const cleanup = () => {
    try {
      if (pyjamaz_cleanup) {
        pyjamaz_cleanup();
      }
    } catch (err) {
      console.error('Error during cleanup:', err);
    }
  };

  process.on('exit', cleanup);
  process.on('SIGINT', () => {
    cleanup();
    process.exit(130);
  });
  process.on('SIGTERM', () => {
    cleanup();
    process.exit(143);
  });
}

/**
 * Get Pyjamaz library version
 */
export function getVersion(): string {
  return pyjamaz_version();
}

/**
 * Optimize an image using the Pyjamaz library
 */
export function optimize(
  inputData: Buffer,
  options: {
    maxBytes?: number;
    maxDiff?: number;
    metric?: string;
    formats?: string[];
    concurrency?: number;
    cacheEnabled?: boolean;
    cacheDir?: string;
    cacheMaxSize?: number;
  }
): { data: Buffer; format: string; diffValue: number; passed: boolean; errorMessage?: string } {
  registerCleanup();

  // Prepare formats string (comma-separated, null-terminated)
  const formats = options.formats || ['jpeg', 'png', 'webp', 'avif'];
  const formatsBytes = Buffer.from(formats.join(',') + '\0', 'utf-8');

  // Prepare metric string (null-terminated)
  const metricBytes = Buffer.from((options.metric || 'dssim') + '\0', 'utf-8');

  // Prepare cache directory (null-terminated)
  const cacheDirBytes = Buffer.from((options.cacheDir || '') + '\0', 'utf-8');

  // Create options object matching Zig API
  const opts = {
    input_bytes: inputData,
    input_len: inputData.length,
    max_bytes: options.maxBytes || 0,
    max_diff: options.maxDiff || 0.0,
    metric_type: metricBytes,
    formats: formatsBytes,
    concurrency: options.concurrency || 4,
    cache_enabled: options.cacheEnabled === false ? 0 : 1,
    cache_dir: cacheDirBytes,
    cache_max_size: options.cacheMaxSize || 0, // 0 = default 1GB in Zig
  };

  // Call the FFI function (koffi automatically passes struct by reference)
  const resultPtr = pyjamaz_optimize(opts);

  if (!resultPtr) {
    throw new PyjamazBindingError('Optimization failed: returned null pointer');
  }

  try {
    // Read the result struct
    const result = koffi.decode(resultPtr, OptimizeResult);

    // Tiger Style: Validate C memory before reading
    let data: Buffer;
    if (result.output_len > 0) {
      // Validate output pointer
      if (!result.output_bytes) {
        throw new PyjamazBindingError('Invalid result: output_bytes is null but output_len > 0');
      }

      // Sanity check size (max 100MB)
      const MAX_OUTPUT_SIZE = 100 * 1024 * 1024;
      if (result.output_len > MAX_OUTPUT_SIZE) {
        throw new PyjamazBindingError(`Output size too large: ${result.output_len} bytes (max ${MAX_OUTPUT_SIZE})`);
      }

      // Read output data
      const OutputArray = koffi.array('uint8_t', result.output_len);
      const outputArray = koffi.decode(result.output_bytes, OutputArray);
      data = Buffer.from(outputArray);
    } else {
      data = Buffer.alloc(0);
    }

    // Format and error message are already decoded by koffi (char pointers become strings)
    const formatStr = result.format || 'jpeg';
    const errorMessage = result.error_message && result.error_message.length > 0
      ? result.error_message
      : undefined;

    return {
      data,
      format: formatStr,
      diffValue: result.diff_value,
      passed: result.passed !== 0,
      errorMessage,
    };
  } finally {
    // Free the result
    pyjamaz_free_result(resultPtr);
  }
}

export { OptimizeOptions, OptimizeResult };
