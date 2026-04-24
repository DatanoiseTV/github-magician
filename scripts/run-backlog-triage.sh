#!/usr/bin/env bash
# One-shot full-backlog triage. Same shape as run-triage.sh but different prompt.
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
REPORT="$REPORT_DIR/backlog-triage-$STAMP.md"
LOG="$REPORT_DIR/backlog-triage-$STAMP.log"

PROMPT_FILE="$JOB_DIR/backlog-triage-prompt.md"
[ -f "$PROMPT_FILE" ] || { echo "Missing $PROMPT_FILE" >&2; exit 1; }

if ! gh auth status >/dev/null 2>&1; then
  echo "$(date) gh auth failed — aborting backlog triage" >&2
  osascript -e 'display notification "gh auth failed — backlog triage aborted" with title "GitHub Backlog" sound name "Basso"' 2>/dev/null || true
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

if grep -qiE "(monthly usage limit|usage limit|out of .* credits|quota.*(exceed|exhaust))" "$REPORT" 2>/dev/null; then
  mv "$REPORT" "${REPORT%.md}.quota-skip.md"
  osascript -e "display notification \"Claude quota exhausted — backlog triage skipped.\" with title \"⚠ Claude quota\" sound name \"Basso\"" 2>/dev/null || true
  exit 2
fi

if [ "$EXIT" -ne 0 ]; then
  osascript -e "display notification \"Exit $EXIT — see $(basename "$LOG")\" with title \"Backlog triage failed\" sound name \"Basso\"" 2>/dev/null || true
  exit "$EXIT"
fi

if [ -s "$REPORT" ]; then
  SUMMARY="$(grep -E '^## (Actionable|Backlog|Closed)' "$REPORT" | tr '\n' ' ' | head -c 120)"
  [ -z "$SUMMARY" ] && SUMMARY="see $(basename "$REPORT")"
  osascript -e "display notification \"$SUMMARY\" with title \"Backlog triage — $(basename "$REPORT")\"" 2>/dev/null || true
fi

# Clean up leftover clones. Bash redirects here aren't inside the claude session,
# so they run with full shell perms (not subject to Claude Code deny rules).
rm -rf /tmp/backlog-* /tmp/triage-* 2>/dev/null || true

exit 0
