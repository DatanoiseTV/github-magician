#!/usr/bin/env bash
# Install LaunchAgents for claude-maintenance. Idempotent.
# Usage:
#   ./install.sh            # uses existing .env
#   GITHUB_USER=foo ./install.sh  # one-shot install
set -euo pipefail

JOB_DIR="$(cd "$(dirname "$0")" && pwd)"
TEMPLATE_DIR="$JOB_DIR/launchd"
LAUNCH_DIR="$HOME/Library/LaunchAgents"

# --- .env setup ---------------------------------------------------------
if [ ! -f "$JOB_DIR/.env" ] && [ -z "${GITHUB_USER:-}" ]; then
  cp "$JOB_DIR/.env.example" "$JOB_DIR/.env"
  echo "Created $JOB_DIR/.env from .env.example."
  echo "Edit it to set GITHUB_USER, then re-run this script."
  exit 1
fi
if [ -f "$JOB_DIR/.env" ]; then
  set -a; . "$JOB_DIR/.env"; set +a
fi
: "${GITHUB_USER:?GITHUB_USER must be set}"

if ! command -v envsubst >/dev/null 2>&1; then
  echo "envsubst missing. Install gettext: brew install gettext (macOS) or apt install gettext (Linux)" >&2
  exit 1
fi
if ! command -v gh >/dev/null 2>&1; then
  echo "gh CLI missing. https://cli.github.com" >&2
  exit 1
fi
if ! gh auth status >/dev/null 2>&1; then
  echo "gh not authenticated. Run: gh auth login" >&2
  exit 1
fi
if ! command -v claude >/dev/null 2>&1; then
  echo "claude CLI missing. https://docs.anthropic.com/claude/docs/claude-code" >&2
  exit 1
fi

# --- Prepare runtime dirs ----------------------------------------------
mkdir -p "$JOB_DIR/reports" "$JOB_DIR/security-reports" "$LAUNCH_DIR"
chmod +x "$JOB_DIR/scripts/"*.sh

# --- Generate and install LaunchAgents ----------------------------------
for tpl in "$TEMPLATE_DIR"/*.plist.template; do
  name="$(basename "$tpl" .template)"
  target="$LAUNCH_DIR/$name"
  echo "Installing $name..."
  envsubst '${HOME}' < "$tpl" > "$target"

  # Unload if already loaded (ignore "not loaded" errors).
  launchctl unload "$target" 2>/dev/null || true
  launchctl load "$target"
done

echo
echo "Installed. Verify:"
echo "  launchctl list | grep claude-maintenance"
echo "Test (no GitHub writes):"
echo "  DRY_RUN=1 $JOB_DIR/scripts/run-triage.sh && cat $JOB_DIR/reports/triage-*.md | tail -30"
echo
echo "Schedule (Europe/Berlin local time):"
echo "  Triage:       daily 08:00 + 18:00"
echo "  Maintenance:  Wednesday + Sunday 22:00"
