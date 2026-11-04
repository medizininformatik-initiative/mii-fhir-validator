# mii-fhir-validator — Agent Instructions

Docker packaging of the HL7 `validator_cli.jar`, run in `server` mode behind an in-image nginx
allowlist on port 8080 (#21), pre-loaded
with the MII Kerndatensatz (KDS) IGs, plus a terminology server (local Blaze, or the MII
Ontoserver through an mTLS nginx proxy). There is no application source code: the moving parts
are the Dockerfile, the entrypoint script, `docker-compose.yml`, the terminology scripts and the
VitePress docs. Images are published to `ghcr.io/medizininformatik-initiative/mii-fhir-validator`.

## Repo layout

```
validator/            Dockerfile (bakes IG package cache), docker-entrypoint.sh, advisor.json
docker-compose.yml    profiles: blaze (validator + blaze), ontoserver (validator-ontoserver + nginx)
.env.default          documented defaults (tracked); .env is the local copy (gitignored, secret)
scripts/terminology/  MII terminology BOM (package.json) + download/upload scripts for Blaze
scripts/test/         validate-test-resources.sh: integration check, used by CI and `make test`
scripts/ci/           download-snomed-ct.sh: SNOMED CT zip from speicherwolke, NLM as fallback
scripts/              check-sync.sh, doctor.sh
tests/                hooks/, runner/, snomed/, entrypoint/: fast tests without a terminology stack
nginx/                mTLS proxy to ontoserver.mii-termserv.de; certs/ holds client keys (secret)
docs/                 VitePress site; public/openapi.yaml documents the validator HTTP API
.github/              workflows, test-resources/*.json (validated in CI), docker-compose.ci.yml
.claude/              settings.json, hooks/, skills/ (also exposed to Codex via .agents/skills/)
```

## Commands

- `make doctor` — which prerequisites are present for each layer below.
- `make check` — everything that needs no terminology stack (seconds, plus Docker for the
  entrypoint tests): `lint`, `check-sync`, `test-hooks`, `test-runner`, `test-snomed`,
  `test-entrypoint`.
  CI runs `make check STRICT=1` (`checks.yml`); without `STRICT=1` missing linters are skipped.
- `make lint` — ShellCheck (all non-ignored `*.sh`), hadolint, actionlint, `docker compose config`
  for both profiles and the CI override. Single linter: `make lint-sh|lint-docker|lint-actions|lint-compose`.
- `make check-sync` — exact comparison of IG versions, image tags, BOM and SNOMED CT name.
- `make test-entrypoint` — runs the working-tree entrypoint in `ubuntu:24.04` with a stub `java`;
  `ENTRYPOINT_TEST_IMAGE=mii-fhir-validator:test` tests a built image instead.
- Integration (needs SNOMED CT, terminology in Blaze, several GB RAM):
  - setup once: extract SNOMED CT into `snomed-ct-release/`,
    `./scripts/terminology/get-mii-terminology.sh install`, `cp .env.default .env` (user does this);
  - `docker compose up -d`, ready when `docker compose ps` shows the validator `healthy`
    (image HEALTHCHECK, images after 0.0.1-alpha.9) or `docker compose logs validator` shows
    `FHIR Validator HTTP Service started`; then `./scripts/terminology/upload-terminology.sh`
    (healthy does not mean terminology is loaded);
  - `make test` (all `.github/test-resources/*.json`) or `make test-file FILE=<resource.json>`.
- Build the image: `docker compose -f docker-compose.yml -f .github/configs/docker-compose.ci.yml up --build --wait`.
- Docs: `make docs-install` once (`npm ci`), then `make docs` (static build into
  `docs/.vitepress/dist`) or `make docs-dev` (live-reload server). Node version from `.nvmrc`.

## Architecture

- `validator/Dockerfile` downloads `validator_cli.jar` (`VALIDATOR_VERSION`) and runs it once with
  `IG_LIST` and `-tx n/a` to bake all IGs + dependencies into `/app/fhir-cache` (offline start).
  `IG_LIST` becomes `DEFAULT_IG_PARAMS`. `.dockerignore` allowlists the files it COPYs.
- `validator/docker-entrypoint.sh` does all runtime configuration, in this order:
  1. seed `$FHIR_HOME/.fhir/packages` from the baked cache (`FHIR_CACHE_SEED`), else fall back to
     the read-only baked cache (Kubernetes `readOnlyRootFilesystem`);
  2. forward proxy (`FORWARD_PROXY_*`) → JVM `-Dhttp(s).proxy*` properties;
  3. require a writable `/tmp`; write `/tmp/fhir-settings.json` for plain-`http://` `TX_SERVER`
     or basic auth;
  4. `nginx -t`, then start nginx (`validator/nginx.conf`, port 8080) and `java … server 8081`
     (no `-allowNetworkAccess`, so loopback only) with `IG_PARAMS` (default `DEFAULT_IG_PARAMS`)
     and `advisor.json` in the background; PID files `/tmp/nginx.pid`, `/tmp/validator.pid`;
  5. stay PID 1 as supervisor: TERM/INT → stop both (KILL after 8 s), exit 0; one child exits →
     stop the other, exit with its code (0 → 1).
- `validator/nginx.conf` is default-deny: exact routes `POST /validateResource`, `GET /health`
  (`auth_request` to the validator on every call, never `return`), `GET /openapi.json` (built
  from `docs/public/openapi.yaml` in a pinned `yq` stage), everything else 404/405. Opening a
  route is a deliberate API decision (#21, Hyrum's Law); `build.yml` asserts the blocked list.
- Both validator services share one image and `container_name: fhir-validator`.

## Conventions not enforced by tooling

- The entrypoint is POSIX `sh`, not bash. It relies on intentional word-splitting of
  `IG_PARAMS`, `FHIR_SETTINGS_ARG` and `TX_LOG`; keep the `shellcheck disable=SC2086` line.
- Misconfiguration fails fast: `Error: …` on stderr, `exit 1`. Paired variables (proxy
  host/port, tx username/password) are both-or-neither. Each new check gets a case in
  `tests/entrypoint/run.sh` that asserts the exit status and the message.
- A new env var touches: the entrypoint, **both** validator services in `docker-compose.yml`,
  `.env.default`, `README.md`, `docs/configuration.md`.
- `make check-sync` covers the exact sync points (IG list = `.env.default` = `docs/overview.md`
  table; compose tag = README/`docs/use.md`; exact BOM pin = docs; SNOMED CT name). Review the
  surrounding prose in `docs/overview.md` by hand; its 2026 image pin is intentional.
- A new validation scenario is a new file in `.github/test-resources/`; CI picks it up.

## Branches and commits (for the user)

- Branch from `develop` as `<issue>-<short-slug>`; PRs target `develop`. `main` receives
  merges from `develop` plus `chore(release)`/`docs(release)` commits.
- Conventional Commits with scope: `feat(validator):`, `fix(docker):`, `ci(release):`,
  `chore(packages):`, `chore(release): prepare vX.Y.Z`.
- A pushed `v*.*.*` tag builds the multi-arch image (`build.yml`) and opens a draft GitHub
  release (`release.yml`). See the `release` skill.

## Definition of done

- `make check` passes; say which parts were skipped (missing linter, no Docker).
- Behavior changes come with a test: an entrypoint case, a runner case, a hook case, or a new
  `.github/test-resources/*.json` resource.
- `make test` passes against a running stack, or the handover says why it was not run.
- Docs are updated where behavior or configuration changed.

## Git policy

- NEVER run `git add`, `git commit`, `git push`, `git merge`, `git rebase`, `git reset`,
  `git tag`, `gh pr create` or `gh pr merge`. The user stages and commits everything.
- Finish every task by summarizing the diff (`git status`, `git diff`) and proposing a
  Conventional Commit message.

## Boundaries

- Secrets: never read or print `.env`/`.env.*` (except `.env.default`), `secrets/`, keys and
  certificates in `nginx/certs/`, or the values of `TX_SERVER_PASSWORD`/`SCT_DOWNLOAD_TOKEN`/`UMLS_API_KEY`.
  No environment dumps (`env`, `printenv`, `docker inspect`, `docker compose config` without `-q`).
  Names and metadata are fine (`git check-ignore`, `ls`, `test -f`); limit recursive searches
  to subdirectories (`grep -rn x docs`), not the repository root.
- Generated files: do not hand-edit `docs/package-lock.json` (npm only),
  `scripts/terminology/node_modules/`, `docs/.vitepress/dist/`.
- Migrations: none in this repo. Blaze data lives in the `blaze-data` volume; never run
  `docker compose down -v` without asking.
- Dependencies: ask before installing tools or adding packages, and before bumping
  `VALIDATOR_VERSION`, the Blaze image digest, GitHub Action or linter versions.
- The MII Ontoserver is for development only: few validations, no patient data.

## Where the rules are enforced

| Rule | Claude Code | Other agents (Codex, …) | CI |
|---|---|---|---|
| Git policy | `.claude/settings.json` deny + `block-git-writes.sh` | this file only | — |
| Secrets | deny rules + `block-secret-reads.sh` | this file only | `.dockerignore`, `.gitignore` |
| Lint before handover | `lint-on-stop.sh` (reminder, lets the agent stop on the 2nd try) | run `make check` | `checks.yml` (enforced) |

The policy hooks share their shell parsing in `.claude/hooks/lib/` and fail closed: missing
`jq`, a missing library or malformed input blocks, and `onFailure: "block"` (Claude Code
≥ 2.1.295; older versions let the action through) covers crashes and timeouts. They are a
guardrail, not a sandbox. A change to a hook needs allowed and blocked cases in
`tests/hooks/cases.tsv` (`make test-hooks`).
