/**
 * GC Verification Test (~30 seconds)
 *
 * Goal: Verify that image optimization results are properly garbage collected
 *
 * Test strategy:
 * 1. Create 10K image optimization operations
 * 2. Force garbage collection
 * 3. Verify heap size decreased
 * 4. Assert: Memory released after GC
 */

const pyjamaz = require('../../src/index');

// Sample 1x1 JPEG image for testing (167 bytes)
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
 * Force garbage collection (requires --expose-gc flag)
 */
function forceGC() {
  if (global.gc) {
    global.gc();
    return true;
  }
  console.warn('WARNING: Garbage collection not exposed. Run with: node --expose-gc');
  return false;
}

/**
 * Get current heap usage in MB
 */
function getHeapUsedMB() {
  const usage = process.memoryUsage();
  return (usage.heapUsed / 1024 / 1024).toFixed(2);
}

/**
 * Main test function
 */
async function runTest() {
  console.log('=== GC Verification Test ===\n');
  console.log('Goal: Verify that image optimization results are properly garbage collected\n');

  // Record initial heap size
  const initialHeap = getHeapUsedMB();
  console.log(`Initial heap: ${initialHeap} MB`);

  // Phase 1: Create 10K image optimizations
  console.log('\nPhase 1: Creating 10K image optimizations...');
  const startTime = Date.now();
  let results = [];

  for (let i = 0; i < 10000; i++) {
    try {
      const result = pyjamaz.optimizeImageFromBufferSync(SAMPLE_JPEG, {
        maxBytes: 10000,
        cacheEnabled: false, // Disable cache to test actual memory usage
      });
      results.push(result);

      if ((i + 1) % 2500 === 0) {
        console.log(`  Created ${i + 1} results...`);
      }
    } catch (err) {
      console.error(`  Error at iteration ${i}:`, err.message);
    }
  }

  const afterCreation = getHeapUsedMB();
  const creationTime = ((Date.now() - startTime) / 1000).toFixed(2);
  console.log(`  Completed in ${creationTime}s`);
  console.log(`  Heap after creation: ${afterCreation} MB (+${(afterCreation - initialHeap).toFixed(2)} MB)`);

  // Phase 2: Clear references
  console.log('\nPhase 2: Clearing references...');
  results = null;
  const afterClear = getHeapUsedMB();
  console.log(`  Heap after clear: ${afterClear} MB`);

  // Phase 3: Force GC
  console.log('\nPhase 3: Forcing garbage collection...');
  const gcSuccess = forceGC();

  if (!gcSuccess) {
    console.error('\nFAILED: Cannot force GC. Rerun with: node --expose-gc gc_verification_test.js');
    process.exit(1);
  }

  // Wait for GC to complete
  await new Promise(resolve => setTimeout(resolve, 1000));

  const afterGC = getHeapUsedMB();
  const memoryFreed = (afterCreation - afterGC).toFixed(2);
  const freedPercentage = ((memoryFreed / (afterCreation - initialHeap)) * 100).toFixed(1);

  console.log(`  Heap after GC: ${afterGC} MB (-${memoryFreed} MB)`);
  console.log(`  Memory freed: ${freedPercentage}% of allocated memory`);

  // Phase 4: Verify memory was released
  console.log('\nPhase 4: Verification...');

  const threshold = 0.7; // At least 70% should be freed
  const actualFreed = parseFloat(freedPercentage) / 100;

  if (actualFreed >= threshold) {
    console.log(`  ✓ PASS: ${freedPercentage}% memory freed (threshold: ${(threshold * 100)}%)`);
    console.log(`  ✓ Memory management working correctly`);
    console.log('\n=== TEST PASSED ===');
    process.exit(0);
  } else {
    console.error(`  ✗ FAIL: Only ${freedPercentage}% memory freed (threshold: ${(threshold * 100)}%)`);
    console.error(`  ✗ Possible memory leak detected`);
    console.error('\n=== TEST FAILED ===');
    process.exit(1);
  }
}

// Run the test
runTest().catch(err => {
  console.error('Test error:', err);
  process.exit(1);
});
