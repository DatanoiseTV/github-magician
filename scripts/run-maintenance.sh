#!/usr/bin/env bash
# Cron-driven weekly maintenance sweep. Same shape as run-triage.sh.
set -uo pipefail

export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
: "${HOME:?HOME must be set}"

if [ -f "$HOME/.claude/cron-jobs/.env" ]; then
  set -a; . "$HOME/.claude/cron-jobs/.env"; set +a
fi
: "${GITHUB_USER:?GITHUB_USER must be set in ~/.claude/cron-jobs/.env (see .env.example)}"

JOB_DIR="$HOME/.claude/cron-jobs"
REPORT_DIR="$JOB_DIR/reports"
mkdir -p "$REPORT_DIR"
STAMP="$(date +%Y%m%d-%H%M%S)"
REPORT="$REPORT_DIR/maintenance-$STAMP.md"
LOG="$REPORT_DIR/maintenance-$STAMP.log"

PROMPT_FILE="$JOB_DIR/maintenance-prompt.md"
[ -f "$PROMPT_FILE" ] || { echo "Missing $PROMPT_FILE" >&2; exit 1; }

if ! gh auth status >/dev/null 2>&1; then
  echo "$(date) gh auth failed — aborting maintenance" >&2
  osascript -e 'display notification "gh auth failed — maintenance aborted" with title "GitHub Maintenance" sound name "Basso"' 2>/dev/null || true
  exit 1
fi

PROMPT="$(envsubst '${GITHUB_USER}' < "$PROMPT_FILE")"
[ "${DRY_RUN:-0}" = "1" ] && PROMPT="DRY_RUN=1 (do not write anything to GitHub)

$PROMPT"

cd "$JOB_DIR"

claude -p "$PROMPT" \
  --model claude-sonnet-4-6 \
  --permission-mode acceptEdits \
  > "$REPORT" 2>"$LOG"
EXIT=$?

if [ "$EXIT" -ne 0 ]; then
  osascript -e "display notification \"Exit $EXIT — see $(basename "$LOG")\" with title \"GitHub Maintenance failed\" sound name \"Basso\"" 2>/dev/null || true
  exit "$EXIT"
fi

if [ -s "$REPORT" ]; then
  SUMMARY="$(grep -E '^Repos processed' "$REPORT" | head -c 120)"
  [ -z "$SUMMARY" ] && SUMMARY="see $(basename "$REPORT")"
  osascript -e "display notification \"$SUMMARY\" with title \"GitHub Maintenance — $(basename "$REPORT")\"" 2>/dev/null || true
fi

# Security disclosure: if this run produced any private high/medium/critical findings,
# post a LOUD notification with a distinctive sound. These files are the only channel —
# they are never pushed to GitHub per the maintenance-prompt disclosure policy.
TODAY="$(date +%Y%m%d)"
SEC_FILES=$(find "$HOME/.claude/cron-jobs/security-reports" -name "*-${TODAY}-*.md" 2>/dev/null | grep -vE '(-low-|-informational-)' | head -20)
if [ -n "$SEC_FILES" ]; then
  COUNT=$(echo "$SEC_FILES" | wc -l | tr -d ' ')
  osascript -e "display notification \"$COUNT high/medium security finding(s) — check ~/.claude/cron-jobs/security-reports/\" with title \"⚠ Security findings — private\" sound name \"Sosumi\"" 2>/dev/null || true
fi

# Always clean up any leftover clones.
rm -rf /tmp/maint-* /tmp/triage-* 2>/dev/null || true

exit 0
