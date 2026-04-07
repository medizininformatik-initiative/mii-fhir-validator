# Use

## Starting the Service

### Blaze Profile (Default)

Start the FHIR Validator with the local Blaze terminology server:

```bash
docker compose --profile blaze up -d
```

### Ontoserver Profile

Start the FHIR Validator with the MII Ontoserver via nginx proxy (requires client certificates in `nginx/certs/`):

```bash
docker compose --profile ontoserver up -d
```

### Loading Terminology Resources into Blaze

After starting Blaze for the first time, upload the required MII terminology packages:

```bash
# Download terminology packages (CodeSystems, ValueSets)
./scripts/terminology/get-mii-terminology.sh install

# Wait for Blaze to be ready, then upload:
./scripts/terminology/upload-terminology.sh
```

Without this step, terminology-dependent validation (CodeSystem lookups, ValueSet bindings) will fail.

## Validating a FHIR Resource

The validator exposes a single HTTP endpoint on port `8080`.

### Endpoint

```
POST http://localhost:8080/validateResource
```

### Headers

| Header | Values |
|---|---|
| `Content-Type` | `application/fhir+json` or `application/fhir+xml` |
| `Accept` | `application/fhir+json` or `application/fhir+xml` (optional, defaults to JSON) |

### Example – JSON

```bash
curl -X POST http://localhost:8080/validateResource \
  -H "Content-Type: application/fhir+json" \
  -H "Accept: application/fhir+json" \
  -d @patient-example.json
```

### Example – XML

```bash
curl -X POST http://localhost:8080/validateResource \
  -H "Content-Type: application/fhir+xml" \
  -H "Accept: application/fhir+xml" \
  -d @patient-example.xml
```

The validator returns an `OperationOutcome` resource with validation results.

## Using a Custom HTTP Terminology Server

To connect to any HTTP terminology server, set `TX_SERVER` to an `http://` URL. The container entrypoint script detects this at startup and automatically generates the required `allowHttp` configuration for that URL:

```bash
docker run -d -p 8080:8080 \
  -e TX_SERVER=http://my-terminology-server:8080/fhir \
  --network your-network \
  ghcr.io/medizininformatik-initiative/mii-fhir-validator:0.0.1-alpha.6
```

## Loading Additional Implementation Guides

To load local IG packages from the `igs/` directory, set `IG_PARAMS` in `.env`:

```bash
IG_PARAMS="-ig /igs/your-package-2026.0.0.tgz"
```

For multiple IGs:

```bash
IG_PARAMS="-ig /igs/package1.tgz -ig /igs/package2.tgz"
```

## Offline Operation

The validator can operate offline, but all dependencies must be pre-cached first.

Run the validator once while online to download and cache all required packages:

```bash
docker compose --profile blaze up -d
# Wait for the validator to finish downloading packages:
docker compose logs -f validator
# Once ready:
docker compose down
```

The package cache is persisted in the `fhir-package-cache` Docker volume and will be available offline. SNOMED CT release files must also be present in `snomed-ct-release/` for Blaze to start.