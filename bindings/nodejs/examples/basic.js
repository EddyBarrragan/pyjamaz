/**
 * Basic usage examples for Pyjamaz Node.js bindings (JavaScript)
 */

const pyjamaz = require('../dist/index');
const fs = require('fs').promises;

async function main() {
  console.log(`Pyjamaz version: ${pyjamaz.getVersion()}\n`);

  // Example 1: Simple optimization with size constraint
  console.log('=== Example 1: Size constraint ===');
  try {
    const result1 = await pyjamaz.optimizeImage('input.jpg', {
      maxBytes: 100000,
    });

    if (result1.passed) {
      await result1.save('output1.jpg');
      console.log(`✓ Optimized to ${result1.size.toLocaleString()} bytes as ${result1.format}`);
    } else {
      console.log(`✗ Failed: ${result1.errorMessage}`);
    }
  } catch (error) {
    console.log(`✗ Error: ${error.message}`);
  }

  console.log();

  // Example 2: Optimize with quality constraint
  console.log('=== Example 2: Quality constraint ===');
  try {
    const result2 = await pyjamaz.optimizeImage('input.png', {
      maxDiff: 0.002,
      metric: 'dssim',
    });

    if (result2.passed) {
      await result2.save('output2.png');
      console.log(`✓ Optimized to ${result2.size.toLocaleString()} bytes`);
      console.log(`  Quality score: ${result2.diffValue.toFixed(6)}`);
    } else {
      console.log(`✗ Failed: ${result2.errorMessage}`);
    }
  } catch (error) {
    console.log(`✗ Error: ${error.message}`);
  }

  console.log();

  // Example 3: Try modern formats
  console.log('=== Example 3: Modern formats (WebP, AVIF) ===');
  try {
    const result3 = await pyjamaz.optimizeImage('input.jpg', {
      formats: ['webp', 'avif'],
      maxBytes: 50000,
    });

    if (result3.passed) {
      await result3.save(`output3.${result3.format}`);
      console.log(`✓ Best format: ${result3.format}`);
      console.log(`  Size: ${result3.size.toLocaleString()} bytes`);
    } else {
      console.log(`✗ Failed: ${result3.errorMessage}`);
    }
  } catch (error) {
    console.log(`✗ Error: ${error.message}`);
  }

  console.log();

  // Example 4: Synchronous optimization
  console.log('=== Example 4: Synchronous optimization ===');
  try {
    const result4 = pyjamaz.optimizeImageSync('input.jpg', {
      maxBytes: 80000,
      metric: 'none',
    });

    if (result4.passed) {
      result4.saveSync('output4.jpg');
      console.log(`✓ Optimized synchronously: ${result4.size.toLocaleString()} bytes`);
    } else {
      console.log(`✗ Failed: ${result4.errorMessage}`);
    }
  } catch (error) {
    console.log(`✗ Error: ${error.message}`);
  }

  console.log();

  // Example 5: Optimize from buffer
  console.log('=== Example 5: Optimize from buffer ===');
  try {
    const inputData = await fs.readFile('input.jpg');

    const result5 = await pyjamaz.optimizeImageFromBuffer(inputData, {
      maxBytes: 100000,
    });

    if (result5.passed) {
      // Write buffer directly
      await fs.writeFile('output5.jpg', result5.data);
      console.log(`✓ Optimized from buffer: ${result5.size.toLocaleString()} bytes`);
    } else {
      console.log(`✗ Failed: ${result5.errorMessage}`);
    }
  } catch (error) {
    console.log(`✗ Error: ${error.message}`);
  }
}

// Run examples
main().catch(console.error);
