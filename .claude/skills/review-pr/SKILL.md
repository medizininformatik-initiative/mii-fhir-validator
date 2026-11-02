---
name: review-pr
description: Review a mii-fhir-validator pull request against AGENTS.md — fetch the PR, its diff and CI checks, and report findings ranked by severity. Never posts comments or reviews without asking. Use when the user says "review PR #N", "look at this PR", or pastes a PR URL.
---

# Review PR

1. **Collect.**
   - `gh pr view <n> --comments` — intent, linked issue, discussion, base branch.
   - `gh pr diff <n>` — the change.
   - `gh pr checks <n>` — CI status. For a failed check, read its log with
     `gh run view <run-id> --log-failed` before judging the code.
2. **Review against AGENTS.md.** Check in particular:
   - Sync points: `IG_LIST` ↔ `.env.default` `IG_PARAMS` ↔ `docs/overview.md`; image tag in both
     validator services and the docs; new env vars in entrypoint, both compose services,
     `.env.default`, `README.md`, `docs/configuration.md`.
   - Entrypoint: still POSIX `sh`, fails fast with `exit 1` on bad config, no secrets echoed,
     `JAVA_TOOL_OPTIONS`/`fhir-settings.json` built correctly for http and https.
   - Compose: `ontoserver` and `blaze` profiles both still valid (`make lint-compose`).
   - Sync points that `make check-sync` cannot see: prose in `docs/overview.md`, README.
   - Tests: an entrypoint, runner or hook case, or a `.github/test-resources/` resource for
     behavior changes; entrypoint cases assert the exact message, not just a non-zero exit.
   - Base branch is `develop` (unless it is a release/merge PR into `main`), Conventional
     Commit title.
   - Secrets: no certificates, keys, tokens or `.env` content in the diff.
3. **Optionally verify locally** if the PR branch is checked out: `make check`, `make test`.
   Do not check out branches or change the working tree without asking.
4. **Report** in the terminal: findings ranked most severe first, each with `file:line`, what
   is wrong and a concrete fix; then what you did not check. Do not post anything to GitHub
   (`gh pr review`, `gh pr comment`) unless the user asks, and show the text first.
