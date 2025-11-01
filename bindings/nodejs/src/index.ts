/**
 * Pyjamaz Node.js Bindings
 *
 * High-performance image optimizer with perceptual quality guarantees.
 * TypeScript-first API with automatic memory management.
 */

import fs from 'fs';
import { promises as fsPromises } from 'fs';
import * as bindings from './bindings';
import {
  ImageFormat,
  OptimizeOptions,
  OptimizeResult,
  PyjamazError,
} from './types';

/**
 * Get the Pyjamaz library version
 *
 * @returns Version string (e.g., "1.0.0")
 *
 * @example
 * ```typescript
 * import { getVersion } from '@pyjamaz/nodejs';
 *
 * console.log(`Pyjamaz version: ${getVersion()}`);
 * ```
 */
export function getVersion(): string {
  return bindings.getVersion();
}

/**
 * Optimize an image from file path
 *
 * @param inputPath - Path to input image file
 * @param options - Optimization options
 * @returns Promise resolving to optimization result
 *
 * @throws {PyjamazError} If optimization fails
 *
 * @example
 * ```typescript
 * const result = await optimizeImage('input.jpg', {
 *   maxBytes: 100_000,
 *   metric: 'dssim',
 * });
 *
 * if (result.passed) {
 *   await result.save('output.jpg');
 *   console.log(`Optimized to ${result.size} bytes`);
 * }
 * ```
 */
export async function optimizeImage(
  inputPath: string,
  options: OptimizeOptions = {}
): Promise<OptimizeResult> {
  const inputData = await fsPromises.readFile(inputPath);
  return optimizeImageFromBuffer(inputData, options);
}

/**
 * Optimize an image from Buffer (synchronous version)
 *
 * @param inputPath - Path to input image file
 * @param options - Optimization options
 * @returns Optimization result
 *
 * @throws {PyjamazError} If optimization fails
 *
 * @example
 * ```typescript
 * const result = optimizeImageSync('input.jpg', { maxBytes: 100_000 });
 * result.saveSync('output.jpg');
 * ```
 */
export function optimizeImageSync(
  inputPath: string,
  options: OptimizeOptions = {}
): OptimizeResult {
  const inputData = fs.readFileSync(inputPath);
  return optimizeImageFromBufferSync(inputData, options);
}

/**
 * Optimize an image from Buffer
 *
 * @param buffer - Input image data
 * @param options - Optimization options
 * @returns Promise resolving to optimization result
 *
 * @throws {PyjamazError} If optimization fails
 *
 * @example
 * ```typescript
 * const inputData = await fs.promises.readFile('input.jpg');
 * const result = await optimizeImageFromBuffer(inputData, {
 *   maxBytes: 100_000,
 *   maxDiff: 0.002,
 * });
 * ```
 */
export async function optimizeImageFromBuffer(
  buffer: Buffer,
  options: OptimizeOptions = {}
): Promise<OptimizeResult> {
  return Promise.resolve(optimizeImageFromBufferSync(buffer, options));
}

/**
 * Optimize an image from Buffer (synchronous version)
 *
 * @param buffer - Input image data
 * @param options - Optimization options
 * @returns Optimization result
 *
 * @throws {PyjamazError} If optimization fails
 *
 * @example
 * ```typescript
 * const inputData = fs.readFileSync('input.jpg');
 * const result = optimizeImageFromBufferSync(inputData, {
 *   maxBytes: 50_000,
 *   formats: ['webp', 'avif'],
 * });
 * ```
 */
export function optimizeImageFromBufferSync(
  buffer: Buffer,
  options: OptimizeOptions = {}
): OptimizeResult {
  try {
    const result = bindings.optimize(buffer, {
      maxBytes: options.maxBytes,
      maxDiff: options.maxDiff,
      metric: options.metric || 'dssim',
      formats: options.formats,
      concurrency: options.concurrency || 4,
      cacheEnabled: options.cacheEnabled !== false,
      cacheDir: options.cacheDir,
      cacheMaxSize: options.cacheMaxSize,
    });

    return new OptimizeResultImpl(
      result.data,
      result.format as ImageFormat,
      result.diffValue,
      result.passed,
      result.errorMessage
    );
  } catch (error) {
    if (error instanceof Error) {
      throw new PyjamazError(`Optimization failed: ${error.message}`);
    }
    throw new PyjamazError('Optimization failed: Unknown error');
  }
}

/**
 * Internal implementation of OptimizeResult
 */
class OptimizeResultImpl implements OptimizeResult {
  public readonly data: Buffer;
  public readonly format: ImageFormat;
  public readonly diffValue: number;
  public readonly passed: boolean;
  public readonly errorMessage?: string;

  constructor(
    data: Buffer,
    format: ImageFormat,
    diffValue: number,
    passed: boolean,
    errorMessage?: string
  ) {
    this.data = data;
    this.format = format;
    this.diffValue = diffValue;
    this.passed = passed;
    this.errorMessage = errorMessage;
  }

  /**
   * Get the size of optimized image in bytes
   */
  get size(): number {
    return this.data.length;
  }

  /**
   * Save the optimized image to a file (async)
   *
   * @param outputPath - Path to save the output file
   *
   * @example
   * ```typescript
   * await result.save('output.jpg');
   * ```
   */
  async save(outputPath: string): Promise<void> {
    await fsPromises.writeFile(outputPath, this.data);
  }

  /**
   * Save the optimized image to a file (sync)
   *
   * @param outputPath - Path to save the output file
   *
   * @example
   * ```typescript
   * result.saveSync('output.jpg');
   * ```
   */
  saveSync(outputPath: string): void {
    fs.writeFileSync(outputPath, this.data);
  }
}

// Re-export types
export {
  ImageFormat,
  MetricType,
  OptimizeOptions,
  OptimizeResult,
  PyjamazError,
} from './types';

// Default export
export default {
  getVersion,
  optimizeImage,
  optimizeImageSync,
  optimizeImageFromBuffer,
  optimizeImageFromBufferSync,
};
