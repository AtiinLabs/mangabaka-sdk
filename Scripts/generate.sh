#!/bin/sh
# Regenerates Sources/MangaBakaSDK/Generated from OpenAPI/openapi.json.
# The generated client is checked in so that apps using the SDK do not build the generator.
# Set SWIFT to choose the toolchain, for example SWIFT="xcrun swift".
set -eu
cd "$(dirname "$0")/.."

output=Sources/MangaBakaSDK/Generated
rm -rf "$output"
mkdir -p "$output"
${SWIFT:-swift} run --package-path Scripts/Generator swift-openapi-generator generate \
    --config OpenAPI/openapi-generator-config.yaml \
    --output-directory "$output" \
    OpenAPI/openapi.json
