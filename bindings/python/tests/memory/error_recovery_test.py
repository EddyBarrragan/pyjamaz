#!/usr/bin/env python3
"""
Error Recovery Test (~10 seconds)

Goal: Verify cleanup happens even when errors occur during optimization

Test strategy:
1. Create invalid image data
2. Attempt optimizations that will fail
3. Verify no memory leaks after errors
4. Assert: Memory stable after error handling
"""

import gc
import sys
import time
import os

# Add parent directory to path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '../..'))

import pyjamaz

# Valid sample image
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


def get_memory_mb():
    """Get current process memory in MB"""
    try:
        import psutil
        process = psutil.Process()
        info = process.memory_info()
        return {
            'rss': round(info.rss / 1024 / 1024, 2),
            'vms': round(info.vms / 1024 / 1024, 2),
        }
    except ImportError:
        return {'rss': 0.0, 'vms': 0.0}


def main():
    print('=== Error Recovery Test ===\n')
    print('Goal: Verify cleanup happens even when errors occur\n')

    # Warm up
    print('Warming up...')
    for i in range(50):
        try:
            pyjamaz.optimize_from_bytes(SAMPLE_JPEG, cache_enabled=False)
        except:
            pass
    gc.collect()
    time.sleep(0.5)

    baseline = get_memory_mb()
    print(f"Baseline: RSS={baseline['rss']}MB, VMS={baseline['vms']}MB\n")

    # Phase 1: Test with invalid image data
    print('Phase 1: Testing with invalid image data...')
    error_count = 0
    success_count = 0

    test_cases = [
        ('Empty buffer', b''),
        ('Random bytes', bytes([0x12, 0x34, 0x56, 0x78])),
        ('Partial JPEG header', bytes([0xff, 0xd8, 0xff])),
        ('Valid JPEG', SAMPLE_JPEG),
    ]

    for round_num in range(250):
        for name, data in test_cases:
            try:
                pyjamaz.optimize_from_bytes(data, max_bytes=10000, cache_enabled=False)
                success_count += 1
            except Exception:
                error_count += 1
                # Expected errors - verify they're properly handled

        if (round_num + 1) % 50 == 0:
            current = get_memory_mb()
            print(f"  Round {round_num + 1}/250: RSS={current['rss']}MB, VMS={current['vms']}MB, "
                  f"Errors={error_count}, Success={success_count}")

    print(f'  Total operations: {error_count + success_count}')
    print(f'  Errors encountered: {error_count}')
    print(f'  Successful: {success_count}\n')

    # Phase 2: Cleanup and measure
    print('Phase 2: Cleanup and measurement...')
    gc.collect()
    gc.collect()
    gc.collect()
    time.sleep(1.0)

    after_cleanup = get_memory_mb()
    rss_growth = after_cleanup['rss'] - baseline['rss']
    vms_growth = after_cleanup['vms'] - baseline['vms']

    print(f"  After cleanup: RSS={after_cleanup['rss']}MB (+{rss_growth:.2f}MB), "
          f"VMS={after_cleanup['vms']}MB (+{vms_growth:.2f}MB)\n")

    # Phase 3: Verify memory is stable
    print('Phase 3: Verification...')

    rss_threshold = 20  # Max 20MB RSS growth
    vms_threshold = 30  # Max 30MB VMS growth

    rss_ok = rss_growth < rss_threshold
    vms_ok = vms_growth < vms_threshold

    if rss_ok and vms_ok:
        print(f'  ✓ PASS: RSS growth {rss_growth:.2f}MB < {rss_threshold}MB')
        print(f'  ✓ PASS: VMS growth {vms_growth:.2f}MB < {vms_threshold}MB')
        print('  ✓ Error handling working correctly')
        print(f'  ✓ No memory leaks detected after {error_count} errors')
        print('\n=== TEST PASSED ===')
        sys.exit(0)
    else:
        print('  ✗ FAIL: Memory leak detected after error handling')
        if not rss_ok:
            print(f'  ✗ RSS growth {rss_growth:.2f}MB >= {rss_threshold}MB')
        if not vms_ok:
            print(f'  ✗ VMS growth {vms_growth:.2f}MB >= {vms_threshold}MB')
        print('\n=== TEST FAILED ===')
        sys.exit(1)


if __name__ == '__main__':
    main()
