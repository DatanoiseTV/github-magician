#!/usr/bin/env bash
# Cron-driven GitHub issue triage. Runs claude headless, writes a timestamped
# report, and posts a macOS notification on completion. Set DRY_RUN=1 to test.
set -uo pipefail

# Cron has a minimal PATH — load the user's Homebrew, mise, and ~/.local/bin.
export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
: "${HOME:?HOME must be set}"

# Load config (GITHUB_USER, any other env). .env is gitignored.
if [ -f "$HOME/.claude/cron-jobs/.env" ]; then
  set -a; . "$HOME/.claude/cron-jobs/.env"; set +a
fi
: "${GITHUB_USER:?GITHUB_USER must be set in ~/.claude/cron-jobs/.env (see .env.example)}"

JOB_DIR="$HOME/.claude/cron-jobs"
REPORT_DIR="$JOB_DIR/reports"
mkdir -p "$REPORT_DIR"
STAMP="$(date +%Y%m%d-%H%M%S)"
REPORT="$REPORT_DIR/triage-$STAMP.md"
LOG="$REPORT_DIR/triage-$STAMP.log"

PROMPT_FILE="$JOB_DIR/triage-prompt.md"
[ -f "$PROMPT_FILE" ] || { echo "Missing $PROMPT_FILE" >&2; exit 1; }

# Verify gh auth is alive before burning tokens.
if ! gh auth status >/dev/null 2>&1; then
  echo "$(date) gh auth failed — aborting triage" >&2
  osascript -e 'display notification "gh auth failed — triage aborted" with title "GitHub Triage" sound name "Basso"' 2>/dev/null || true
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

# Detect Claude usage-limit exhaustion: the CLI emits a short message to stdout
# and exits non-zero. Rename the report so it doesn't look like a real run,
# and notify distinctly — quota is a temporary "will retry next fire" issue,
# not a bug in the script or the prompt.
if grep -qiE "(monthly usage limit|usage limit|out of .* credits|quota.*(exceed|exhaust))" "$REPORT" 2>/dev/null; then
  mv "$REPORT" "${REPORT%.md}.quota-skip.md"
  osascript -e "display notification \"Claude quota exhausted — triage skipped. Will retry at next fire.\" with title \"⚠ Claude quota\" sound name \"Basso\"" 2>/dev/null || true
  exit 2
fi

if [ "$EXIT" -ne 0 ]; then
  osascript -e "display notification \"Exit $EXIT — see $(basename "$LOG")\" with title \"GitHub Triage failed\" sound name \"Basso\"" 2>/dev/null || true
  exit "$EXIT"
fi

# Notify only if the report has real content (not just "All clear").
if [ -s "$REPORT" ] && ! grep -q "^All clear" "$REPORT"; then
  SUMMARY="$(grep -E '^Security flags|^PRs drafted' "$REPORT" | tr '\n' ' ' | head -c 120)"
  osascript -e "display notification \"$SUMMARY\" with title \"GitHub Triage — $(basename "$REPORT")\"" 2>/dev/null || true
fi

exit 0
