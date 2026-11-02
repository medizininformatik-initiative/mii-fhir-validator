# Setting up Development

To run this project locally for development, the following steps need to be followed:

1. Add SNOMED CT release files
2. Download MII terminology packages
3. Configure environment
4. Start services

## Prerequisites

Run `make doctor` to see which of these are present.

| Needed for | Tools and files |
|---|---|
| Fast checks (`make check`) | Docker (daemon running), `jq`, ShellCheck, hadolint, actionlint (`brew install shellcheck hadolint actionlint`) |
| Integration tests (`make test`) | the running stack below, `curl`, `jq` |
| Documentation | Node.js in the version from `.nvmrc` (`nvm use`), npm |

For the stack itself:

- Docker and Docker Compose
- A SNOMED CT International Edition release (downloadable from e.g. https://www.nlm.nih.gov/healthit/snomedct/)

## Step 1: Add SNOMED CT Release Files

Download the SNOMED CT International Edition and extract the release package into the `snomed-ct-release/` directory. The directory should contain a subdirectory named `SnomedCT_InternationalRF2_PRODUCTION_<date>/`.

See `snomed-ct-release/README.md` for detailed instructions.

With a [UMLS account](https://uts.nlm.nih.gov/uts/), you can also fetch the zip through the NLM download API, using the API key from your UTS profile:

```bash
UMLS_API_KEY=<your key> ./scripts/ci/download-snomed-ct.sh SnomedCT_InternationalRF2_PRODUCTION_20250701T120000Z.zip
unzip SnomedCT_InternationalRF2_PRODUCTION_20250701T120000Z.zip -d snomed-ct-release
```

## Step 2: Download MII Terminology Packages

```bash
./scripts/terminology/get-mii-terminology.sh install
```

This downloads the CodeSystems and ValueSets needed for MII validation into a local directory for later upload to Blaze.

## Step 3: Configure Environment

```bash
cp .env.default .env
# Optionally edit .env to customise settings
```

Docker Compose reads `.env` automatically. The `.env.default` file contains sensible defaults and is tracked in git; `.env` is gitignored for local customisation.

## Step 4: Start Services

```bash
docker compose up -d
```

This starts:
- **validator** – FHIR Validator on port `8080`
- **blaze** – Blaze terminology server on port `8082`

## Step 5: Upload Terminology to Blaze

Wait for Blaze to report as healthy, then upload the terminology resources:

```bash
./scripts/terminology/upload-terminology.sh
```

## Accessing the Services

| Service | URL |
|---|---|
| FHIR Validator API | http://localhost:8080 |
| Blaze FHIR Terminology Server | http://localhost:8082 |

## Building the Docker Image Locally

To build the validator image from source instead of pulling from GHCR:

```bash
docker compose build validator
```

Or uncomment the `build:` section and comment out the `image:` line in `docker-compose.yml` for the `validator` service.

## MII Ontoserver Profile (Development with mTLS)

To develop against the MII Ontoserver instead of local Blaze:

1. Place decrypted client certificates in `nginx/certs/`:
   ```bash
   cp /path/to/client-cert.pem nginx/certs/
   openssl rsa -in encrypted-key.key -out nginx/certs/client-key.key
   ```
2. Update `.env`:
   ```
   COMPOSE_PROFILES=ontoserver
   TX_SERVER="http://nginx/fhir"
   ```
3. Start with this ontoserver profile:
   ```bash
   docker compose up -d
   ```

> [!IMPORTANT]
> The MII Ontoserver must only be used for development purposes (a small number of validations, no personal/patient data). See [Configuration](configuration.md) for the full usage policy.

## Checks and Tests

The checks are layered. Pick the cheapest one that covers your change:

| Command | What it checks | Needs |
|---|---|---|
| `make lint` | ShellCheck, hadolint, actionlint, `docker compose config` for both profiles and the CI override | linters (missing ones are skipped; `STRICT=1` fails instead) |
| `make check-sync` | IG versions in `validator/Dockerfile`, `.env.default` and `docs/overview.md`; image tags; terminology BOM pin; SNOMED CT release name | nothing |
| `make test-entrypoint` | `validator/docker-entrypoint.sh`: error messages and exit codes, proxy and terminology settings, Java arguments, package cache modes | Docker |
| `make test-runner` | `scripts/test/validate-test-resources.sh` against canned responses | nothing |
| `make test-snomed` | `scripts/ci/download-snomed-ct.sh`: source order, zip check, no secrets in output | `zip`, `unzip` |
| `make test-hooks` | the Claude Code policy hooks in `.claude/hooks` | `jq` |
| `make check` | all of the above | as above |
| `make test` / `make test-file FILE=…` | validates `.github/test-resources/*.json` against the running validator | the stack, with terminology loaded |

CI runs `make check STRICT=1` on every pull request to `develop` and `main` (`checks.yml`), the entrypoint tests against the built image (`build.yml`), and the `make test` script against a full Blaze stack (`ci-blaze.yml`).

### SNOMED CT in CI

`build.yml` and `ci-blaze.yml` get the SNOMED CT release through `.github/actions/snomed-ct-download`. It restores the zip from the Actions cache, and on a cache miss runs `scripts/ci/download-snomed-ct.sh` and saves the result to the cache straight away. The script tries two sources in order; each is skipped when its repository secret is not set, and at least one must be set:

| Secret | Source |
|---|---|
| `SCT_DOWNLOAD_TOKEN` | share token on speicherwolke.uni-leipzig.de |
| `UMLS_API_KEY` | NLM UTS download API (API key from a UTS profile); fallback when speicherwolke fails |

GitHub drops cache entries that nobody has read for 7 days. `snomed-cache.yml` runs on `main` every 5 days and on demand (`gh workflow run snomed-cache.yml`), so the entry stays readable for every branch and pull request.

To build the documentation, run `make docs-install` once (runs `npm ci` in `docs/`), then `make docs` for a static build into `docs/.vitepress/dist` or `make docs-dev` for a live-reload server.

## Troubleshooting

- **`skip: <tool> not installed` in `make lint`:** the linter is missing locally and was skipped. CI does not skip it. Install it, or run `make lint STRICT=1` to see what CI sees.
- **`make test-entrypoint` fails with "the Docker daemon is not running":** start Docker Desktop (or `dockerd`). The first run pulls `ubuntu:24.04`.
- **`make test` reports "no response" or `curl exit 7`:** the validator is not running or not ready yet. Check `docker compose ps` and wait for `FHIR Validator HTTP Service started` in `docker compose logs validator`.
- **`make test` reports `curl exit 28`:** the request timed out. The first validations after a start are slow while the terminology cache fills; raise `VALIDATOR_TIMEOUT` (seconds, default 300).
- **Validation fails with terminology errors (unknown code system, value set not found):** the terminology was not uploaded, or the BOM changed. Run `./scripts/terminology/get-mii-terminology.sh update` and `./scripts/terminology/upload-terminology.sh`.
- **`make check-sync` fails after an IG or release bump:** update every file it names. The `release` skill in `.claude/skills/release` lists the steps.

