---
name: fix-issue
description: Fix a GitHub issue of mii-fhir-validator end to end — read the issue, find the root cause, propose a plan and wait for approval, add a failing test, implement, run lint and tests, then hand over a diff summary and a proposed commit message without committing. Use when the user says "fix issue #N", "work on #N", "resolve this issue" or pastes an issue URL.
---

# Fix issue

Work through the steps in order. Do not commit, push, or open a PR (see AGENTS.md → Git policy).

1. **Read the issue.** `gh issue view <n> --comments`. Note the expected vs. actual behavior,
   the affected component (entrypoint, Dockerfile/IG list, compose, terminology scripts, docs)
   and any linked PRs.
2. **Find the root cause.** Read the relevant files; for runtime behavior, start with
   `validator/docker-entrypoint.sh` and the service definitions in `docker-compose.yml`.
   Do not guess — quote the line(s) that cause the problem.
3. **Propose a plan and wait.** State the root cause, the files you will change (include every
   sync point from AGENTS.md that applies), and the test you will add. Wait for approval.
   This pause is intentional for every fix, small ones included; skip it only when the user
   explicitly says to go ahead without a plan.
4. **Write the failing test first** and show that it fails:
   - Entrypoint behavior: a case in `tests/entrypoint/run.sh` (exit status and message);
     `make test-entrypoint`.
   - Validation runner: a case in `tests/runner/run.sh`; `make test-runner`.
   - Hooks: a line in `tests/hooks/cases.tsv`; `make test-hooks`.
   - Sync drift: a check in `scripts/check-sync.sh`; `make check-sync`.
   - Validation results: a resource in `.github/test-resources/` and
     `make test-file FILE=<it>` against the running stack. If the stack cannot run here, say so.
5. **Implement** the smallest change that fixes the root cause. Follow the conventions in
   AGENTS.md (POSIX `sh` entrypoint, fail fast on misconfiguration, both validator services).
6. **Verify.** `make check`, then `make test` if the stack is up.
7. **Hand over.** Summarize `git status` and `git diff`, list what was and was not run, and
   propose a commit message such as `fix(validator): <what> (#<n>)`. Stop there.
