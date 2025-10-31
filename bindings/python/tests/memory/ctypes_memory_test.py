#!/usr/bin/env python3
"""
CTypes Memory Test (~30 seconds)

Goal: Verify that native memory from ctypes calls is properly cleaned up

Test strategy:
1. Track process RSS (Resident Set Size) memory
2. Create 5K image optimizations
3. Measure native memory growth
4. Assert: Native memory stable after cleanup
"""

import gc
import sys
import time
import os

# Add parent directory to path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '../..'))

import pyjamaz

# Sample 1x1 JPEG image
SAMPLE_JPEG = bytes([
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
])


def get_rss_mb():
    """Get RSS memory in MB"""
    try:
        import psutil
        process = psutil.Process()
        return round(process.memory_info().rss / 1024 / 1024, 2)
    except ImportError:
        # Fallback to /proc/self/status on Linux
        try:
            with open('/proc/self/status') as f:
                for line in f:
                    if line.startswith('VmRSS:'):
                        return round(int(line.split()[1]) / 1024, 2)
        except:
            pass
        return 0.0


def main():
    print('=== CTypes Memory Test ===\n')
    print('Goal: Verify native memory from ctypes calls is properly cleaned up\n')

    # Warm up
    print('Warming up...')
    for i in range(100):
        pyjamaz.optimize_from_bytes(SAMPLE_JPEG, max_bytes=10000, cache_enabled=False)
    gc.collect()
    time.sleep(0.5)

    # Record baseline
    baseline_rss = get_rss_mb()
    print(f'Baseline RSS: {baseline_rss} MB\n')

    # Phase 1: Create 5K optimizations and track memory
    print('Phase 1: Creating 5K optimizations...')
    start_time = time.time()
    memory_snapshots = []

    for i in range(5000):
        pyjamaz.optimize_from_bytes(SAMPLE_JPEG, max_bytes=10000, cache_enabled=False)

        # Take memory snapshots every 500 iterations
        if (i + 1) % 500 == 0:
            current_rss = get_rss_mb()
            delta = current_rss - baseline_rss
            memory_snapshots.append({
                'iteration': i + 1,
                'rss': current_rss,
                'delta': delta,
            })
            print(f'  Iteration {i + 1}: RSS = {current_rss} MB (+{delta:.2f} MB)')

    duration = time.time() - start_time
    print(f'  Completed in {duration:.2f}s\n')

    # Phase 2: Force GC and wait
    print('Phase 2: Forcing cleanup...')
    gc.collect()
    gc.collect()
    gc.collect()
    time.sleep(1.0)

    after_cleanup = get_rss_mb()
    cleanup_delta = after_cleanup - baseline_rss
    print(f'  RSS after cleanup: {after_cleanup} MB (+{cleanup_delta:.2f} MB from baseline)\n')

    # Phase 3: Analyze memory growth
    print('Phase 3: Analysis...')

    # Calculate memory growth rate
    first_snapshot = memory_snapshots[0]
    last_snapshot = memory_snapshots[-1]
    total_growth = last_snapshot['delta'] - first_snapshot['delta']
    growth_rate = (total_growth / (last_snapshot['iteration'] - first_snapshot['iteration']) * 1000)

    print(f"  Memory growth: {total_growth:.2f} MB over {last_snapshot['iteration'] - first_snapshot['iteration']} iterations")
    print(f'  Growth rate: {growth_rate:.4f} MB per 1000 operations')

    # Check if memory is stable (growth rate < 0.5 MB per 1000 ops)
    threshold = 0.5

    if growth_rate < threshold and cleanup_delta < 50:
        print(f'  ✓ PASS: Memory stable (growth rate: {growth_rate:.4f} MB/1000 ops < {threshold})')
        print(f'  ✓ Final overhead: {cleanup_delta:.2f} MB (acceptable)')
        print('\n=== TEST PASSED ===')
        sys.exit(0)
    else:
        print('  ✗ FAIL: Memory leak detected')
        print(f'  ✗ Growth rate: {growth_rate:.4f} MB/1000 ops (threshold: {threshold})')
        print(f'  ✗ Final overhead: {cleanup_delta:.2f} MB')
        print('\n=== TEST FAILED ===')
        sys.exit(1)


if __name__ == '__main__':
    main()
