> ⚠️ **Note:** Active development happens on the `develop` branch.
>
> ➡️ Go here: https://github.com/medizininformatik-initiative/mii-fhir-validator/tree/develop

# MII FHIR Validator Service

A locally deployable FHIR validation service. This service includes:
- FHIR Validator as a local HTTP service (with custom allowHttp support)
- Blaze terminology service (default, no authentication required)
- Support for offline Implementation Guides

**Current Configuration:** This setup uses **Blaze** as the default terminology server for local development and validation with direct HTTP connectivity. For access to the **MII Service Unit Terminology Server** (`ontoserver.mii-termserv.de`), see [Alternative: MII Ontoserver Setup](#alternative-mii-ontoserver-setup) below.

## Docker Image

Pre-built Docker images are available on GitHub Container Registry. These images include the FHIR Validator with MII Implementation Guides pre-configured.

**Quick Start with Docker:**
```bash
docker run -p 8080:8080 \
  -e TX_SERVER=http://your-terminology-server:8080/fhir \
  ghcr.io/medizininformatik-initiative/mii-fhir-validator:latest
```

For detailed Docker usage, configuration options, and examples, see **[DOCKER.md](DOCKER.md)**.

## Local Development Setup

The following instructions are for running the complete local development setup with Blaze terminology server.

### Prerequisites

- Docker and Docker Compose
- Git LFS (for patched validator JAR)
- FHIR Validator JAR file (downloaded by setup script)
> **Note:** This setup uses a patched validator JAR with `allowHttp` support (tracked via Git LFS) to enable direct HTTP connections to terminology servers. See upstream issue: https://github.com/hapifhir/org.hl7.fhir.core/issues/2312 

## Quick Start

1. **Download the FHIR validator:**
  Skip this step - the patched validator JAR is already included via Git LFS
   ```bash
   ./validator/download-validator.sh
   ```

2. **Add SNOMED CT release files (required for validation):**
   ```bash
   # Download SNOMED CT International Edition from e.g. https://www.nlm.nih.gov/healthit/snomedct/
   # Extract the release into the snomed-ct-release/ directory
   # See snomed-ct-release/README.md for detailed instructions
   ```

3. **Download MII terminology packages (required for MII validation):**
   ```bash
   ./scripts/terminology/get-mii-terminology.sh install
   ```
   This downloads CodeSystems and ValueSets that will be loaded into Blaze.

4. **Add Implementation Guides (optional):**
   Place your offline IG package files (`.tgz`) in the `igs/` directory.
   
   **For true offline operation:** You also need to pre-populate the FHIR package cache with core dependencies. See [Offline Operation](#offline-operation) below.

5. **Configure environment variables (optional):**
   ```bash
   cp .env.default .env
   # Edit .env to customize settings (TX_SERVER, IG_PARAMS, JAVA_OPTS, etc.)
   ```
   Docker Compose will automatically read `.env` for configuration. The `.env.default` file contains default values and is tracked in git, while `.env` is gitignored for local customizations.

6. **Start the services:**
   ```bash
   docker-compose up -d
   ```
   This starts the validator with direct HTTP connection to Blaze terminology server (LOINC + SNOMED CT support).

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
- **Validator** connects directly to Blaze via HTTP using the custom `allowHttp` feature configured in `fhir-settings.json`

### Validator Configuration

Configuration can be customized via environment variables:
- `FHIR_VERSION` - FHIR version (default: 4.0)
- `IG_PARAMS` - Implementation Guides to load (e.g., `-ig package#version`)
- `TX_SERVER` - Terminology server endpoint (default: `http://blaze-terminology:8080/fhir` for direct HTTP connection)
- `JAVA_OPTS` - JVM memory settings

**Using .env file (recommended):**
```bash
cp .env.default .env
# Edit .env with your custom values
```

Docker Compose automatically reads `.env` from the same directory. The `.env.default` file provides example values and is tracked in git, while `.env` is gitignored for local customization.

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

3. **Update configuration for MII Ontoserver:**
   
   Update `.env` to use nginx proxy:
   ```bash
   cp .env.default .env
   # Edit .env and change:
   TX_SERVER="https://nginx/fhir"
   ```

4. **Update docker-compose.yml:**
   
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
         - JAVA_OPTS=${JAVA_OPTS}
         - FHIR_VERSION=${FHIR_VERSION}
         - TX_SERVER=${TX_SERVER}
         - IG_PARAMS=${IG_PARAMS}
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

5. **Restart services:**
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
