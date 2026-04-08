# Setting up Development

To run this project locally for development, the following steps need to be followed:

1. Add SNOMED CT release files
2. Download MII terminology packages
3. Configure environment
4. Start services

## Prerequisites

- Docker and Docker Compose
- A SNOMED CT International Edition release (downloadable from e.g. https://www.nlm.nih.gov/healthit/snomedct/)

## Step 1: Add SNOMED CT Release Files

Download the SNOMED CT International Edition and extract the release package into the `snomed-ct-release/` directory. The directory should contain a subdirectory named `SnomedCT_InternationalRF2_PRODUCTION_<date>/`.

See `snomed-ct-release/README.md` for detailed instructions.

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
docker compose --profile blaze up -d
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
   TX_SERVER="http://nginx/fhir"
   ```
3. Start with the ontoserver profile:
   ```bash
   docker compose --profile ontoserver up -d
   ```

> [!IMPORTANT]
> The MII Ontoserver must only be used for development purposes (a small number of validations, no personal/patient data). See [Configuration](configuration.md) for the full usage policy.

