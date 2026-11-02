---
name: release
description: Prepare a mii-fhir-validator release or IG version bump — update the IG list in all synced places, bump the image tag in compose and docs, check the terminology BOM pin, draft release notes, then hand the tag and push commands to the user. Use when the user asks to "prepare a release", "release vX", "bump the IG versions", "update the IGs for the 2027 KDS" or "cut alpha.N".
---

# Release

The agent prepares the files; the **user** commits, tags and pushes (AGENTS.md → Git policy).
Pushing a `v*.*.*` tag runs `build.yml` (multi-arch image to GHCR, tag without `v`) and
`release.yml` (draft GitHub release, prerelease if the version contains `-`).

## A. IG version bump (`chore(packages): …`)

1. Get the target versions from the user (or the issue). Never guess package versions.
2. Update `ARG IG_LIST` in `validator/Dockerfile` and `IG_PARAMS` in `.env.default` — same
   packages, same versions, same order.
3. Update the IG table in `docs/overview.md` and note intentional exceptions (e.g. an IG from
   another release line), like the existing text does.
4. Check: `make check-sync` (IG_LIST = IG_PARAMS = docs table, BOM pin, image tags).
5. If the terminology BOM changes, pin it exactly in `scripts/terminology/package.json`
   (no `^`) and update the BOM table in `docs/overview.md`.

## B. Release prep (`chore(release): prepare vX.Y.Z` / `docs(release): …`)

1. Version: latest with `git describe --tags --abbrev=0`; confirm the new one with the user.
2. Replace the old image tag (without `v`) in both validator services of `docker-compose.yml`
   and in `docs/use.md` / `docs/overview.md`: `grep -n '<old-version>' docker-compose.yml docs/*.md README.md`.
3. Update version-specific links in `docs/overview.md` (`blob/vX.Y.Z/...`).
4. `make check` (includes `check-sync`); if the stack runs, `make test`.
5. Draft release notes (Docker pull line, IG/BOM changes, features, fixes) from
   `git log --oneline <prev-tag>..HEAD`.
6. Hand over: diff summary, proposed commit message, and the commands for the user to run
   after merging to `main`:
   ```
   git tag vX.Y.Z
   git push origin vX.Y.Z
   ```
   Then: review the draft release on GitHub and publish it.
