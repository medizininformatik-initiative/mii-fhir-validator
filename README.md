# MII FHIR Validator Service

A locally deployable FHIR validation service. This service includes:
- FHIR Validator as a local HTTP service
- Blaze terminology service (default, no authentication required)
- Optional: Nginx proxy for certificate-based access to MII Ontoserver
- Support for offline Implementation Guides

**Current Configuration:** This setup uses **Blaze** as the default terminology server for local development and validation. For access to the **MII Service Unit Terminology Server** (`ontoserver.mii-termserv.de`), see [Alternative: MII Ontoserver Setup](#alternative-mii-ontoserver-setup) below.

> [!IMPORTANT]
> The default terminology server MUST NOT be used for running production validations in local ETL processes. The Service Unit Terminological Services does not allow this kind of usage. You are welcome to use this tool for the development process of your local ETL processes however, where only a few resources are validated, and no personal data is sent to the service. If you have any questions about this policy, please contact [team@mail.mii-termserv.de](mailto:team@mail.mii-termserv.de).

## Prerequisites

- Docker and Docker Compose
- FHIR Validator JAR file (downloaded by setup script)

## Quick Start

1. **Download the FHIR validator:**
   ```bash
   ./validator/download-validator.sh
   ```

2. **Generate self-signed certificate:**
   ```bash
   ./scripts/generate-self-signed-cert.sh
   ```
   This creates certificates needed for the validator's internal HTTPS connection to Blaze (via nginx proxy).

3. **Add SNOMED CT release files (required for validation):**
   ```bash
   # Download SNOMED CT International Edition from e.g. https://www.nlm.nih.gov/healthit/snomedct/
   # Extract the release into the snomed-ct-release/ directory
   # See snomed-ct-release/README.md for detailed instructions
   ```

4. **Download MII terminology packages (required for MII validation):**
   ```bash
   ./scripts/terminology/get-mii-terminology.sh install
   ```
   This downloads CodeSystems and ValueSets that will be loaded into Blaze.

5. **Add Implementation Guides (optional):**
   Place your offline IG package files (`.tgz`) in the `igs/` directory.
   
   **For true offline operation:** You also need to pre-populate the FHIR package cache with core dependencies. See [Offline Operation](#offline-operation) below.

6. **Start the services:**
   ```bash
   docker-compose up -d
   ```
   This starts the validator with Blaze terminology server (LOINC + SNOMED CT support).

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

### Blaze Terminology Server (Default)

The setup uses [Blaze](https://samply.github.io/blaze/) as a local terminology server with LOINC and SNOMED CT support.

**Architecture:**
- **Blaze** runs on HTTP (accessible on port 8082)
- **Nginx** provides HTTPS/SSL termination with self-signed certificate
- **Validator** connects to `https://nginx/fhir`, which proxies to Blaze over HTTP

### Validator Configuration

Edit `docker-compose.yml` environment variables to customize:
- `FHIR_VERSION` - FHIR version (default: 4.0)
- `IG_PARAMS` - Implementation Guides to load (e.g., `-ig package#version`)
- `TX_SERVER` - Terminology server endpoint (default: `https://nginx/fhir` which proxies to Blaze)
- `JAVA_OPTS` - JVM memory settings

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

### Running Without Docker

If you need to run the validator JAR directly (outside Docker):

**With Blaze running via Docker Compose:**
```bash
# Start only Blaze and nginx via Docker
docker-compose up -d blaze nginx

# Run validator locally, connecting to Blaze on localhost
java -jar validator/validator_cli.jar \
  -server 8080 \
  -version 4.0 \
  -ig de.medizininformatikinitiative.kerndatensatz.base#2026.0.0 \
  -tx http://localhost:8082/fhir
```

**Note:** Without a terminology server, validation will be incomplete. See [Configuration](#configuration) for terminology server options.

## Offline Operation

The validator can work in offline environments, but requires preparation:

### Important: Offline Operation Requires Pre-populated Package Cache

The validator needs **all dependencies** available offline. When starting, it downloads:
- Core FHIR spec (e.g., `hl7.fhir.r4.core#4.0.1`)
- Terminology packages (e.g., `hl7.terminology.r4#6.2.0`)
- Extension packages (e.g., `hl7.fhir.uv.extensions.r4#5.2.0`)
- IG dependencies (e.g., `de.basisprofil.r4#1.5.4`)

**To prepare for offline use:**

Run the validator once while online to download and cache all dependencies:
```bash
docker-compose up -d
# Wait for all packages to download (check logs: docker-compose logs validator)
docker-compose down
```

The package cache is persisted in a Docker volume and will be available for offline use.

### Offline with Blaze Terminology Server (Default Configuration)
1. **Add SNOMED CT release files** to `snomed-ct-release/` directory (see [snomed-ct-release/README.md](snomed-ct-release/README.md))
2. Pre-populate package cache (see above)
3. Place your IG `.tgz` files in `igs/` directory (optional)
4. Start services: `docker-compose up -d`

**Note:** A terminology service like Blaze is required for complete FHIR validation. Without it, terminology-dependent validations (CodeSystem, ValueSet bindings, code validation) will fail.

### Loading Local Implementation Guides

To load IGs from the `igs/` directory, specify the **full container path** in `docker-compose.yml`:

```yaml
IG_PARAMS=-ig /igs/your-package-2026.0.0.tgz
```

For multiple IGs:
```yaml
IG_PARAMS=-ig /igs/package1.tgz -ig /igs/package2.tgz
```

**Note:** Dependencies will still be resolved from the package cache or downloaded online if not cached.

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

2. **Configure nginx for MII Ontoserver:**
   
   <details>
   <summary>Click to show complete nginx.conf for MII Ontoserver</summary>
   
   Replace `nginx/nginx.conf` with the following configuration:
   ```nginx
   events {
       worker_connections 1024;
   }

   http {
       access_log /dev/stdout;
       error_log /dev/stderr;

       # Increase timeouts for terminology server operations
       proxy_connect_timeout 300s;
       proxy_send_timeout 300s;
       proxy_read_timeout 300s;

       server {
           listen 80;
           server_name localhost;

           # Health check endpoint
           location /health {
               access_log off;
               return 200 "healthy\n";
               add_header Content-Type text/plain;
           }

           # Redirect all other traffic to HTTPS
           location / {
               return 301 https://$host$request_uri;
           }
       }

       server {
           listen 443 ssl;
           server_name localhost;

           # Self-signed certificate for internal communication
           ssl_certificate /etc/nginx/certs/self-signed.crt;
           ssl_certificate_key /etc/nginx/certs/self-signed.key;

           # Health check endpoint
           location /health {
               access_log off;
               return 200 "healthy\n";
               add_header Content-Type text/plain;
           }

           # Proxy to MII Ontoserver with client certificate authentication
           location / {
               # Forward to MII Ontoserver
               proxy_pass https://ontoserver.mii-termserv.de;
               proxy_ssl_server_name on;

               # TLS client certificate settings
               proxy_ssl_certificate /etc/nginx/certs/client-cert.pem;
               proxy_ssl_certificate_key /etc/nginx/certs/client-key.key;

               # Optional: verify server certificate
               # proxy_ssl_verify on;
               # proxy_ssl_trusted_certificate /etc/nginx/certs/ca-cert.pem;

               # Forward headers
               proxy_set_header Host $proxy_host;
               proxy_set_header X-Real-IP $remote_addr;
               proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
               proxy_set_header X-Forwarded-Proto $scheme;

               # Handle redirects properly
               proxy_redirect off;
           }
       }
   }
   ```
   </details>

3. **Update docker-compose.yml:**
   
   <details>
   <summary>Click to show docker-compose.yml for MII Ontoserver</summary>
   
   Replace `docker-compose.yml` with this version (Blaze service removed):
   ```yaml
   services:
     validator:
       build:
         context: ./validator
         dockerfile: Dockerfile
       container_name: fhir-validator
       ports:
         - "8080:8080"
       environment:
         - JAVA_OPTS=-Xmx4g
         - FHIR_VERSION=4.0
         - TX_SERVER=https://nginx/fhir
         - IG_PARAMS=
             -ig de.basisprofil.r4#1.5.4
             -ig de.medizininformatikinitiative.kerndatensatz.meta#2026.0.0
             -ig de.medizininformatikinitiative.kerndatensatz.base#2026.0.0
             -ig de.medizininformatikinitiative.kerndatensatz.laborbefund#2026.0.0
             -ig de.medizininformatikinitiative.kerndatensatz.medikation#2026.0.0
             -ig de.medizininformatikinitiative.kerndatensatz.consent#2026.0.0
             -ig de.medizininformatikinitiative.kerndatensatz.bildgebung#2026.0.0
             -ig de.medizininformatikinitiative.kerndatensatz.biobank#2026.0.0
             -ig de.medizininformatikinitiative.kerndatensatz.molgen#2026.0.4
             -ig de.medizininformatikinitiative.kerndatensatz.onkologie#2026.0.0
             -ig de.medizininformatikinitiative.kerndatensatz.patho#2026.0.0
             -ig de.medizininformatikinitiative.kerndatensatz.icu#2026.0.0-ballot
       volumes:
         - ./validator/config:/config:ro
         - ./igs:/igs:ro
         - ./nginx/certs/self-signed.crt:/etc/nginx/certs/self-signed.crt:ro
         - fhir-package-cache:/root/.fhir/packages
       depends_on:
         nginx:
           condition: service_healthy
       networks:
         - fhir-network
       restart: unless-stopped

     nginx:
       build:
         context: ./nginx
         dockerfile: Dockerfile
       container_name: fhir-nginx
       ports:
         - "8081:80"
       volumes:
         - ./nginx/nginx.conf:/etc/nginx/nginx.conf:ro
         - ./nginx/certs:/etc/nginx/certs:ro
       networks:
         - fhir-network
       restart: unless-stopped

   networks:
     fhir-network:
       driver: bridge

   volumes:
     fhir-package-cache:
   ```
   </details>

4. **Restart services:**
   ```bash
   docker-compose down
   docker-compose up -d
   ```
   
   The validator will now use MII Ontoserver instead of Blaze.

### Using Other Terminology Servers

**For a local server without authentication (e.g., HAPI FHIR):**
- Edit `docker-compose.yml`: Change `TX_SERVER` to `http://your-server:port/fhir`
- Update nginx configuration or connect directly

**For other authenticated servers:**
- Follow steps similar to MII Ontoserver setup
- Update `nginx/nginx.conf` with correct URL and certificate paths
- Configure authentication as required by your server

## Maintenance

### Updating the Validator

```bash
cd validator
./download-validator.sh
docker-compose build validator
docker-compose up -d
```

### Certificate Renewal

**For self-signed certificates (default Blaze setup):**
```bash
./scripts/generate-self-signed-cert.sh
docker-compose restart nginx validator
```

**For MII Ontoserver client certificates:**
1. Replace certificates in `nginx/certs/`
2. Restart nginx: `docker-compose restart nginx`

