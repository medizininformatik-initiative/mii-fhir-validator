# MII FHIR Validator Docker Image

Docker image for the FHIR Validator configured for MII (Medizininformatik-Initiative) Implementation Guides.

## Quick Start

```bash
docker run -p 8080:8080 \
  -e TX_SERVER=https://your-terminology-server/fhir \
  ghcr.io/medizininformatik-initiative/mii-fhir-validator:latest
```

## Configuration

### Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `TX_SERVER` | Terminology server URL (required) | - |
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

## Usage Examples

### With Blaze Terminology Server (HTTP)

For terminology servers with HTTP:

```bash
docker run -d --name fhir-validator \
  -p 8080:8080 \
  -e TX_SERVER=http://blaze:8080/fhir \
  --network your-network \
  ghcr.io/medizininformatik-initiative/mii-fhir-validator:latest
```

**Note:** If you encounter SSL errors with HTTP, use the HTTPS setup below.

### With HTTPS Terminology Servers (Self-Signed Certificates)

**Recommended for servers with self-signed certificates.** This includes local Blaze setups behind nginx proxies, or external terminology servers like Ontoserver with custom certificates:

```bash
docker run -d --name fhir-validator \
  -p 8080:8080 \
  -e TX_SERVER=https://nginx/fhir \
  --network your-network \
  -v /path/to/server-certificate.crt:/etc/nginx/certs/self-signed.crt:ro \
  ghcr.io/medizininformatik-initiative/mii-fhir-validator:latest
```

**Important:** 
- The certificate must be the **server certificate** used by the terminology server's HTTPS endpoint
- Mount the certificate at `/etc/nginx/certs/self-signed.crt` inside the container
- The certificate is imported into the Java truststore on startup
- The hostname in `TX_SERVER` must match the certificate's Common Name (CN) or Subject Alternative Names (SAN)
- Use absolute paths for volume mounts, or run from the directory containing the certificate


### Docker Compose Example

**Simple HTTP setup:**

```yaml
services:
  blaze:
    image: samply/blaze:latest
    ports:
      - "8082:8080"
    environment:
      JAVA_TOOL_OPTIONS: "-Xmx4g"
      ENABLE_TERMINOLOGY_SERVICE: "true"
      ENABLE_TERMINOLOGY_LOINC: "true"
    volumes:
      - blaze-data:/app/data
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
      TX_SERVER: http://blaze:8080/fhir
      JAVA_OPTS: -Xmx4g
    depends_on:
      blaze:
        condition: service_healthy

volumes:
  blaze-data:
```

**With nginx HTTPS proxy (self-signed certs):**

```yaml
services:
  blaze:
    image: samply/blaze:latest
    environment:
      JAVA_TOOL_OPTIONS: "-Xmx4g"
      ENABLE_TERMINOLOGY_SERVICE: "true"
      ENABLE_TERMINOLOGY_LOINC: "true"
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

  nginx:
    image: nginx:alpine
    volumes:
      - ./nginx/nginx.conf:/etc/nginx/nginx.conf:ro
      - ./nginx/certs:/etc/nginx/certs:ro
    networks:
      - fhir-network

  validator:
    image: ghcr.io/medizininformatik-initiative/mii-fhir-validator:latest
    ports:
      - "8080:8080"
    environment:
      TX_SERVER: https://nginx/fhir
      JAVA_OPTS: -Xmx4g
    volumes:
      - ./nginx/certs/self-signed.crt:/etc/nginx/certs/self-signed.crt:ro
    depends_on:
      blaze:
        condition: service_healthy
      nginx:
        condition: service_started
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
