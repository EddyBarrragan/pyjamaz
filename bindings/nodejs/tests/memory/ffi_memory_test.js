/**
 * FFI Memory Test (~30 seconds)
 *
 * Goal: Verify that native memory from FFI calls is properly cleaned up
 *
 * Test strategy:
 * 1. Track process RSS (Resident Set Size) memory
 * 2. Create 5K image optimizations
 * 3. Measure native memory growth
 * 4. Assert: Native memory stable after cleanup
 */

const pyjamaz = require('../../src/index');

// Sample 1x1 JPEG image
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
 * Get RSS memory in MB
 */
function getRssMB() {
  const usage = process.memoryUsage();
  return (usage.rss / 1024 / 1024).toFixed(2);
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
  console.log('=== FFI Memory Test ===\n');
  console.log('Goal: Verify native memory from FFI calls is properly cleaned up\n');

  // Warm up
  console.log('Warming up...');
  for (let i = 0; i < 100; i++) {
    pyjamaz.optimizeImageFromBufferSync(SAMPLE_JPEG, {
      maxBytes: 10000,
      cacheEnabled: false,
    });
  }
  tryForceGC();
  await new Promise(resolve => setTimeout(resolve, 500));

  // Record baseline
  const baselineRss = parseFloat(getRssMB());
  console.log(`Baseline RSS: ${baselineRss} MB\n`);

  // Phase 1: Create 5K optimizations and track memory
  console.log('Phase 1: Creating 5K optimizations...');
  const startTime = Date.now();
  const memorySnapshots = [];

  for (let i = 0; i < 5000; i++) {
    pyjamaz.optimizeImageFromBufferSync(SAMPLE_JPEG, {
      maxBytes: 10000,
      cacheEnabled: false,
    });

    // Take memory snapshots every 500 iterations
    if ((i + 1) % 500 === 0) {
      const currentRss = parseFloat(getRssMB());
      memorySnapshots.push({
        iteration: i + 1,
        rss: currentRss,
        delta: (currentRss - baselineRss).toFixed(2),
      });
      console.log(`  Iteration ${i + 1}: RSS = ${currentRss} MB (+${memorySnapshots[memorySnapshots.length - 1].delta} MB)`);
    }
  }

  const duration = ((Date.now() - startTime) / 1000).toFixed(2);
  console.log(`  Completed in ${duration}s\n`);

  // Phase 2: Force GC and wait
  console.log('Phase 2: Forcing cleanup...');
  tryForceGC();
  await new Promise(resolve => setTimeout(resolve, 1000));

  const afterCleanup = parseFloat(getRssMB());
  const cleanupDelta = (afterCleanup - baselineRss).toFixed(2);
  console.log(`  RSS after cleanup: ${afterCleanup} MB (+${cleanupDelta} MB from baseline)\n`);

  // Phase 3: Analyze memory growth
  console.log('Phase 3: Analysis...');

  // Calculate memory growth rate
  const firstSnapshot = memorySnapshots[0];
  const lastSnapshot = memorySnapshots[memorySnapshots.length - 1];
  const totalGrowth = parseFloat(lastSnapshot.delta) - parseFloat(firstSnapshot.delta);
  const growthRate = (totalGrowth / (lastSnapshot.iteration - firstSnapshot.iteration) * 1000).toFixed(4);

  console.log(`  Memory growth: ${totalGrowth.toFixed(2)} MB over ${lastSnapshot.iteration - firstSnapshot.iteration} iterations`);
  console.log(`  Growth rate: ${growthRate} MB per 1000 operations`);

  // Check if memory is stable (growth rate < 0.5 MB per 1000 ops)
  const threshold = 0.5;
  const finalDelta = parseFloat(cleanupDelta);

  if (parseFloat(growthRate) < threshold && finalDelta < 50) {
    console.log(`  ✓ PASS: Memory stable (growth rate: ${growthRate} MB/1000 ops < ${threshold})`);
    console.log(`  ✓ Final overhead: ${finalDelta} MB (acceptable)`);
    console.log('\n=== TEST PASSED ===');
    process.exit(0);
  } else {
    console.error(`  ✗ FAIL: Memory leak detected`);
    console.error(`  ✗ Growth rate: ${growthRate} MB/1000 ops (threshold: ${threshold})`);
    console.error(`  ✗ Final overhead: ${finalDelta} MB`);
    console.error('\n=== TEST FAILED ===');
    process.exit(1);
  }
}

// Run the test
runTest().catch(err => {
  console.error('Test error:', err);
  process.exit(1);
});
