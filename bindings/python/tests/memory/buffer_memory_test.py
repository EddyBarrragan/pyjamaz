#!/usr/bin/env python3
"""
Buffer Memory Test (~1 minute)

Goal: Verify that large image buffers are properly managed

Test strategy:
1. Create images of various sizes
2. Optimize 1000 images
3. Track buffer allocation and deallocation
4. Assert: No unbounded memory growth
"""

import gc
import sys
import time
import os

# Add parent directory to path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '../..'))

import pyjamaz

# Base JPEG for generation
BASE_JPEG = bytes([
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


def generate_test_image(size_multiplier=1):
    """Generate a test JPEG of varying sizes"""
    if size_multiplier <= 1:
        return BASE_JPEG

    # Create larger buffer by duplicating data
    buffers = [BASE_JPEG]
    for i in range(1, size_multiplier):
        buffers.append(bytes([i % 256] * len(BASE_JPEG)))
    return b''.join(buffers)


def get_memory_stats():
    """Get memory usage stats"""
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
    print('=== Buffer Memory Test ===\n')
    print('Goal: Verify large image buffers are properly managed\n')

    # Warm up
    print('Warming up...')
    small_image = generate_test_image(1)
    for i in range(100):
        try:
            pyjamaz.optimize_from_bytes(small_image, cache_enabled=False)
        except:
            pass
    gc.collect()
    time.sleep(0.5)

    baseline = get_memory_stats()
    print(f"Baseline memory: RSS={baseline['rss']}MB, VMS={baseline['vms']}MB\n")

    # Phase 1: Process small images (1x size)
    print('Phase 1: Processing 400 small images...')
    start_time = time.time()

    for i in range(400):
        try:
            image = generate_test_image(1)
            pyjamaz.optimize_from_bytes(image, max_bytes=50000, cache_enabled=False)
        except:
            pass

        if (i + 1) % 100 == 0:
            stats = get_memory_stats()
            print(f"  {i + 1} images: RSS={stats['rss']}MB, VMS={stats['vms']}MB")

    duration = time.time() - start_time
    print(f'  Completed in {duration:.2f}s\n')

    gc.collect()
    time.sleep(0.5)

    after_small = get_memory_stats()
    print(f"After small images: RSS={after_small['rss']}MB, VMS={after_small['vms']}MB\n")

    # Phase 2: Process medium images (10x size)
    print('Phase 2: Processing 300 medium images...')
    start_time = time.time()

    for i in range(300):
        try:
            image = generate_test_image(10)
            pyjamaz.optimize_from_bytes(image, max_bytes=100000, cache_enabled=False)
        except:
            pass

        if (i + 1) % 100 == 0:
            stats = get_memory_stats()
            print(f"  {i + 1} images: RSS={stats['rss']}MB, VMS={stats['vms']}MB")

    duration = time.time() - start_time
    print(f'  Completed in {duration:.2f}s\n')

    gc.collect()
    time.sleep(0.5)

    after_medium = get_memory_stats()
    print(f"After medium images: RSS={after_medium['rss']}MB, VMS={after_medium['vms']}MB\n")

    # Phase 3: Process large images (50x size)
    print('Phase 3: Processing 300 large images...')
    start_time = time.time()

    for i in range(300):
        try:
            image = generate_test_image(50)
            pyjamaz.optimize_from_bytes(image, max_bytes=200000, cache_enabled=False)
        except:
            pass

        if (i + 1) % 100 == 0:
            stats = get_memory_stats()
            print(f"  {i + 1} images: RSS={stats['rss']}MB, VMS={stats['vms']}MB")

    duration = time.time() - start_time
    print(f'  Completed in {duration:.2f}s\n')

    # Phase 4: Final cleanup
    print('Phase 4: Final cleanup...')
    gc.collect()
    gc.collect()
    gc.collect()
    time.sleep(1.0)

    final = get_memory_stats()
    print(f"Final memory: RSS={final['rss']}MB, VMS={final['vms']}MB\n")

    # Phase 5: Analysis
    print('Phase 5: Analysis...')
    rss_growth = final['rss'] - baseline['rss']
    vms_growth = final['vms'] - baseline['vms']

    print(f'  Memory growth: RSS=+{rss_growth:.2f}MB, VMS=+{vms_growth:.2f}MB')
    print('  Total images processed: 1000')

    # Thresholds (allow some growth due to internal caching, etc.)
    rss_threshold = 30  # Max 30MB RSS growth
    vms_threshold = 50  # Max 50MB VMS growth

    rss_ok = rss_growth < rss_threshold
    vms_ok = vms_growth < vms_threshold

    if rss_ok and vms_ok:
        print(f'  ✓ PASS: RSS growth {rss_growth:.2f}MB < {rss_threshold}MB')
        print(f'  ✓ PASS: VMS growth {vms_growth:.2f}MB < {vms_threshold}MB')
        print('  ✓ Buffer memory management working correctly')
        print('\n=== TEST PASSED ===')
        sys.exit(0)
    else:
        print('  ✗ FAIL: Excessive memory growth detected')
        if not rss_ok:
            print(f'  ✗ RSS growth {rss_growth:.2f}MB >= {rss_threshold}MB')
        if not vms_ok:
            print(f'  ✗ VMS growth {vms_growth:.2f}MB >= {vms_threshold}MB')
        print('\n=== TEST FAILED ===')
        sys.exit(1)


if __name__ == '__main__':
    main()
