#!/usr/bin/env bash
#
# Download conformance test suites for Pyjamaz
#
# Usage: ./scripts/download_testdata.sh [--force]
#
# This script downloads standard image test suites used for conformance testing.
# Downloaded files go to testdata/conformance/
#
# Options:
#   --force    Re-download even if files exist

set -euo pipefail

TESTDATA_DIR="testdata/conformance"
TOTAL_SIZE_ESTIMATE="~200 MB"
FORCE_DOWNLOAD=false

# Parse arguments
for arg in "$@"; do
  case $arg in
    --force)
      FORCE_DOWNLOAD=true
      shift
      ;;
  esac
done

echo "=== Pyjamaz Conformance Test Suite Downloader ==="
echo ""
echo "This will download ${TOTAL_SIZE_ESTIMATE} of test images to ${TESTDATA_DIR}/"
if [ "$FORCE_DOWNLOAD" = true ]; then
  echo "Mode: Force re-download (existing files will be overwritten)"
fi
echo "Press Ctrl+C to cancel, or Enter to continue..."
read -r

mkdir -p "$TESTDATA_DIR"

# Track success/failures/skipped
declare -i SUCCESS=0
declare -i FAILED=0
declare -i SKIPPED=0

# Helper: Download file with retry
download_file() {
  local url="$1"
  local output="$2"
  local max_retries=3
  local retry=0

  while [ $retry -lt $max_retries ]; do
    if curl -f -L --retry 2 --retry-delay 1 -o "$output" "$url" 2>/dev/null; then
      return 0
    fi
    retry=$((retry + 1))
    [ $retry -lt $max_retries ] && sleep 1
  done
  return 1
}

# Kodak Image Suite (24 images, ~5MB)
echo ""
echo "→ Downloading Kodak Image Suite (24 images, ~5MB)"
mkdir -p "$TESTDATA_DIR/kodak"
for i in $(seq -f "%02g" 1 24); do
  OUTPUT="$TESTDATA_DIR/kodak/kodim$i.png"

  if [ -f "$OUTPUT" ] && [ "$FORCE_DOWNLOAD" = false ]; then
    echo "  ⊘ kodim$i.png (already exists)"
    SKIPPED=$((SKIPPED + 1))
    continue
  fi

  URL="http://r0k.us/graphics/kodak/kodak/kodim$i.png"
  if download_file "$URL" "$OUTPUT"; then
    echo "  ✓ kodim$i.png"
    SUCCESS=$((SUCCESS + 1))
  else
    echo "  ✗ kodim$i.png (failed)"
    FAILED=$((FAILED + 1))
  fi
done

# PngSuite (edge cases, ~2MB)
echo ""
echo "→ Downloading PNG Suite (edge cases, ~2MB)"
mkdir -p "$TESTDATA_DIR/pngsuite"
PNGSUITE_TAR="$TESTDATA_DIR/pngsuite.tar.gz"

# Check if already downloaded
if [ -d "$TESTDATA_DIR/pngsuite" ] && [ "$(find "$TESTDATA_DIR/pngsuite" -name "*.png" | wc -l)" -gt 0 ] && [ "$FORCE_DOWNLOAD" = false ]; then
  COUNT=$(find "$TESTDATA_DIR/pngsuite" -name "*.png" | wc -l | xargs)
  echo "  ⊘ PNG Suite already downloaded ($COUNT files)"
  SKIPPED=$((SKIPPED + COUNT))
else
  PNGSUITE_URL="http://www.schaik.com/pngsuite/PngSuite-2017jul19.tgz"
  if download_file "$PNGSUITE_URL" "$PNGSUITE_TAR"; then
    tar -xzf "$PNGSUITE_TAR" -C "$TESTDATA_DIR/pngsuite" 2>/dev/null || true
    rm "$PNGSUITE_TAR"
    COUNT=$(find "$TESTDATA_DIR/pngsuite" -name "*.png" | wc -l | xargs)
    echo "  ✓ Extracted $COUNT PNG files"
    SUCCESS=$((SUCCESS + COUNT))
  else
    echo "  ✗ PNG Suite download failed"
    FAILED=$((FAILED + 1))
  fi
fi

# WebP Gallery (sample images, ~5MB)
echo ""
echo "→ Downloading WebP Gallery (sample images, ~5MB)"
mkdir -p "$TESTDATA_DIR/webp"
WEBP_URLS=(
  "https://www.gstatic.com/webp/gallery/1.webp"
  "https://www.gstatic.com/webp/gallery/2.webp"
  "https://www.gstatic.com/webp/gallery/3.webp"
  "https://www.gstatic.com/webp/gallery/4.webp"
  "https://www.gstatic.com/webp/gallery/5.webp"
)
for url in "${WEBP_URLS[@]}"; do
  FILENAME=$(basename "$url")
  OUTPUT="$TESTDATA_DIR/webp/$FILENAME"

  if [ -f "$OUTPUT" ] && [ "$FORCE_DOWNLOAD" = false ]; then
    echo "  ⊘ $FILENAME (already exists)"
    SKIPPED=$((SKIPPED + 1))
    continue
  fi

  if download_file "$url" "$OUTPUT"; then
    echo "  ✓ $FILENAME"
    SUCCESS=$((SUCCESS + 1))
  else
    echo "  ✗ $FILENAME (failed)"
    FAILED=$((FAILED + 1))
  fi
done

# JPEG Test Suite (diverse JPEG samples, ~10MB)
echo ""
echo "→ Downloading JPEG Test Samples (~10MB)"
mkdir -p "$TESTDATA_DIR/jpeg"

# Tecnick JPEG test images
JPEG_SAMPLES=(
  "https://filesamples.com/samples/image/jpg/sample_640%C3%97426.jpg:sample_640x426.jpg"
  "https://filesamples.com/samples/image/jpg/sample_1920%C3%971280.jpg:sample_1920x1280.jpg"
  "https://filesamples.com/samples/image/jpg/sample_1280%C3%97853.jpg:sample_1280x853.jpg"
)

for entry in "${JPEG_SAMPLES[@]}"; do
  IFS=':' read -r url filename <<< "$entry"
  OUTPUT="$TESTDATA_DIR/jpeg/$filename"

  if [ -f "$OUTPUT" ] && [ "$FORCE_DOWNLOAD" = false ]; then
    echo "  ⊘ $filename (already exists)"
    SKIPPED=$((SKIPPED + 1))
    continue
  fi

  if download_file "$url" "$OUTPUT"; then
    echo "  ✓ $filename"
    SUCCESS=$((SUCCESS + 1))
  else
    echo "  ✗ $filename (failed)"
    FAILED=$((FAILED + 1))
  fi
done

# Sample Images (various formats, ~15MB)
echo ""
echo "→ Downloading Sample Images (various formats, ~15MB)"
mkdir -p "$TESTDATA_DIR/samples"

SAMPLE_IMAGES=(
  "https://raw.githubusercontent.com/image-rs/image-png/main/tests/pngsuite/basi0g01.png:basi0g01.png"
  "https://raw.githubusercontent.com/image-rs/image-png/main/tests/pngsuite/basi0g02.png:basi0g02.png"
  "https://raw.githubusercontent.com/image-rs/image-png/main/tests/pngsuite/basi0g04.png:basi0g04.png"
  "https://raw.githubusercontent.com/image-rs/image-png/main/tests/pngsuite/basi0g08.png:basi0g08.png"
  "https://raw.githubusercontent.com/image-rs/image-png/main/tests/pngsuite/basi2c08.png:basi2c08.png"
)

for entry in "${SAMPLE_IMAGES[@]}"; do
  IFS=':' read -r url filename <<< "$entry"
  OUTPUT="$TESTDATA_DIR/samples/$filename"

  if [ -f "$OUTPUT" ] && [ "$FORCE_DOWNLOAD" = false ]; then
    echo "  ⊘ $filename (already exists)"
    SKIPPED=$((SKIPPED + 1))
    continue
  fi

  if download_file "$url" "$OUTPUT"; then
    echo "  ✓ $filename"
    SUCCESS=$((SUCCESS + 1))
  else
    echo "  ✗ $filename (failed - source may have moved)"
    FAILED=$((FAILED + 1))
  fi
done

# Summary
echo ""
echo "=== Download Summary ==="
echo "Successful: $SUCCESS files"
echo "Skipped:    $SKIPPED files (already exist)"
echo "Failed:     $FAILED downloads"
echo ""

# Calculate total size
if command -v du &> /dev/null; then
  TOTAL_SIZE=$(du -sh "$TESTDATA_DIR" 2>/dev/null | cut -f1)
  echo "Total size: $TOTAL_SIZE"
fi

# Count files per suite
echo ""
echo "=== Test Suite Breakdown ==="
for suite in kodak pngsuite webp jpeg samples; do
  if [ -d "$TESTDATA_DIR/$suite" ]; then
    COUNT=$(find "$TESTDATA_DIR/$suite" -type f \( -name "*.png" -o -name "*.jpg" -o -name "*.jpeg" -o -name "*.webp" \) 2>/dev/null | wc -l | xargs)
    echo "  $suite: $COUNT images"
  fi
done

echo ""
echo "Test suites downloaded to: $TESTDATA_DIR/"
echo ""
if [ $FAILED -gt 0 ]; then
  echo "⚠️  Some downloads failed. This is often due to:"
  echo "   - Network issues (try again later)"
  echo "   - Source URLs moved (images may no longer be available)"
  echo "   - Rate limiting (wait a few minutes and retry)"
  echo ""
  echo "Tip: Run with --force to retry failed downloads"
fi
echo "To run conformance tests:"
echo "  zig build conformance"
echo ""
echo "To re-download all files:"
echo "  ./scripts/download_testdata.sh --force"

exit 0
