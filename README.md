> ⚠️ **Note:** Active development happens on the `develop` branch.
>
> ➡️ Go here: https://github.com/medizininformatik-initiative/mii-fhir-validator/tree/develop

# MII FHIR Validator

A locally deployable FHIR validation service pre-configured for MII Implementation Guides. Pre-built images are published to GitHub Container Registry.

`docker compose` starts two services:
- **Validator** — FHIR Validator HTTP service on port `8080`, pre-loaded with MII IGs
- **Blaze** — local FHIR terminology server on port `8082`

For access to the **MII Service Unit Terminology Server** (`ontoserver.mii-termserv.de`) instead of local Blaze, see [Alternative: MII Ontoserver Setup](#alternative-mii-ontoserver-setup) below.

## Prerequisites

- Docker and Docker Compose

## Quick Start

1. **Clone this repository:**
   ```bash
   git clone https://github.com/medizininformatik-initiative/mii-fhir-validator.git
   cd mii-fhir-validator
   ```
   The `docker-compose.yml` in this repository is the canonical configuration. It references the pre-built image from GHCR and is kept in sync with the validator image.

2. **Add SNOMED CT release files (required for validation):**
   ```bash
   # Download SNOMED CT International Edition from e.g. https://www.nlm.nih.gov/healthit/snomedct/
   # Extract the release into the snomed-ct-release/ directory
   # See snomed-ct-release/README.md for detailed instructions
   ```

3. **Download MII terminology packages:**
   ```bash
   ./scripts/terminology/get-mii-terminology.sh install
   ```
   This downloads CodeSystems and ValueSets that will be loaded into Blaze.

4. **Add Implementation Guides (optional):**
   Place your offline IG package files (`.tgz`) in the `igs/` directory and reference them in `IG_PARAMS` (e.g. `-ig /igs/your-package.tgz`).

5. **Configure environment variables (optional):**
   ```bash
   cp .env.default .env
   # Edit .env to customize settings
   ```
   Docker Compose will read `.env` for configuration. Infrastructure variables (`TX_SERVER`, `FHIR_VERSION`, `TX_CACHE_DIR`, `TX_LOG`) have built-in defaults in `docker-compose.yml` — you only need `.env` to set `JAVA_OPTS` and `IG_PARAMS`, or to override those defaults. `.env.default` documents all available variables and is tracked in git; `.env` is gitignored for local customizations.

6. **Start the services:**
   ```bash
   docker compose --profile blaze up -d
   ```
   Docker Compose pulls the pre-built image from GHCR automatically and starts both services.

7. **Load terminology resources into Blaze (required for validation):**
   ```bash
   # Wait for Blaze to be ready (check: docker-compose logs blaze)
   ./scripts/terminology/upload-terminology.sh
   ```
   This uploads CodeSystems and ValueSets to Blaze. Without this step, terminology validation will fail.

8. **Access the validator:**
   - Validator API: `http://localhost:8080`
   - Blaze terminology server: `http://localhost:8082`

## Configuration

### Service Profiles

This setup uses Docker Compose profiles to support different terminology server configurations:

**Blaze Profile (Default - Local Development):**
- Local Blaze terminology server with LOINC and SNOMED CT
- Direct HTTP connection (no authentication required)
- Start with: `docker compose --profile blaze up -d`

**Ontoserver Profile (MII Production Server):**
- Connects to MII Service Unit Terminology Server via nginx proxy
- Requires client certificates for authentication
- Validator connects to nginx via HTTP, nginx proxies HTTPS to MII Ontoserver
- Start with: `docker compose --profile ontoserver up -d`

### Blaze Terminology Server (Default)

The setup uses [Blaze](https://samply.github.io/blaze/) as a local terminology server with LOINC and SNOMED CT support.

**Architecture:**
- **Blaze** runs on HTTP (accessible on port 8082)
- **Validator** connects directly to Blaze via HTTP

### Validator Configuration

Configuration is split into two tiers:

**Set via `.env` (required for basic use):**
- `JAVA_OPTS` - JVM memory settings (default: `-Xmx16g`)
- `IG_PARAMS` - Implementation Guides to load (e.g., `-ig package#version`)

**Built-in defaults in `docker-compose.yml` (override in `.env` only if needed):**
- `FHIR_VERSION` - FHIR version (default: `4.0`)
- `TX_SERVER` - Terminology server URL (default: `http://blaze-terminology:8080/fhir` for blaze profile, `http://nginx/fhir` for ontoserver profile)
- `TX_CACHE_DIR` - Terminology cache directory (default: `/tmp/tx-cache`)
- `TX_LOG` - Terminology request log path (default: `/tmp/tx-cache/tx.log`)

**Using .env file:**
```bash
cp .env.default .env
# Edit .env with your custom values
```

Docker Compose reads `.env` from the same directory. `.env.default` documents all available variables and is tracked in git; `.env` is gitignored for local customization.

**Direct editing:**
Alternatively, edit `docker-compose.yml` environment variables directly.

## Usage Examples

### Validate a FHIR Resource

The validator runs as an HTTP server on port 8080. To validate a resource:

**Endpoint:**
```
POST http://localhost:8080/validateResource
```

**Headers:**
- `Content-Type`: `application/fhir+json` or `application/fhir+xml`
- `Accept`: `application/fhir+json` or `application/fhir+xml` (optional, defaults to JSON)

**Example with JSON:**
```bash
curl -X POST http://localhost:8080/validateResource \
  -H "Content-Type: application/fhir+json" \
  -H "Accept: application/fhir+json" \
  -d @patient-example.json
```

**Example with XML:**
```bash
curl -X POST http://localhost:8080/validateResource \
  -H "Content-Type: application/fhir+xml" \
  -H "Accept: application/fhir+xml" \
  -d @patient-example.xml
```

The validator returns an `OperationOutcome` resource with validation results.

## Offline Operation

The pre-built image contains the full FHIR package cache for all default MII IGs baked in at build time. This includes all IG dependencies. No internet access is required at runtime when using the default configuration.

### Adding Custom IGs for Offline Use

If you add IGs beyond the defaults via `IG_PARAMS`, their dependencies will be resolved at startup. To ensure they are available offline, run the validator once while online to populate the cache:

```bash
docker compose --profile blaze up -d
# Wait for all packages to download (check logs: docker compose logs validator)
docker compose down
```

The `fhir-package-cache` Docker volume persists the cache across container restarts.

To load IGs from the `igs/` directory:
```bash
IG_PARAMS="-ig /igs/your-package-2026.0.0.tgz -ig /igs/another-package.tgz"
```

**Note:** A terminology service (Blaze) is still required for offline terminology validation (CodeSystem, ValueSet bindings, code validation). SNOMED CT release files must be provided locally — see [snomed-ct-release/README.md](snomed-ct-release/README.md).

## Alternative: MII Ontoserver Setup

> [!IMPORTANT]
> The terminology server MUST NOT be used for running production validations in local ETL processes. The Service Unit Terminological Services does not allow this kind of usage. You are welcome to use this tool for the development process of your local ETL processes however, where only a few resources are validated, and no personal data is sent to the service. If you have any questions about this policy, please contact [team@mail.mii-termserv.de](mailto:team@mail.mii-termserv.de).

To use the **MII Service Unit Terminology Server** at `https://ontoserver.mii-termserv.de` instead of the local Blaze server:

### Prerequisites

- Client certificate for MII terminology server authentication
- Private key (decrypted, PEM format)

### Setup Steps

1. **Add client certificates** to `nginx/certs/`:
   ```bash
   # Copy your MII certificates
   cp /path/to/client-cert.pem nginx/certs/
   cp /path/to/client-key.key nginx/certs/
   ```
   
   **Important:** The private key must be decrypted (no passphrase). To decrypt:
   ```bash
   openssl rsa -in encrypted-key.key -out client-key.key
   ```

2. **Update configuration:**
   
   Update `.env` to use nginx proxy:
   ```bash
   cp .env.default .env
   # Edit .env and change:
   TX_SERVER="http://nginx/fhir"
   ```

3. **Start with Ontoserver profile:**
   ```bash
   docker compose --profile ontoserver up -d
   ```
   
   The setup works as follows:
   - Validator connects to nginx via HTTP
   - Nginx proxies requests to MII Ontoserver via HTTPS
   - Client certificates are used for authentication with MII Ontoserver

### Using Other Terminology Servers

**For a local server without authentication (e.g., HAPI FHIR):**
- Set `TX_SERVER` to `http://your-server:port/fhir` in `.env`
- Use the blaze profile: `docker compose --profile blaze up -d`

**For other authenticated servers:**
- Follow steps similar to MII Ontoserver setup
- Update `nginx/nginx.conf` with correct URL and certificate paths
- Use the ontoserver profile: `docker compose --profile ontoserver up -d`

