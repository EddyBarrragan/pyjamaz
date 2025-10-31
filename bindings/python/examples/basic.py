"""
Basic example of using Pyjamaz Python bindings.
"""

import pyjamaz
from pathlib import Path

def main():
    # Get version
    print(f"Pyjamaz version: {pyjamaz.get_version()}")

    # Example 1: Optimize with size constraint
    print("\n=== Example 1: Size Constraint ===")
    result = pyjamaz.optimize_image(
        'input.jpg',
        max_bytes=100_000,  # 100KB max
        metric='ssimulacra2',
    )

    if result.passed:
        result.save('output_100kb.jpg')
        print(f"✓ Optimized to {result.size:,} bytes as {result.format}")
        print(f"  Quality score: {result.diff_value:.6f}")
    else:
        print(f"✗ Optimization failed: {result.error_message}")

    # Example 2: Optimize with quality constraint
    print("\n=== Example 2: Quality Constraint ===")
    result = pyjamaz.optimize_image(
        'input.png',
        max_diff=0.002,  # Very high quality
        metric='dssim',
        formats=['webp', 'avif'],  # Try modern formats
    )

    if result.passed:
        result.save(f'output.{result.format}')
        print(f"✓ Saved as {result.format}: {result.size:,} bytes")
        print(f"  Quality score: {result.diff_value:.6f}")
    else:
        print(f"✗ Failed: {result.error_message}")

    # Example 3: Optimize from bytes
    print("\n=== Example 3: From Bytes ===")
    with open('input.jpg', 'rb') as f:
        image_data = f.read()

    result = pyjamaz.optimize_image(
        image_data,
        max_bytes=50_000,
        formats=['jpeg', 'webp'],
    )

    if result.passed:
        with open('output_50kb.webp', 'wb') as f:
            f.write(result.output_buffer)
        print(f"✓ Optimized {len(image_data):,} → {result.size:,} bytes")
        reduction = (1 - result.size / len(image_data)) * 100
        print(f"  Reduction: {reduction:.1f}%")

if __name__ == '__main__':
    main()
