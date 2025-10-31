/**
 * Batch processing example for Pyjamaz Node.js bindings (TypeScript)
 */

import * as pyjamaz from '../src/index';
import * as fs from 'fs';
import * as path from 'path';
import { promisify } from 'util';

const readdir = promisify(fs.readdir);
const stat = promisify(fs.stat);

interface ProcessResult {
  success: boolean;
  input: string;
  output?: string;
  originalSize?: number;
  optimizedSize?: number;
  reduction?: number;
  format?: string;
  quality?: number;
  error?: string;
}

/**
 * Optimize a single image
 */
async function optimizeSingleImage(
  inputPath: string,
  outputDir: string,
  maxBytes: number
): Promise<ProcessResult> {
  try {
    const result = await pyjamaz.optimizeImage(inputPath, {
      maxBytes,
      metric: 'ssimulacra2',
      cacheEnabled: true,
    });

    if (result.passed) {
      const inputName = path.basename(inputPath, path.extname(inputPath));
      const outputPath = path.join(outputDir, `${inputName}_optimized.${result.format}`);
      await result.save(outputPath);

      const originalSize = (await stat(inputPath)).size;
      const reduction = ((1 - result.size / originalSize) * 100);

      return {
        success: true,
        input: path.basename(inputPath),
        output: path.basename(outputPath),
        originalSize,
        optimizedSize: result.size,
        reduction,
        format: result.format,
        quality: result.diffValue,
      };
    } else {
      return {
        success: false,
        input: path.basename(inputPath),
        error: result.errorMessage,
      };
    }
  } catch (error) {
    return {
      success: false,
      input: path.basename(inputPath),
      error: error instanceof Error ? error.message : String(error),
    };
  }
}

/**
 * Process images in batches with parallelism
 */
async function processBatch(
  images: string[],
  outputDir: string,
  maxBytes: number,
  maxParallel: number
): Promise<ProcessResult[]> {
  const results: ProcessResult[] = [];
  const pending: Promise<ProcessResult>[] = [];

  for (const imagePath of images) {
    // Add to pending promises
    const promise = optimizeSingleImage(imagePath, outputDir, maxBytes);
    pending.push(promise);

    // When we reach max parallel, wait for one to complete
    if (pending.length >= maxParallel) {
      const result = await Promise.race(pending);
      results.push(result);

      // Remove completed promise
      const index = pending.findIndex(async (p) => (await p) === result);
      if (index !== -1) {
        pending.splice(index, 1);
      }
    }
  }

  // Wait for remaining promises
  const remaining = await Promise.all(pending);
  results.push(...remaining);

  return results;
}

/**
 * Main function
 */
async function main() {
  // Configuration
  const inputDir = 'images';
  const outputDir = 'optimized';
  const maxBytes = 100_000; // 100KB target
  const maxParallel = 4; // Parallel workers

  // Create output directory
  if (!fs.existsSync(outputDir)) {
    fs.mkdirSync(outputDir, { recursive: true });
  }

  // Find all images
  const imageExtensions = new Set(['.jpg', '.jpeg', '.png', '.webp']);
  const files = await readdir(inputDir);
  const images = files
    .filter((file) => imageExtensions.has(path.extname(file).toLowerCase()))
    .map((file) => path.join(inputDir, file));

  console.log(`Found ${images.length} images to optimize`);
  console.log(`Target size: ${maxBytes.toLocaleString()} bytes`);
  console.log(`Using ${maxParallel} parallel workers`);
  console.log();

  // Process images
  const startTime = Date.now();
  const results: ProcessResult[] = [];

  // Process with progress updates
  for (const imagePath of images) {
    const result = await optimizeSingleImage(imagePath, outputDir, maxBytes);
    results.push(result);

    if (result.success) {
      console.log(
        `✓ ${result.input}: ${result.originalSize!.toLocaleString()} → ` +
        `${result.optimizedSize!.toLocaleString()} bytes (${result.reduction!.toFixed(1)}% reduction)`
      );
    } else {
      console.log(`✗ ${result.input}: ${result.error}`);
    }
  }

  const elapsed = (Date.now() - startTime) / 1000;

  // Print summary
  const successful = results.filter((r) => r.success);
  const failed = results.filter((r) => !r.success);

  console.log(`\n${'='.repeat(60)}`);
  console.log(`Processed ${images.length} images in ${elapsed.toFixed(2)}s`);
  console.log(`Success: ${successful.length}, Failed: ${failed.length}`);

  if (successful.length > 0) {
    const totalOriginal = successful.reduce((sum, r) => sum + (r.originalSize || 0), 0);
    const totalOptimized = successful.reduce((sum, r) => sum + (r.optimizedSize || 0), 0);
    const totalReduction = ((1 - totalOptimized / totalOriginal) * 100);

    console.log(`\nTotal size: ${totalOriginal.toLocaleString()} → ${totalOptimized.toLocaleString()} bytes`);
    console.log(`Total reduction: ${totalReduction.toFixed(1)}%`);
    console.log(`Average per image: ${(elapsed / images.length).toFixed(3)}s`);
  }
}

// Run
main().catch(console.error);
