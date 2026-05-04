#!/bin/bash
set -euo pipefail

# LocalStack can recursively discover .sh files under init directories.
# If this helper is picked up there, skip it to avoid init failures.

if [[ -n "${LOCALSTACK_HOSTNAME:-}" || -n "${LOCALSTACK_RUNTIME_ID:-}" ]]; then
	echo "[build] skipping helper script in LocalStack init context"
	exit 0
fi

if ! command -v dotnet >/dev/null 2>&1; then
	echo "[build] dotnet not available; skipping helper script"
	exit 0
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_DIR="/tmp/lambda-authorizer-build"
ZIP_FILE="$OUTPUT_DIR/function.zip"

echo "[build] Cleaning previous build..."
rm -rf "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR"

echo "[build] Publishing Lambda function..."
cd "$SCRIPT_DIR"
dotnet publish -c Release -o "$OUTPUT_DIR/publish" --self-contained false

echo "[build] Creating deployment package..."
cd "$OUTPUT_DIR/publish"
zip -r "$ZIP_FILE" . > /dev/null 2>&1

echo "[build] Lambda function packaged: $ZIP_FILE"
ls -lh "$ZIP_FILE"

exit 0
