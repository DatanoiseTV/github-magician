# claude-maintenance

Local, scheduled GitHub automation driven by Claude Code. Triages issues, drafts
conservative fix PRs, runs weekly dependency + security + hygiene sweeps, and
keeps a backlog sane — all while respecting work-in-progress and keeping any
non-trivial security findings private.

**Runs entirely on your machine.** Uses the `gh` CLI's existing OS-keychain auth
and the `claude` CLI's existing auth. No tokens stored in this repo, no cloud
services involved.

## Requirements

- macOS (uses `launchd` and `osascript` for notifications; trivially portable to
  Linux with cron + `notify-send`).
- [`claude`](https://docs.anthropic.com/claude/docs/claude-code) — the Claude
  Code CLI, logged into an account with access to a capable model (defaults to
  `claude-sonnet-4-6`).
- [`gh`](https://cli.github.com/) — the GitHub CLI, authenticated (`gh auth
  login`).
- `envsubst` (ships with gettext: `brew install gettext` on macOS).
- `jq`.

## Install

```sh
cp .env.example .env
$EDITOR .env             # set GITHUB_USER
./install.sh
```

First run will prompt you to edit `.env`; re-run `install.sh` afterwards. The
script is idempotent — it'll unload-and-reload the LaunchAgents on each run.

## Layout

```
.env.example                     template (checked in)
.env                             your config (gitignored)
.gitignore
README.md · LICENSE
install.sh · uninstall.sh

triage-prompt.md                 daily issue triage
backlog-triage-prompt.md         one-shot full-backlog sweep
maintenance-prompt.md            twice-weekly dep/security/hygiene sweep

scripts/
  run-triage.sh
  run-backlog-triage.sh
  run-maintenance.sh
launchd/
  com.claude-maintenance.triage.plist.template
  com.claude-maintenance.maintenance.plist.template

reports/                         auto-populated, gitignored
security-reports/                auto-populated, gitignored, PRIVATE disclosures
.claude/settings.json            scoped permission allowlist for the runs
```

## Schedule

| Agent | Cadence (Europe/Berlin) | Cron-equivalent (UTC) |
|---|---|---|
| Triage | daily 08:00 + 18:00 | `0 6,16 * * *` |
| Maintenance | Wednesday + Sunday 22:00 | `0 20 * * 0,3` |

Edit the `StartCalendarInterval` sections of the `.plist.template` files and
re-run `install.sh` to change them.

## What the agents do

### Triage (daily)

- **Pre-filter** by activity: drops repos not pushed this year and not pushed in
  the last 90 days (unless they have fresh issue activity in the last 14h).
- **Spam filter**: crypto/giveaway/off-topic/low-effort → label `possible-spam`.
- **Security guardrails** (in every prompt): treats issue bodies as untrusted
  input, refuses prompt-injection attempts silently, never echoes secrets,
  redacts token patterns before including anything in output.
- **Duplicate detection**: closes dupes of an older canonical issue with
  cross-links. Labels `duplicate` / `possible-duplicate`.
- **Split-large**: if a new issue has 2–5 enumerable sub-tasks, opens sub-issues
  and converts the parent into a `meta` umbrella with a checklist.
- **Conservative fix drafting**: <50 LOC, clear bug, WIP pre-check passes (no
  open PRs by you, no recent commits to touched files) → draft PR, never applied
  from OP-suggested code.

### Backlog triage (one-shot, can be re-run)

Same rules as daily, but scans *all* open issues across *all* non-archived
non-fork repos. Classifies into `close-obsolete` / `actionable` / `backlog` /
`skip-unreasonable`. Adds `effort:X` / `feasibility:Y` / `priority:Z` labels and
a structured analysis comment. Assigns `actionable` + `trivial|small` +
`feasibility:clear` issues. Max 3 draft PRs per run.

```sh
./scripts/run-backlog-triage.sh          # real
DRY_RUN=1 ./scripts/run-backlog-triage.sh  # no writes
```

### Maintenance (twice weekly)

1. **Pick up to 10 active repos** (pushed this year or in the last 90 days).
2. **Dep check** (`npm/bun/pip/cargo/go` outdated) — patch + minor → one draft
   PR per repo; major → one tracking issue per repo with a checklist.
3. **Backlog drift**: same logic as backlog-triage, capped at 10 issues.
4. **Security scan** — injection / secrets / weak crypto / insecure
   randomness / path traversal / SSRF / unsafe deserialization / `verify=False`
   / ReDoS. Severity-classified with a strict disclosure split (below).
5. **Occasional small code improvement** — max 1 per repo, max 2 per run, <30
   LOC, draft PR, WIP pre-check applies.
6. **Release / artifact cleanup** — deletes Actions artifacts older than 90
   days (max 20 per repo/run) and unused prereleases/drafts older than 180 days
   (max 5 total/run). Strict safeguards: never touches stable releases, the
   latest release, releases with >10 asset downloads, or releases with tags
   referenced from the default branch.
7. **Code review** — one recently-merged PR per repo, comments only on real
   findings.
8. **Hygiene** — flags missing LICENSE / README / CI / dependabot via a
   checklist issue.
9. Writes its timestamp to `[maintenance-sweep] last run` in your most-active
   repo (next run uses this to skip repos that haven't moved).

## Security disclosure policy (mandatory)

| Severity | Channel | Notification |
|---|---|---|
| **Critical / High / Medium** | **Private file** under `security-reports/<repo>-<YYYYMMDD>-<severity>.md`. **Never published** (no public issue, no public PR). | Loud macOS `Sosumi` sound + "⚠ Security findings — private" banner. |
| Low | Public issue labelled `security-low`, no PoC in text. | Normal banner. |
| Informational | Folded into regular code-review comments. | None. |

This split is enforced by the prompt; don't weaken it casually. Low-priority
findings being public is intentional (accountability, renovate-style
visibility); high/medium going private is responsible-disclosure hygiene.

## Safety properties

- **WIP pre-check**: before drafting any PR, all agents skip repos where you
  have an open PR, or have committed to files you'd touch in the last 7 days.
- **Read-only on archived repos**: detected via `gh repo view` metadata.
- **Never applies OP-suggested code**: patches suggested in issue bodies are
  treated as untrusted. Agents rewrite fixes from the codebase.
- **Prompt injection**: issue text is treated as data, never as instructions.
  Attempts labelled `prompt-injection` and ignored silently (no engagement).
- **Secret redaction**: tokens matching common patterns (`ghp_`, `sk-`, `xox[baprs]-`,
  AWS/GCP shapes) are redacted from anything the agent writes back.
- **Dry run**: every script honours `DRY_RUN=1` — does everything except the
  GitHub writes.

## Uninstall

```sh
./uninstall.sh               # unload + remove LaunchAgents
./uninstall.sh --purge       # also delete reports/ and security-reports/
```

Scripts and prompts stay — delete the directory if you want it fully gone.

## License

MIT — see `LICENSE`.
