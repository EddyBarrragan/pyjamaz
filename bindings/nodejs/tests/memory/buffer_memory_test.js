/**
 * Buffer Memory Test (~1 minute)
 *
 * Goal: Verify that large image buffers are properly managed
 *
 * Test strategy:
 * 1. Create images of various sizes
 * 2. Optimize 1000 images
 * 3. Track buffer allocation and deallocation
 * 4. Assert: No unbounded memory growth
 */

const pyjamaz = require('../../src/index');

// Generate a larger test JPEG (still small but larger than 1x1)
function generateTestImage(sizeMultiplier = 1) {
  // Base JPEG header + data
  const base = Buffer.from([
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

  // Create a larger buffer by duplicating data
  if (sizeMultiplier <= 1) return base;

  const buffers = [base];
  for (let i = 1; i < sizeMultiplier; i++) {
    buffers.push(Buffer.alloc(base.length, i % 256));
  }
  return Buffer.concat(buffers);
}

/**
 * Get memory usage stats
 */
function getMemoryStats() {
  const usage = process.memoryUsage();
  return {
    heapUsed: (usage.heapUsed / 1024 / 1024).toFixed(2),
    heapTotal: (usage.heapTotal / 1024 / 1024).toFixed(2),
    rss: (usage.rss / 1024 / 1024).toFixed(2),
    external: (usage.external / 1024 / 1024).toFixed(2),
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
  console.log('=== Buffer Memory Test ===\n');
  console.log('Goal: Verify large image buffers are properly managed\n');

  // Warm up
  console.log('Warming up...');
  const smallImage = generateTestImage(1);
  for (let i = 0; i < 100; i++) {
    try {
      pyjamaz.optimizeImageFromBufferSync(smallImage, { cacheEnabled: false });
    } catch (err) {
      // May fail, that's ok for warmup
    }
  }
  tryForceGC();
  await new Promise(resolve => setTimeout(resolve, 500));

  const baseline = getMemoryStats();
  console.log(`Baseline memory:`);
  console.log(`  Heap: ${baseline.heapUsed}/${baseline.heapTotal} MB`);
  console.log(`  RSS: ${baseline.rss} MB`);
  console.log(`  External: ${baseline.external} MB\n`);

  // Phase 1: Process small images (1x size)
  console.log('Phase 1: Processing 400 small images...');
  let startTime = Date.now();

  for (let i = 0; i < 400; i++) {
    try {
      const image = generateTestImage(1);
      pyjamaz.optimizeImageFromBufferSync(image, {
        maxBytes: 50000,
        cacheEnabled: false,
      });
    } catch (err) {
      // Ignore errors
    }

    if ((i + 1) % 100 === 0) {
      const stats = getMemoryStats();
      console.log(`  ${i + 1} images: Heap=${stats.heapUsed}MB, RSS=${stats.rss}MB, Ext=${stats.external}MB`);
    }
  }

  let duration = ((Date.now() - startTime) / 1000).toFixed(2);
  console.log(`  Completed in ${duration}s\n`);

  tryForceGC();
  await new Promise(resolve => setTimeout(resolve, 500));

  const afterSmall = getMemoryStats();
  console.log(`After small images: Heap=${afterSmall.heapUsed}MB, RSS=${afterSmall.rss}MB\n`);

  // Phase 2: Process medium images (10x size)
  console.log('Phase 2: Processing 300 medium images...');
  startTime = Date.now();

  for (let i = 0; i < 300; i++) {
    try {
      const image = generateTestImage(10);
      pyjamaz.optimizeImageFromBufferSync(image, {
        maxBytes: 100000,
        cacheEnabled: false,
      });
    } catch (err) {
      // Ignore errors
    }

    if ((i + 1) % 100 === 0) {
      const stats = getMemoryStats();
      console.log(`  ${i + 1} images: Heap=${stats.heapUsed}MB, RSS=${stats.rss}MB, Ext=${stats.external}MB`);
    }
  }

  duration = ((Date.now() - startTime) / 1000).toFixed(2);
  console.log(`  Completed in ${duration}s\n`);

  tryForceGC();
  await new Promise(resolve => setTimeout(resolve, 500));

  const afterMedium = getMemoryStats();
  console.log(`After medium images: Heap=${afterMedium.heapUsed}MB, RSS=${afterMedium.rss}MB\n`);

  // Phase 3: Process large images (50x size)
  console.log('Phase 3: Processing 300 large images...');
  startTime = Date.now();

  for (let i = 0; i < 300; i++) {
    try {
      const image = generateTestImage(50);
      pyjamaz.optimizeImageFromBufferSync(image, {
        maxBytes: 200000,
        cacheEnabled: false,
      });
    } catch (err) {
      // Ignore errors
    }

    if ((i + 1) % 100 === 0) {
      const stats = getMemoryStats();
      console.log(`  ${i + 1} images: Heap=${stats.heapUsed}MB, RSS=${stats.rss}MB, Ext=${stats.external}MB`);
    }
  }

  duration = ((Date.now() - startTime) / 1000).toFixed(2);
  console.log(`  Completed in ${duration}s\n`);

  // Phase 4: Final cleanup
  console.log('Phase 4: Final cleanup...');
  tryForceGC();
  await new Promise(resolve => setTimeout(resolve, 1000));

  const final = getMemoryStats();
  console.log(`Final memory: Heap=${final.heapUsed}MB, RSS=${final.rss}MB\n`);

  // Phase 5: Analysis
  console.log('Phase 5: Analysis...');
  const heapGrowth = (parseFloat(final.heapUsed) - parseFloat(baseline.heapUsed)).toFixed(2);
  const rssGrowth = (parseFloat(final.rss) - parseFloat(baseline.rss)).toFixed(2);

  console.log(`  Memory growth: Heap=+${heapGrowth}MB, RSS=+${rssGrowth}MB`);
  console.log(`  Total images processed: 1000`);

  // Thresholds (allow some growth due to internal caching, etc.)
  const heapThreshold = 30; // Max 30MB heap growth
  const rssThreshold = 50; // Max 50MB RSS growth

  const heapOk = parseFloat(heapGrowth) < heapThreshold;
  const rssOk = parseFloat(rssGrowth) < rssThreshold;

  if (heapOk && rssOk) {
    console.log(`  ✓ PASS: Heap growth ${heapGrowth}MB < ${heapThreshold}MB`);
    console.log(`  ✓ PASS: RSS growth ${rssGrowth}MB < ${rssThreshold}MB`);
    console.log(`  ✓ Buffer memory management working correctly`);
    console.log('\n=== TEST PASSED ===');
    process.exit(0);
  } else {
    console.error(`  ✗ FAIL: Excessive memory growth detected`);
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
