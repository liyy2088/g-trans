#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
OUT_DIR="$ROOT_DIR/.local/diagnostics"
STAMP="$(date +%Y%m%d-%H%M%S)"
TARGET_DIR="$OUT_DIR/$STAMP"
LOG_DIR="$HOME/Library/Application Support/GTrans/Logs"
REPORT_DIR="$HOME/Library/Logs/DiagnosticReports"

mkdir -p "$TARGET_DIR"

if [ -d "$LOG_DIR" ]; then
  cp -R "$LOG_DIR" "$TARGET_DIR/app-logs"
fi

if [ -d "$REPORT_DIR" ]; then
  find "$REPORT_DIR" \
    -maxdepth 1 \
    \( -name 'GTrans*.ips' -o -name 'GTrans*.crash' -o -name 'G-Trans*.ips' -o -name 'G-Trans*.crash' \) \
    -mtime -14 \
    -print0 | while IFS= read -r -d '' report; do
      cp "$report" "$TARGET_DIR/"
    done
fi

cat > "$TARGET_DIR/README.txt" <<EOF
G-Trans diagnostics collected at $STAMP

Included when present:
- app-logs/gtrans.log
- app-logs/gtrans.previous.log
- recent macOS crash reports from ~/Library/Logs/DiagnosticReports

If there was a crash, inspect the newest .ips or .crash file first, then match its timestamp with app-logs/gtrans.log.
EOF

echo "$TARGET_DIR"
