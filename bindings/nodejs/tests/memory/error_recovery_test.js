/**
 * Error Recovery Test (~10 seconds)
 *
 * Goal: Verify cleanup happens even when errors occur during optimization
 *
 * Test strategy:
 * 1. Create invalid image data
 * 2. Attempt optimizations that will fail
 * 3. Verify no memory leaks after errors
 * 4. Assert: Memory stable after error handling
 */

const pyjamaz = require('../../src/index');

// Valid sample image
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

/**
 * Get heap and RSS memory in MB
 */
function getMemoryMB() {
  const usage = process.memoryUsage();
  return {
    heap: (usage.heapUsed / 1024 / 1024).toFixed(2),
    rss: (usage.rss / 1024 / 1024).toFixed(2),
  };
}

/**
 * Force GC if available
 */
function tryForceGC() {
  if (global.gc) {
    global.gc();
  }
}

/**
 * Main test function
 */
async function runTest() {
  console.log('=== Error Recovery Test ===\n');
  console.log('Goal: Verify cleanup happens even when errors occur\n');

  // Warm up
  console.log('Warming up...');
  for (let i = 0; i < 50; i++) {
    try {
      pyjamaz.optimizeImageFromBufferSync(SAMPLE_JPEG, { cacheEnabled: false });
    } catch (err) {
      // Ignore
    }
  }
  tryForceGC();
  await new Promise(resolve => setTimeout(resolve, 500));

  const baseline = getMemoryMB();
  console.log(`Baseline: Heap=${baseline.heap}MB, RSS=${baseline.rss}MB\n`);

  // Phase 1: Test with invalid image data
  console.log('Phase 1: Testing with invalid image data...');
  let errorCount = 0;
  let successCount = 0;

  const testCases = [
    { name: 'Empty buffer', data: Buffer.alloc(0) },
    { name: 'Random bytes', data: Buffer.from([0x12, 0x34, 0x56, 0x78]) },
    { name: 'Partial JPEG header', data: Buffer.from([0xff, 0xd8, 0xff]) },
    { name: 'Valid JPEG', data: SAMPLE_JPEG },
  ];

  for (let round = 0; round < 250; round++) {
    for (const testCase of testCases) {
      try {
        pyjamaz.optimizeImageFromBufferSync(testCase.data, {
          maxBytes: 10000,
          cacheEnabled: false,
        });
        successCount++;
      } catch (err) {
        errorCount++;
        // Expected errors - verify they're properly handled
      }
    }

    if ((round + 1) % 50 === 0) {
      const current = getMemoryMB();
      console.log(`  Round ${round + 1}/250: Heap=${current.heap}MB, RSS=${current.rss}MB, Errors=${errorCount}, Success=${successCount}`);
    }
  }

  console.log(`  Total operations: ${errorCount + successCount}`);
  console.log(`  Errors encountered: ${errorCount}`);
  console.log(`  Successful: ${successCount}\n`);

  // Phase 2: Cleanup and measure
  console.log('Phase 2: Cleanup and measurement...');
  tryForceGC();
  await new Promise(resolve => setTimeout(resolve, 1000));

  const afterCleanup = getMemoryMB();
  const heapGrowth = (parseFloat(afterCleanup.heap) - parseFloat(baseline.heap)).toFixed(2);
  const rssGrowth = (parseFloat(afterCleanup.rss) - parseFloat(baseline.rss)).toFixed(2);

  console.log(`  After cleanup: Heap=${afterCleanup.heap}MB (+${heapGrowth}MB), RSS=${afterCleanup.rss}MB (+${rssGrowth}MB)\n`);

  // Phase 3: Verify memory is stable
  console.log('Phase 3: Verification...');

  const heapThreshold = 10; // Max 10MB heap growth
  const rssThreshold = 20; // Max 20MB RSS growth

  const heapOk = parseFloat(heapGrowth) < heapThreshold;
  const rssOk = parseFloat(rssGrowth) < rssThreshold;

  if (heapOk && rssOk) {
    console.log(`  ✓ PASS: Heap growth ${heapGrowth}MB < ${heapThreshold}MB`);
    console.log(`  ✓ PASS: RSS growth ${rssGrowth}MB < ${rssThreshold}MB`);
    console.log(`  ✓ Error handling working correctly`);
    console.log(`  ✓ No memory leaks detected after ${errorCount} errors`);
    console.log('\n=== TEST PASSED ===');
    process.exit(0);
  } else {
    console.error(`  ✗ FAIL: Memory leak detected after error handling`);
    if (!heapOk) console.error(`  ✗ Heap growth ${heapGrowth}MB >= ${heapThreshold}MB`);
    if (!rssOk) console.error(`  ✗ RSS growth ${rssGrowth}MB >= ${rssThreshold}MB`);
    console.error('\n=== TEST FAILED ===');
    process.exit(1);
  }
}

// Run the test
runTest().catch(err => {
  console.error('Test error:', err);
  process.exit(1);
});
