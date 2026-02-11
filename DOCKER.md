# MII FHIR Validator Docker Image

Docker image for the FHIR Validator configured for MII (Medizininformatik-Initiative) Implementation Guides.

This validator includes a patched version that supports HTTP connections to terminology servers via the `allowHttp` feature configured in `fhir-settings.json`.

## Quick Start

```bash
docker run -p 8080:8080 \
  -e TX_SERVER=http://your-terminology-server/fhir \
  ghcr.io/medizininformatik-initiative/mii-fhir-validator:latest
```

## Configuration

### Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `TX_SERVER` | Terminology server URL (HTTP supported) | - |
| `FHIR_VERSION` | FHIR version | `4.0` |
| `JAVA_OPTS` | JVM options | `-Xmx4g` |
| `IG_PARAMS` | Additional Implementation Guide parameters | Preconfigured MII IGs |

### Pre-configured Implementation Guides

The image comes with MII Implementation Guides pre-configured. These packages are downloaded and cached during the Docker build process.

For the complete list of pre-configured IGs and their versions, see:
- [`validator/Dockerfile`](validator/Dockerfile) - `ARG IG_LIST` section
- [`.env.default`](.env.default) - `IG_PARAMS` variable

You can override these at runtime using the `IG_PARAMS` environment variable.

### HTTP Support

This validator includes a custom patch that allows HTTP connections to terminology servers. The allowed servers are configured in `/app/fhir-settings.json` inside the container:

```json
{
  "servers": [
    {
      "url": "http://blaze-terminology:8080/fhir",
      "type": "fhir",
      "authenticationType": "none",
      "allowHttp": true
    }
  ]
}
```

The validator will accept HTTP connections to any terminology server that matches the configured URLs. For custom setups, you can mount your own `fhir-settings.json`.

### Custom HTTP Terminology Server

To connect to your own HTTP terminology server, create a custom `fhir-settings.json`:

```json
{
  "servers": [
    {
      "url": "http://my-terminology-server:8080/fhir",
      "type": "fhir",
      "authenticationType": "none",
      "allowHttp": true
    }
  ]
}
```

Then mount it when running the container:

```bash
docker run -d --name fhir-validator \
  -p 8080:8080 \
  -e TX_SERVER=http://my-terminology-server:8080/fhir \
  -v /path/to/fhir-settings.json:/app/fhir-settings.json:ro \
  --network your-network \
  ghcr.io/medizininformatik-initiative/mii-fhir-validator:latest
```

**Note:** The `url` in `fhir-settings.json` must match or be a prefix of your `TX_SERVER` value.

### HTTPS Terminology Server

For HTTPS servers, you don't need custom `fhir-settings.json`:

```bash
docker run -d --name fhir-validator \
  -p 8080:8080 \
  -e TX_SERVER=https://your-terminology-server/fhir \
  ghcr.io/medizininformatik-initiative/mii-fhir-validator:latest
```

## Usage Examples

### With Blaze Terminology Server

```bash
docker run -d --name fhir-validator \
  -p 8080:8080 \
  -e TX_SERVER=http://blaze:8080/fhir \
  --network your-network \
  ghcr.io/medizininformatik-initiative/mii-fhir-validator:latest
```

### Docker Compose Example

#### Using .env file (Recommended)

Create a `.env` file from the template:
```bash
cp .env.default .env
```

Then customize `.env` with your settings:
```env
JAVA_OPTS="-Xmx4g"
FHIR_VERSION="4.0"
TX_SERVER="http://blaze-terminology:8080/fhir"
IG_PARAMS="-ig de.basisprofil.r4#1.5.4 -ig de.medizininformatikinitiative.kerndatensatz.meta#2026.0.0 ..."
```

Docker Compose configuration with `.env` support:
```yaml
services:
  blaze:
    image: samply/blaze:latest
    container_name: blaze-terminology
    ports:
      - "8082:8080"
    environment:
      JAVA_TOOL_OPTIONS: "-Xmx4g"
      ENABLE_TERMINOLOGY_SERVICE: "true"
      ENABLE_TERMINOLOGY_LOINC: "true"
      ENABLE_TERMINOLOGY_SNOMED_CT: "true"
    volumes:
      - blaze-data:/app/data
    networks:
      - fhir-network
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8080/health"]
      interval: 10s
      timeout: 5s
      retries: 5
      start_period: 30s

  validator:
    image: ghcr.io/medizininformatik-initiative/mii-fhir-validator:latest
    ports:
      - "8080:8080"
    environment:
      - JAVA_OPTS=${JAVA_OPTS}
      - FHIR_VERSION=${FHIR_VERSION}
      - TX_SERVER=${TX_SERVER}
      - IG_PARAMS=${IG_PARAMS}
    # Optional: mount custom fhir-settings.json for different HTTP servers
    # volumes:
    #   - ./fhir-settings.json:/app/fhir-settings.json:ro
    depends_on:
      blaze:
        condition: service_healthy
    networks:
      - fhir-network

networks:
  fhir-network:

volumes:
  blaze-data:
```

Docker Compose automatically reads `.env` from the same directory. The `.env.default` file provides example values and is tracked in version control, while `.env` is gitignored for local customization.

#### Inline Configuration

Alternatively, specify environment values directly in `docker-compose.yml`:
```yaml
  validator:
    image: ghcr.io/medizininformatik-initiative/mii-fhir-validator:latest
    ports:
      - "8080:8080"
    environment:
      TX_SERVER: http://blaze-terminology:8080/fhir
      JAVA_OPTS: -Xmx4g
    depends_on:
      blaze:
        condition: service_healthy
    networks:
      - fhir-network
```

## API Usage

### Validate a Resource

```bash
curl -X POST http://localhost:8080/validateResource \
  -H "Content-Type: application/fhir+json" \
  -H "Accept: application/fhir+json" \
  -d @patient.json
```

The validator returns an `OperationOutcome` resource with validation results.
