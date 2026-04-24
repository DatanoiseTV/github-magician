#!/usr/bin/env bash
# Unload and remove the LaunchAgents. Does NOT touch reports/ or security-reports/.
# Pass --purge to also delete those directories.
set -euo pipefail

LAUNCH_DIR="$HOME/Library/LaunchAgents"
JOB_DIR="$(cd "$(dirname "$0")" && pwd)"

for plist in "$LAUNCH_DIR"/com.claude-maintenance.*.plist; do
  [ -f "$plist" ] || continue
  echo "Removing $(basename "$plist")..."
  launchctl unload "$plist" 2>/dev/null || true
  rm -f "$plist"
done

if [ "${1:-}" = "--purge" ]; then
  rm -rf "$JOB_DIR/reports" "$JOB_DIR/security-reports"
  echo "Purged reports/ and security-reports/."
fi

echo "Done. Scripts and prompts remain at $JOB_DIR — delete manually if you want them gone."
