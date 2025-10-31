/**
 * Basic usage examples for Pyjamaz Node.js bindings (TypeScript)
 */

import * as pyjamaz from '../src/index';
import * as fs from 'fs';

async function main() {
  console.log(`Pyjamaz version: ${pyjamaz.getVersion()}\n`);

  // Example 1: Optimize with size constraint
  console.log('=== Example 1: Size constraint ===');
  try {
    const result1 = await pyjamaz.optimizeImage('input.jpg', {
      maxBytes: 100_000,
    });

    if (result1.passed) {
      await result1.save('output1.jpg');
      console.log(`✓ Optimized to ${result1.size.toLocaleString()} bytes as ${result1.format}`);
      console.log(`  Quality score: ${result1.diffValue.toFixed(6)}`);
    } else {
      console.log(`✗ Failed: ${result1.errorMessage}`);
    }
  } catch (error) {
    console.log(`✗ Error: ${error}`);
  }

  console.log();

  // Example 2: Optimize with quality constraint
  console.log('=== Example 2: Quality constraint (SSIMULACRA2) ===');
  try {
    const result2 = await pyjamaz.optimizeImage('input.png', {
      maxDiff: 0.002,
      metric: 'ssimulacra2',
    });

    if (result2.passed) {
      await result2.save('output2.webp');
      console.log(`✓ Optimized to ${result2.size.toLocaleString()} bytes as ${result2.format}`);
      console.log(`  Quality score: ${result2.diffValue.toFixed(6)}`);
    } else {
      console.log(`✗ Failed: ${result2.errorMessage}`);
    }
  } catch (error) {
    console.log(`✗ Error: ${error}`);
  }

  console.log();

  // Example 3: Optimize from buffer with format selection
  console.log('=== Example 3: Format selection (WebP and AVIF only) ===');
  try {
    const inputData = await fs.promises.readFile('input.jpg');
    const result3 = await pyjamaz.optimizeImageFromBuffer(inputData, {
      formats: ['webp', 'avif'],
      maxBytes: 50_000,
    });

    if (result3.passed) {
      await result3.save(`output3.${result3.format}`);
      console.log(`✓ Optimized to ${result3.size.toLocaleString()} bytes as ${result3.format}`);
    } else {
      console.log(`✗ Failed: ${result3.errorMessage}`);
    }
  } catch (error) {
    console.log(`✗ Error: ${error}`);
  }

  console.log();

  // Example 4: Dual constraints (size + quality)
  console.log('=== Example 4: Dual constraints (size + quality) ===');
  try {
    const result4 = pyjamaz.optimizeImageSync('input.jpg', {
      maxBytes: 80_000,
      maxDiff: 0.001,
      metric: 'dssim',
    });

    if (result4.passed) {
      result4.saveSync('output4.jpg');
      console.log(`✓ Optimized to ${result4.size.toLocaleString()} bytes as ${result4.format}`);
      console.log(`  Quality score: ${result4.diffValue.toFixed(6)}`);
    } else {
      console.log(`✗ Failed: ${result4.errorMessage}`);
    }
  } catch (error) {
    console.log(`✗ Error: ${error}`);
  }

  console.log();

  // Example 5: Caching demonstration
  console.log('=== Example 5: Caching speedup ===');
  try {
    const options: pyjamaz.OptimizeOptions = {
      maxBytes: 100_000,
      cacheEnabled: true,
    };

    // First run (cache miss)
    const start1 = Date.now();
    const result5a = pyjamaz.optimizeImageSync('input.jpg', options);
    const time1 = Date.now() - start1;

    // Second run (cache hit)
    const start2 = Date.now();
    const result5b = pyjamaz.optimizeImageSync('input.jpg', options);
    const time2 = Date.now() - start2;

    console.log(`First run:  ${time1}ms (cache miss)`);
    console.log(`Second run: ${time2}ms (cache hit)`);
    console.log(`Speedup:    ${(time1 / time2).toFixed(1)}x faster`);
  } catch (error) {
    console.log(`✗ Error: ${error}`);
  }
}

// Run examples
main().catch(console.error);
