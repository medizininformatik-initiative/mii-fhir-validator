# MII FHIR Validator Service

A locally deployable FHIR validation service that can run in environments without internet access. This service includes:
- FHIR Validator HTTP server
- Nginx proxy for certificate-based terminology server authentication
- Support for offline Implementation Guides

**Current Configuration:** This setup is configured to connect to the **MII Service Unit Terminology Server** (`ontoserver.mii-termserv.de`) which requires client certificate authentication. See [Configuration](#configuration) below for switching to a local or different terminology server.

## Prerequisites

- Docker and Docker Compose
- Java 17+ (if running validator directly)
- FHIR validator JAR file
- Client certificates for MII terminology server authentication (if using the default configuration)

## Quick Start

1. **Download the FHIR validator:**
   ```bash
   cd validator
   ./download-validator.sh
   ```

2. **Generate self-signed certificate for internal HTTPS:**
   ```bash
   ./scripts/generate-self-signed-cert.sh
   ```
   This creates `nginx/certs/self-signed.crt` and `nginx/certs/self-signed.key` needed for the validator's internal HTTPS connection to nginx.

3. **Add your client certificates for terminology server:**
   Place your client certificate and key in `nginx/certs/`:
   - `client-cert.pem` - Your client certificate
   - `client-key.key` - Your decrypted private key (PKCS8 format, unencrypted)

   **Note:** If your key is encrypted, decrypt it first:
   ```bash
   openssl pkcs8 -in client-key-encrypted.key -out nginx/certs/client-key.key
   ```

4. **Add Implementation Guides (optional):**
   Place your offline IG package files (`.tgz`) in the `igs/` directory.
   
   **For true offline operation:** You also need to pre-populate the FHIR package cache with core dependencies. See [Offline Operation](#offline-operation) below.

5. **Start the services:**
   ```bash
   docker-compose up -d
   ```

5. **Access the validator:**
   - Validator API: `http://localhost:8080`
   - Nginx proxy (terminology server): `http://localhost:8081`

## Configuration

### Terminology Server

**Default:** The setup is configured for the MII terminology server at `https://ontoserver.mii-termserv.de` (configured in `nginx/nginx.conf`).

**To use a different terminology server:**

1. **For a local/offline server without authentication:**
   - Edit `docker-compose.yml`: Change `TX_SERVER` to `http://your-server:port/fhir`
   - Optionally remove the nginx service if authentication isn't needed
   - Remove certificate-related configuration

2. **For a different authenticated server:**
   - Edit `nginx/nginx.conf`: Update `proxy_pass` URL
   - Replace certificates in `nginx/certs/` with your server's client certificates

3. **For completely offline validation:**
   - Set `TX_SERVER` to `n/a` in `docker-compose.yml` to disable terminology validation
   - Pre-download all required Implementation Guides to the `igs/` directory

### Validator Configuration

Edit `docker-compose.yml` environment variables to customize:
- `FHIR_VERSION` - FHIR version (e.g., 4.0)
- `IG_PARAMS` - Implementation Guides to load (e.g., `-ig package#version`)
- `TX_SERVER` - Terminology server endpoint (default: `https://nginx/fhir` which proxies to MII)
- `JAVA_OPTS` - JVM memory settings

### Nginx Configuration

Edit `nginx/nginx.conf` to update:
- **Terminology server URL** - Currently set to `https://ontoserver.mii-termserv.de`
- Certificate paths
- Port bindings

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

```bash
java -jar validator/validator_cli.jar \
  -server 8080 \
  -version 4.0 \
  -ig de.medizininformatikinitiative.kerndatensatz.base#2026.0.0 \
  -tx https://nginx/fhir
```

## Offline Operation

This validator can work in completely offline environments, but requires preparation:

### Important: True Offline Operation Requires Pre-populated Package Cache

The validator needs **all dependencies** available offline, not just your IGs. When starting, it downloads:
- Core FHIR spec (e.g., `hl7.fhir.r4.core#4.0.1`)
- Terminology packages (e.g., `hl7.terminology.r4#6.2.0`)
- Extension packages (e.g., `hl7.fhir.uv.extensions.r4#5.2.0`)
- IG dependencies (e.g., `de.basisprofil.r4#1.5.4`)

**To prepare for offline use:**

1. **Run the validator once online** to populate the package cache:
   ```bash
   docker-compose up -d
   # Wait for all packages to download (check logs: docker-compose logs validator)
   docker-compose down
   ```

2. **Extract the package cache** from the container:
   ```bash
   # Create a volume to persist the package cache
   # Add to docker-compose.yml under validator volumes:
   # - fhir-package-cache:/root/.fhir/packages
   ```

3. **For deployment**, include the pre-populated package cache volume

### Option 1: Offline with Local Terminology Server
1. Pre-populate package cache (see above)
2. Place your IG `.tgz` files in `igs/` directory
3. Set up a local terminology server (e.g., Ontoserver, HAPI FHIR)
4. Update `nginx/nginx.conf` to point to your local server, or set `TX_SERVER` to `http://local-server:port/fhir`

### Option 2: Completely Offline (No Terminology Validation)
1. Pre-populate package cache (see above)
2. Place your IG `.tgz` files in `igs/` directory
3. Edit `docker-compose.yml`: Set `TX_SERVER=-tx n/a`
4. Remove the nginx service dependency
5. **Note:** Terminology validation (CodeSystem, ValueSet lookups) will not be performed

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

## Maintenance

### Updating the Validator

```bash
cd validator
./download-validator.sh
docker-compose build validator
docker-compose up -d
```

### Certificate Renewal

1. Replace certificates in `nginx/certs/`
2. Restart nginx: `docker-compose restart nginx`

## Troubleshooting

- **Connection refused**: Check if services are running with `docker-compose ps`
- **Certificate errors**: Verify certificate paths in `nginx/nginx.conf`
- **Validation errors**: Check validator logs with `docker-compose logs validator`
- **"Error fetching" package messages**: 
  - If using local IGs: Ensure path is `/igs/filename.tgz` not just `filename.tgz`
  - If offline: Package cache may not be populated. Run once online first to download dependencies
