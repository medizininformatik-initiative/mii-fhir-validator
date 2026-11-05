# Configuration

The MII FHIR Validator is configured via environment variables. Configuration is split into two tiers:

- **`JAVA_OPTS`, `IG_PARAMS`, and optional forward proxy settings** are set via `.env` (copy `.env.default` as a starting point).
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

The container generates the required `fhir-settings.json` at startup: HTTP access for `http://` URLs, credentials, and private network access (see [Terminology Server Settings](#terminology-server-settings-fhir-settings-json)).

**Default (Blaze profile):** `http://blaze-terminology:8080/fhir` *(set in `docker-compose.yml`)*

**Default (Ontoserver profile):** `http://nginx/fhir` *(set in `docker-compose.yml`)*

---

#### `TX_SERVER_USERNAME`

Username for basic authentication against the terminology server. Must be set together with `TX_SERVER_PASSWORD`. Requires `TX_SERVER` to be set.

**Default:** *(unset)*

---

#### `TX_SERVER_PASSWORD`

Password for basic authentication against the terminology server. Must be set together with `TX_SERVER_USERNAME`. Requires `TX_SERVER` to be set.

**Default:** *(unset)*

---

#### `TX_SERVER_ALLOW_PRIVATE_NETWORK`

Whether `TX_SERVER` may resolve to a private address, such as a Docker service (`blaze-terminology`, `nginx`), a Kubernetes service or an intranet host.

Since validator 6.10, Server-Side Request Forgery (SSRF) protection refuses connections to non-public addresses: loopback, link-local, RFC 1918 (including Docker's `172.16.0.0/12`), IPv6 unique local and carrier-grade NAT. The log then shows `Refusing to fetch from non-public address … for host …`. A server entry in `fhir-settings.json` with `allowPrivateNetwork: true` lifts this for that server only.

- `true` (default): the entrypoint adds `"allowPrivateNetwork": true` to the generated entry for `TX_SERVER`. Both compose profiles need this.
- `false`: retain private-address blocking for the configured terminology server. This is the usual choice for a public terminology server. If the server does resolve to a private address, validator 6.10+ can't reach it at startup: the log shows `Error fetching the server's capability statement: Refusing to fetch from non-public address …` and the container exits with code 1.

Allowed values are `true` and `false` in lowercase. Unset or empty means `true`. Any other value stops the container at startup with `Error: TX_SERVER_ALLOW_PRIVATE_NETWORK must be true or false.`

The validator image currently ships validator 6.9.11, which has no SSRF protection and ignores `allowPrivateNetwork`. The setting takes effect once the image moves to 6.10 or later.

Don't switch the protection off globally with the validator option `-ssrf-protection-enabled false`. That would also allow private addresses for every URL that validated content points to.

**Default:** `true` *(set in `docker-compose.yml`)*

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

## Forward Proxy

Outbound HTTP and HTTPS connections made by the validator can optionally be routed through a forward proxy. Leave both `FORWARD_PROXY_HOST` and `FORWARD_PROXY_PORT` unset to retain the default direct-connection behavior.

```dotenv
FORWARD_PROXY_HOST="proxy.example.org"
FORWARD_PROXY_PORT="3128"
FORWARD_PROXY_NON_PROXY_HOSTS="localhost|127.*|[::1]|blaze|blaze-terminology|nginx|*.local|*.svc|*.cluster.local"
```

`FORWARD_PROXY_HOST` must contain only the hostname or IP address, without `http://` or `https://`. Host and port must be configured together. If only one is set, the container exits with an error.

`FORWARD_PROXY_NON_PROXY_HOSTS` uses Java's pipe-separated host pattern syntax. Its default keeps the local Blaze and nginx services, loopback addresses, and common container-orchestration domains outside the forward proxy. The entrypoint translates these settings into the JVM's HTTP and HTTPS proxy properties; no changes to `JAVA_OPTS` are required.

Standard `HTTP_PROXY` and `HTTPS_PROXY` environment variables alone do not configure the Java validator. Use the variables above, or configure the equivalent JVM properties manually in `JAVA_OPTS`.

---

#### `TX_CACHE_DIR`

Directory inside the container where terminology server responses are cached. Mapped to a persistent Docker volume so the cache is retained across container restarts, eliminating cold-start latency on subsequent startups.

**Default:** `/tmp/tx-cache` *(set in `docker-compose.yml`)*

---

#### `TX_LOG`

Path inside the container for the terminology server request log. Each validation request's TX interactions are appended to this file. Set to an empty string to disable logging.

**Default:** `/tmp/tx-cache/tx.log` *(set in `docker-compose.yml`)*

---

#### `DISPLAY_ISSUES_ARE_WARNINGS`

When `true`, a `Coding.display` that doesn't match the code (for example `Invalid display … A valid display is …`) is reported as a **warning** instead of an error. The container passes the validator option `-display-issues-are-warnings`, which applies to every validation request.

Only display mismatches are downgraded. This includes a required-binding error such as `The code provided … was not found in the value set …` when the wrong display is its only cause. These remain errors:
- unknown codes;
- codes that are not members of a required value set;
- code systems or code system versions that the terminology server doesn't know.

Example: a Condition with ICD-10-GM `2025` code `E10.30` and display `Diabetes mellitus` has the wrong display. The setting doesn't help while ICD-10-GM 2025 is missing from the terminology server: the result is still "code system … not found". Once that version is loaded, the resource validates with warnings only when the setting is `true`, and with errors when it is `false`.

The `checkDisplay` query parameter of `/validateResource` still decides whether the display is checked at all (see the [API reference](api.md)).

Allowed values are `true` and `false` in lowercase. Unset or empty means `false`. Any other value stops the container at startup with `Error: DISPLAY_ISSUES_ARE_WARNINGS must be true or false.`

**Default:** `false` *(set in `docker-compose.yml`)*

---

#### `IG_PARAMS`

Space-separated list of `-ig` parameters specifying which Implementation Guides to load. Each entry is in the form `-ig <package-id>#<version>` or `-ig /path/to/package.tgz` for local files.

See [`.env.default`](../.env.default) for the full default list of pre-configured MII IGs.

`IG_PARAMS` replaces that list. To keep the MII IGs and load more, use `ADDITIONAL_IG_PARAMS`.

---

#### `ADDITIONAL_IG_PARAMS`

`-ig` parameters loaded **in addition to** the IGs from `IG_PARAMS` or, if `IG_PARAMS` is unset or empty, the image's default MII IGs. Use it to add an IG without copying, and later updating, the full default list.

```dotenv
ADDITIONAL_IG_PARAMS="-ig hl7.fhir.us.cqfmeasures#5.0.0"
```

Each entry is `-ig <package-id>#<version>` or `-ig /path/to/package.tgz`. Any other content, such as a package without `-ig`, stops the container at startup with `Error: ADDITIONAL_IG_PARAMS must be a list of "-ig <package#version|path>" pairs.`

- **Download at startup:** packages that are not in the image's cache are downloaded when the validator starts, together with their dependencies. This needs network access (or a [forward proxy](#forward-proxy)) and a writable package cache (`FHIR_HOME`). With a read-only cache, the validator stops at startup with `Read-only file system` in the log and the container exits with code 1. It makes startup longer; the health check allows 300 s before failures count. The alternative is a download during the first validation that needs the package, which can take long enough for clients to time out. For offline use, the added packages **and all their dependencies** must already be in the package cache: start the validator once while online (see [Custom IGs](use.md#custom-igs)). A local `-ig /igs/<file>.tgz` alone isn't enough when the package has dependencies that aren't cached.
- **Versions:** don't add another version of a default IG here; replace the list with `IG_PARAMS` instead. Added packages can bring other versions of shared dependencies (for example `hl7.terminology`). Check that MII resources still validate as before (`make test`).

**Default:** *(unset)*

## Exposed Endpoints

Images built from this repository after `0.0.1-alpha.9` expose only three routes on port `8080`:

| Route | Purpose |
|---|---|
| `POST /validateResource` | Validation, query parameters as documented in the [API reference](api.md) |
| `GET /health` | Readiness (see [Health Check](#health-check)) |
| `GET /openapi.json` | The API description of this image |

The FHIR Validator CLI server has more endpoints, among them `/stop` (shuts the validator down) and `/loadIG` (loads packages from caller-supplied URLs or paths into the shared engine), all without authentication. They are not reachable: the validator listens on `127.0.0.1:8081` inside the container only, and an nginx in the same container on port `8080` forwards the three routes above. Every other path returns `404`, a wrong method `405`. Endpoints added by future validator versions are blocked the same way. There is no setting to re-enable them; if you need them, run the `validator_cli.jar` directly or stay on `0.0.1-alpha.9`.

The container entrypoint supervises both processes. On `docker stop` (SIGTERM) it stops both and exits `0`; a process that hasn't stopped after 8 s is killed. If either process ends on its own, the entrypoint stops the other and the container exits with that process's exit code (`1` if it was `0`), so a restart policy can bring it back.

nginx, the PID files (`/tmp/validator.pid`, `/tmp/nginx.pid`) and `fhir-settings.json` write to `/tmp`, which must be writable; with a read-only root filesystem, mount a tmpfs or `emptyDir` there. The container exits with an error otherwise.

## Health Check

Images built from this repository after `0.0.1-alpha.9` have a Docker `HEALTHCHECK` that requests `GET http://127.0.0.1:8080/health` inside the container (`wget --no-proxy`, every 10 s, 5 s timeout). `docker compose ps` shows the validator as `healthy`, and `docker compose up --wait` waits for it.

- **What `healthy` means:** nginx runs and the validator has loaded all IGs and answers HTTP requests. `/health` asks the validator on every call (it requests the validator's own API description, which doesn't run a validation) and returns `{"status":"UP"}`; if the validator doesn't answer within 3 s it returns `500`.
- **What it does not mean:** that the terminology has been uploaded to Blaze or that terminology validation works. Run `./scripts/terminology/upload-terminology.sh` and the validation tests as before.
- **Startup:** failures during the first 300 s (`start-period`) don't count. A successful check marks the container `healthy` right away, so the start period doesn't add any waiting time.
- **Long validations:** the validator handles one HTTP request at a time, so a running validation blocks the health check until it is done. A single `/health` call fails after about 3 s when the validator doesn't answer (nginx returns `500`). Docker reports `unhealthy` only after 20 failed attempts in a row; it starts the next attempt 10 s after the previous one ends, so that's 20 × (10 s + ~3 s) ≈ 4 minutes 20 seconds, depending on scheduling. A validation that takes longer still marks the container `unhealthy` until it finishes. Docker itself never restarts an unhealthy container.

Kubernetes ignores the Docker `HEALTHCHECK`; see the probe example in the README's Kubernetes section.

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

## Terminology Server Settings (`fhir-settings.json`)

The validator reads per-server permissions and credentials from a `fhir-settings.json`. The container generates it at startup at `/tmp/fhir-settings.json`, with one server entry for `TX_SERVER`, and passes it with `-fhir-settings`. No manual `fhir-settings.json` management is needed.

An entry is written when `TX_SERVER` is set and at least one of these applies:
- it uses plain `http://`: the validator needs `allowHttp: true` to connect without HTTPS;
- credentials are set (`TX_SERVER_USERNAME`/`TX_SERVER_PASSWORD`, both required): `authenticationType: basic` with the credentials, otherwise `authenticationType: none`;
- `TX_SERVER_ALLOW_PRIVATE_NETWORK` is `true` (the default): `allowPrivateNetwork: true`.

| `TX_SERVER` scheme | Credentials | `TX_SERVER_ALLOW_PRIVATE_NETWORK` | Generated entry |
|---|---|---|---|
| `http://` | no | `true` | `authenticationType: none`, `allowHttp: true`, `allowPrivateNetwork: true` |
| `http://` | no | `false` | `authenticationType: none`, `allowHttp: true` |
| `http://` | yes | `true` | `authenticationType: basic` + credentials, `allowHttp: true`, `allowPrivateNetwork: true` |
| `http://` | yes | `false` | `authenticationType: basic` + credentials, `allowHttp: true` |
| `https://` | no | `true` | `authenticationType: none`, `allowPrivateNetwork: true` |
| `https://` | no | `false` | no `fhir-settings.json` |
| `https://` | yes | `true` | `authenticationType: basic` + credentials, `allowPrivateNetwork: true` |
| `https://` | yes | `false` | `authenticationType: basic` + credentials |

Without `TX_SERVER`, no file is generated.

**Public or private is your choice.** The entrypoint doesn't check whether `TX_SERVER` resolves to a public or a private address. With the default, even a public HTTPS server gets `allowPrivateNetwork: true`. That doesn't change connections while the server resolves to a public address, but it would still allow a later private resolution (for example after a DNS change), so set `false` for public servers. Choose the setting for where the server runs:

| Destination | Example | `TX_SERVER_ALLOW_PRIVATE_NETWORK` |
|---|---|---|
| HTTP, private | the compose profiles (`http://blaze-terminology:8080/fhir`, `http://nginx/fhir`), a cluster service | `true` (default) |
| HTTPS, private | an intranet terminology server | `true` (default) |
| HTTPS, public | a terminology server on the internet | `false` recommended |
| HTTP, public | not recommended; credentials and results travel unencrypted | `false` |

**What an entry covers.** The validator applies an entry to every request whose scheme, host and port equal those of `TX_SERVER` and whose path starts with the path of `TX_SERVER`. This is a plain prefix match, not a path-segment match: an entry for `http://tx.example/fhir` also covers `http://tx.example/fhir-other/…`. Requests to other URLs keep the default rules: HTTPS only and, from validator 6.10, no private addresses.

**Settings file precedence.** A file passed with `-fhir-settings` takes precedence over the `fhir.settings.path` system property and over `~/.fhir/fhir-settings.json`. Since an HTTPS `TX_SERVER` now also gets a generated file by default, a mounted `~/.fhir/fhir-settings.json` is no longer read in that case. If you rely on one, set `TX_SERVER_ALLOW_PRIVATE_NETWORK=false` (without credentials, so no file is generated), or move its content into the supported variables.

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
