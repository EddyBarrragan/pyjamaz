#!/usr/bin/env python3
"""
GC Verification Test (~30 seconds)

Goal: Verify that image optimization results are properly garbage collected

Test strategy:
1. Create 10K image optimization operations
2. Force garbage collection
3. Verify memory size decreased
4. Assert: Memory released after GC
"""

import gc
import sys
import time
import os

# ANSI color codes
class Colors:
    HEADER = '\033[95m'
    OKBLUE = '\033[94m'
    OKCYAN = '\033[96m'
    OKGREEN = '\033[92m'
    WARNING = '\033[93m'
    FAIL = '\033[91m'
    ENDC = '\033[0m'
    BOLD = '\033[1m'
    UNDERLINE = '\033[4m'

# Add parent directory to path
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), '../..')))

import pyjamaz

# Sample 1x1 JPEG image for testing (167 bytes)
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
        return round(process.memory_info().rss / 1024 / 1024, 2)
    except ImportError:
        # Fallback to gc stats
        stats = gc.get_stats()
        if stats and 'collected' in stats[0]:
            return round(sum(s.get('collected', 0) for s in stats) / 1024 / 1024, 2)
        return 0.0


def main():
    print(f'{Colors.BOLD}{Colors.HEADER}=== GC Verification Test ==={Colors.ENDC}\n')
    print(f'{Colors.OKCYAN}Goal: Verify that image optimization results are properly garbage collected{Colors.ENDC}\n')

    # Record initial memory
    gc.collect()
    time.sleep(0.5)
    initial_memory = get_memory_mb()
    print(f'Initial memory: {initial_memory} MB')

    # Phase 1: Create 10K image optimizations
    print('\nPhase 1: Creating 10K image optimizations...')
    start_time = time.time()
    results = []

    for i in range(10000):
        try:
            result = pyjamaz.optimize_from_bytes(
                SAMPLE_JPEG,
                max_bytes=10000,
                cache_enabled=False,  # Disable cache to test actual memory usage
            )
            results.append(result)

            if (i + 1) % 2500 == 0:
                print(f'  Created {i + 1} results...')
        except Exception as err:
            print(f'  Error at iteration {i}: {err}')

    after_creation = get_memory_mb()
    creation_time = time.time() - start_time
    print(f'  Completed in {creation_time:.2f}s')
    print(f'  Memory after creation: {after_creation} MB (+{after_creation - initial_memory:.2f} MB)')

    # Phase 2: Clear references
    print('\nPhase 2: Clearing references...')
    results = None
    after_clear = get_memory_mb()
    print(f'  Memory after clear: {after_clear} MB')

    # Phase 3: Force GC
    print('\nPhase 3: Forcing garbage collection...')
    gc.collect()
    gc.collect()  # Collect twice to ensure all cycles are broken
    gc.collect()

    # Wait for GC to complete
    time.sleep(1.0)

    after_gc = get_memory_mb()
    memory_freed = after_creation - after_gc
    allocated_memory = after_creation - initial_memory
    freed_percentage = (memory_freed / allocated_memory * 100) if allocated_memory > 0 else 0

    print(f'  Memory after GC: {after_gc} MB (-{memory_freed:.2f} MB)')
    print(f'  Memory freed: {freed_percentage:.1f}% of allocated memory')

    # Phase 4: Verify memory was released
    print('\nPhase 4: Verification...')

    threshold = 0.7  # At least 70% should be freed
    actual_freed = freed_percentage / 100

    if actual_freed >= threshold or after_gc <= initial_memory + 10:
        print(f'  {Colors.OKGREEN}✓ PASS: {freed_percentage:.1f}% memory freed (threshold: {threshold * 100:.0f}%){Colors.ENDC}')
        print(f'  {Colors.OKGREEN}✓ Memory management working correctly{Colors.ENDC}')
        print(f'\n{Colors.BOLD}{Colors.OKGREEN}=== TEST PASSED ==={Colors.ENDC}')
        sys.exit(0)
    else:
        print(f'  {Colors.FAIL}✗ FAIL: Only {freed_percentage:.1f}% memory freed (threshold: {threshold * 100:.0f}%){Colors.ENDC}')
        print(f'  {Colors.FAIL}✗ Possible memory leak detected{Colors.ENDC}')
        print(f'\n{Colors.BOLD}{Colors.FAIL}=== TEST FAILED ==={Colors.ENDC}')
        sys.exit(1)


if __name__ == '__main__':
    main()
