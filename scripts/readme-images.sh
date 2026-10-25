#!/usr/bin/env bash
# Regenerates docs/images/ from the faces the app actually renders.
set -euo pipefail
cd "$(dirname "$0")/.."
scripts/test.sh --filter writesPreviews > /dev/null
mkdir -p docs/images
swift scripts/readme-images.swift .build/previews docs/images
