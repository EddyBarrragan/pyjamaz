"""
Batch processing example for Pyjamaz.
"""

import pyjamaz
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor, as_completed
import time

def optimize_single_image(input_path: Path, output_dir: Path, max_bytes: int):
    """Optimize a single image."""
    try:
        result = pyjamaz.optimize_image(
            str(input_path),
            max_bytes=max_bytes,
            metric='ssimulacra2',
            cache_enabled=True,  # Use cache for speed
        )

        if result.passed:
            output_path = output_dir / f"{input_path.stem}_optimized.{result.format}"
            result.save(output_path)

            original_size = input_path.stat().st_size
            reduction = (1 - result.size / original_size) * 100

            return {
                'success': True,
                'input': input_path.name,
                'output': output_path.name,
                'original_size': original_size,
                'optimized_size': result.size,
                'reduction': reduction,
                'format': result.format,
                'quality': result.diff_value,
            }
        else:
            return {
                'success': False,
                'input': input_path.name,
                'error': result.error_message,
            }
    except Exception as e:
        return {
            'success': False,
            'input': input_path.name,
            'error': str(e),
        }

def main():
    # Configuration
    input_dir = Path('images')
    output_dir = Path('optimized')
    max_bytes = 100_000  # 100KB target
    max_workers = 4  # Parallel workers

    # Create output directory
    output_dir.mkdir(exist_ok=True)

    # Find all images
    image_extensions = {'.jpg', '.jpeg', '.png', '.webp'}
    images = [f for f in input_dir.iterdir() if f.suffix.lower() in image_extensions]

    print(f"Found {len(images)} images to optimize")
    print(f"Target size: {max_bytes:,} bytes")
    print(f"Using {max_workers} parallel workers")
    print()

    # Process images in parallel
    start_time = time.time()
    results = []

    with ThreadPoolExecutor(max_workers=max_workers) as executor:
        # Submit all tasks
        future_to_image = {
            executor.submit(optimize_single_image, img, output_dir, max_bytes): img
            for img in images
        }

        # Collect results as they complete
        for future in as_completed(future_to_image):
            result = future.result()
            results.append(result)

            if result['success']:
                print(f"✓ {result['input']}: "
                      f"{result['original_size']:,} → {result['optimized_size']:,} bytes "
                      f"({result['reduction']:.1f}% reduction)")
            else:
                print(f"✗ {result['input']}: {result['error']}")

    elapsed = time.time() - start_time

    # Print summary
    successful = [r for r in results if r['success']]
    failed = [r for r in results if not r['success']]

    print(f"\n{'='*60}")
    print(f"Processed {len(images)} images in {elapsed:.2f}s")
    print(f"Success: {len(successful)}, Failed: {len(failed)}")

    if successful:
        total_original = sum(r['original_size'] for r in successful)
        total_optimized = sum(r['optimized_size'] for r in successful)
        total_reduction = (1 - total_optimized / total_original) * 100

        print(f"\nTotal size: {total_original:,} → {total_optimized:,} bytes")
        print(f"Total reduction: {total_reduction:.1f}%")
        print(f"Average per image: {elapsed/len(images):.3f}s")

if __name__ == '__main__':
    main()
