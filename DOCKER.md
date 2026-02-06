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

The image comes with these MII Implementation Guides pre-configured:
- de.basisprofil.r4#1.5.4
- de.medizininformatikinitiative.kerndatensatz.meta#2026.0.0
- de.medizininformatikinitiative.kerndatensatz.base#2026.0.0
- de.medizininformatikinitiative.kerndatensatz.laborbefund#2026.0.0
- de.medizininformatikinitiative.kerndatensatz.medikation#2026.0.0
- de.medizininformatikinitiative.kerndatensatz.consent#2026.0.0
- de.medizininformatikinitiative.kerndatensatz.bildgebung#2026.0.0
- de.medizininformatikinitiative.kerndatensatz.biobank#2026.0.0
- de.medizininformatikinitiative.kerndatensatz.molgen#2026.0.4
- de.medizininformatikinitiative.kerndatensatz.onkologie#2026.0.0
- de.medizininformatikinitiative.kerndatensatz.patho#2026.0.0
- de.medizininformatikinitiative.kerndatensatz.icu#2026.0.0-ballot

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
      TX_SERVER: http://blaze-terminology:8080/fhir
      JAVA_OPTS: -Xmx4g
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

## API Usage

### Validate a Resource

```bash
curl -X POST http://localhost:8080/validateResource \
  -H "Content-Type: application/fhir+json" \
  -H "Accept: application/fhir+json" \
  -d @patient.json
```

The validator returns an `OperationOutcome` resource with validation results.
