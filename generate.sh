#!/bin/bash

CONTRACT_PATH="src/MudraToken.sol"
REPORT_DIR="audit-reports"

mkdir -p "$REPORT_DIR"

echo "🧹 Cleaning up..."
forge clean

echo "🛠️ Running Slither detectors (JSON)..."
slither "$CONTRACT_PATH" --json "$REPORT_DIR/slither-report.json"

echo "🧾 Running full detector output (text)..."
slither "$CONTRACT_PATH" > "$REPORT_DIR/full-detector-output.txt"

echo "📄 Running human-readable summary..."
slither "$CONTRACT_PATH" --print human-summary > "$REPORT_DIR/human-summary.txt"

echo ""
echo "✅ All reports generated in: $REPORT_DIR/"
echo "  - slither-report.json"
echo "  - full-detector-output.txt"
echo "  - human-summary.txt"
