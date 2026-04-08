# Configuration

The MII FHIR Validator is configured via environment variables. Configuration is split into two tiers:

- **`JAVA_OPTS` and `IG_PARAMS`** are set via `.env` (copy `.env.default` as a starting point).
- **`FHIR_VERSION`, `TX_SERVER`, `TX_CACHE_DIR`, `TX_LOG`** have built-in defaults in `docker-compose.yml` and only need to be set in `.env` if you want to override them.

```bash
cp .env.default .env
# Edit .env with your custom values
```

`.env.default` documents all available variables (infrastructure defaults are shown as commented-out entries) and is tracked in git; `.env` is gitignored for local customization.

---

#### `TX_SERVER`

URL of the terminology server used for terminology validation.

For the local **Blaze** profile, this points to the Blaze container inside the Docker network. For the **Ontoserver** profile, this points to the nginx proxy that forwards requests to `ontoserver.mii-termserv.de` using mTLS.

HTTP connections are enabled automatically when `TX_SERVER` starts with `http://` — the container generates the required `fhir-settings.json` at startup.

**Default (Blaze profile):** `http://blaze-terminology:8080/fhir` *(set in `docker-compose.yml`)*

**Default (Ontoserver profile):** `http://nginx/fhir` *(set in `docker-compose.yml`)*

---

#### `FHIR_VERSION`

FHIR version used for validation.

**Default:** `4.0` *(set in `docker-compose.yml`)*

---

#### `JAVA_OPTS`

JVM options passed to the validator process. Increase `-Xmx` if you encounter out-of-memory errors during validation or when building the terminology cache on first startup.

**Default:** `-Xmx16g`

::: tip Memory requirements
Large bundles and the initial terminology cache warm-up can require significant Java heap space. `-Xmx16g` is recommended. Otherwise, `-Xmx8g` is usually sufficient for single-resource validation.
:::

---

#### `TX_CACHE_DIR`

Directory inside the container where terminology server responses are cached. Mapped to a persistent Docker volume so the cache is retained across container restarts, eliminating cold-start latency on subsequent startups.

**Default:** `/tmp/tx-cache` *(set in `docker-compose.yml`)*

---

#### `TX_LOG`

Path inside the container for the terminology server request log. Each validation request's TX interactions are appended to this file. Set to an empty string to disable logging.

**Default:** `/tmp/tx-cache/tx.log` *(set in `docker-compose.yml`)*

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
