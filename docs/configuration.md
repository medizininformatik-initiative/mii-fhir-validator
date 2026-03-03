# Configuration

The MII FHIR Validator is configured via environment variables. These can be set in a `.env` file (copy `.env.default` as a starting point) which Docker Compose reads automatically.

```bash
cp .env.default .env
# Edit .env with your custom values
```

---

#### `TX_SERVER`

URL of the terminology server used for terminology validation.

For the local **Blaze** profile, this points to the Blaze container inside the Docker network. For the **Ontoserver** profile, this points to the nginx proxy that forwards requests to `ontoserver.mii-termserv.de` using mTLS.

HTTP connections are enabled automatically when `TX_SERVER` starts with `http://` — the container generates the required `fhir-settings.json` at startup.

**Default (Blaze profile):** `http://blaze-terminology:8080/fhir`

**Ontoserver profile:** `http://nginx/fhir`

---

#### `FHIR_VERSION`

FHIR version used for validation.

**Default:** `4.0`

---

#### `JAVA_OPTS`

JVM options passed to the validator process. Increase `-Xmx` if you encounter out-of-memory errors.

**Default:** `-Xmx4g`

---

#### `IG_PARAMS`

Space-separated list of `-ig` parameters specifying which Implementation Guides to load. Each entry is in the form `-ig <package-id>#<version>` or `-ig /path/to/package.tgz` for local files.

See [`.env.default`](../.env.default) for the full default list of pre-configured MII IGs.

## Validator Advisor File (`advisor.json`)

The validator is started with `-advisor-file /app/validator/advisor.json`.
The default advisor file is included in the image at `validator/advisor.json`.

If you want to customize suppressions/rules without rebuilding the image, override the file via bind mount in `docker-compose.yml`:

```yaml
services:
	validator:
		volumes:
			- ./validator/advisor.json:/app/validator/advisor.json:ro
```

For the complete advisor file format and matching behavior, see the HL7 Validator Advisor Framework documentation:
[https://confluence.hl7.org/spaces/FHIR/pages/281216179/Validator+Advisor+Framework](https://confluence.hl7.org/spaces/FHIR/pages/281216179/Validator+Advisor+Framework)

## HTTP Support (`allowHttp`)

The FHIR Validator CLI requires explicit `allowHttp: true` configuration to connect to HTTP (non-HTTPS) terminology servers. The container handles this automatically: when `TX_SERVER` starts with `http://`, a `fhir-settings.json` is generated at startup with `allowHttp: true` for that URL and passed to the validator. For HTTPS or unset `TX_SERVER`, no `fhir-settings.json` is generated.

No manual `fhir-settings.json` management is needed — setting `TX_SERVER` in `.env` is sufficient.

## Blaze Terminology Server

The following environment variables control the Blaze container's behaviour (set in `docker-compose.yml`):

| Variable | Description | Default |
|---|---|---|
| `JAVA_TOOL_OPTIONS` | JVM options for Blaze | `-Xmx8g` |
| `DB_BLOCK_CACHE_SIZE` | RocksDB block cache size in MB | `1024` |
| `ENABLE_TERMINOLOGY_SERVICE` | Enable the terminology service | `true` |
| `ENABLE_TERMINOLOGY_LOINC` | Enable LOINC support | `true` |
| `ENABLE_TERMINOLOGY_SNOMED_CT` | Enable SNOMED CT support | `true` |
| `SNOMED_CT_RELEASE_PATH` | Path to the SNOMED CT release directory inside the container | `/snomed-ct-release` |
| `TERMINOLOGY_SERVICE_GRAPH_CACHE_SIZE` | Number of entries in the terminology graph cache | `100000` |

The SNOMED CT release files must be placed in the `snomed-ct-release/` directory on the host. They are mounted read-only into the Blaze container.

## Ontoserver Profile (nginx)

When using the `ontoserver` profile, the validator communicates via an nginx reverse proxy with mTLS client certificate authentication.

Client certificates must be placed in `nginx/certs/`:
- `client-cert.pem` – client certificate (PEM)
- `client-key.key` – **decrypted** private key (no passphrase)

> [!IMPORTANT]
> The terminology server MUST NOT be used for running production validations in local ETL processes. The Service Unit Terminological Services does not allow this kind of usage. For development use only. Contact [team@mail.mii-termserv.de](mailto:team@mail.mii-termserv.de) for questions.
