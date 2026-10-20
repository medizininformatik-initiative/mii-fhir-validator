# Overview

## Purpose

This repository publishes a **Docker image** of the [HL7 FHIR Validator CLI](https://confluence.hl7.org/spaces/FHIR/pages/35718580/Using+the+FHIR+Validator) pre-configured for the [Medical Informatics Initiative (MII)](https://www.medizininformatik-initiative.de/). The image contains only the validator and the pre-cached MII IGs. **A terminology server must be provided separately** and pointed to via the `TX_SERVER` environment variable.

The published image provides:

- The FHIR Validator CLI exposed as an HTTP service
- Pre-configured and pre-cached MII Implementation Guides
- HTTP terminology server support (`allowHttp` auto-configured from `TX_SERVER`)
- Configurable via environment variables (`TX_SERVER`, `IG_PARAMS`, `JAVA_OPTS`, …)

This repository also provides a **`docker-compose.yml`** as a convenience setup for local development and offline use. It bundles a [Blaze](https://samply.github.io/blaze/) FHIR server as a local terminology service, and an optional nginx reverse proxy for authenticated access to the MII Ontoserver.

> **In short:** run the published image standalone if you already have a terminology server. Use `docker compose` from this repo if you need a complete local setup.

## Architecture

The `docker-compose.yml` in this repository offers two deployment profiles:

### Blaze Profile (Default – Local Development)

The validator runs alongside a local [Blaze](https://samply.github.io/blaze/) FHIR server that acts as the terminology service. Blaze is loaded with LOINC and SNOMED CT support and communicates with the validator over plain HTTP inside the Docker network.

```
┌─────────────────────────────────────────────────┐
│  Docker Network (fhir-network)                  │
│                                                 │
│  ┌──────────────────┐    HTTP     ┌───────────┐ │
│  │  FHIR Validator  │ ──────────► │   Blaze   │ │
│  │  :8080           │   TX calls  │   :8080   │ │
│  └──────────────────┘             └───────────┘ │
│         ▲  (→ host:8080)          (→ host:8082) │
└─────────┼───────────────────────────────────────┘
          │  POST /validateResource
     Client (localhost:8080)
          │  [Blaze FHIR API also accessible at localhost:8082]
```

### Ontoserver Profile (MII SU-TermServ)

The validator connects to an nginx reverse proxy that authenticates to the MII SU-TermServ (`ontoserver.mii-termserv.de`) using mTLS client certificates.

```
┌──────────────────────────────────────────────────────────────┐
│  Docker Network (fhir-network)                               │
│                                                              │
│  ┌──────────────────┐    HTTP     ┌───────────────────────┐  │
│  │  FHIR Validator  │ ──────────► │  nginx (mTLS proxy)   │  │
│  │  :8080           │             │  :80                  │  │
│  └──────────────────┘             └───────────────────────┘  │
│           ▲                                  │ HTTPS + cert  │
└───────────┼──────────────────────────────────┼───────────────┘
            │                                  ▼
       Client                  ontoserver.mii-termserv.de
```

## Pre-configured Implementation Guides

The Docker image ships with a set of MII IGs and their dependencies pre-cached at build time.

### Validating the 2026 MII Core Data Set

Use release **`v0.0.1-alpha.9`** to validate against the **2026 MII Core Data Set (CDS / KDS) Implementation Guides**. Pin the Docker image to this version to retain the 2026 package set when development moves to the 2027 IGs:

```yaml
image: ghcr.io/medizininformatik-initiative/mii-fhir-validator:0.0.1-alpha.9
```

For the 2026 release line, it was agreed to **pre-apply the microbiology IG from the 2027 release line** and **keep ICU on its 2025 version**. Accordingly, this validator release includes microbiology `2027.0.0-ballot2` and ICU `2025.0.4`. These are intentional exceptions to the 2026 package versions. The consent IG is included at `2026.0.1-rc-4`.

The following table lists all explicitly configured IG packages in `v0.0.1-alpha.9`; transitive dependencies are also cached in the image.

| Package | Version |
| --- | --- |
| `de.basisprofil.r4` | `1.5.4` |
| `de.medizininformatikinitiative.kerndatensatz.meta` | `2026.0.0` |
| `de.medizininformatikinitiative.kerndatensatz.base` | `2026.0.1` |
| `de.medizininformatikinitiative.kerndatensatz.laborbefund` | `2026.0.3` |
| `de.medizininformatikinitiative.kerndatensatz.medikation` | `2026.0.1` |
| `de.medizininformatikinitiative.kerndatensatz.consent` | `2026.0.1-rc-4` |
| `de.medizininformatikinitiative.kerndatensatz.bildgebung` | `2026.0.0` |
| `de.medizininformatikinitiative.kerndatensatz.biobank` | `2026.0.1` |
| `de.medizininformatikinitiative.kerndatensatz.molgen` | `2026.0.4` |
| `de.medizininformatikinitiative.kerndatensatz.onkologie` | `2026.0.3` |
| `de.medizininformatikinitiative.kerndatensatz.patho` | `2026.0.2` |
| `de.medizininformatikinitiative.kerndatensatz.icu` | `2025.0.4` |
| `de.medizininformatikinitiative.kerndatensatz.dokument` | `2026.0.1` |
| `de.medizininformatikinitiative.kerndatensatz.mikrobiologie` | `2027.0.0-ballot2` |
| `de.medizininformatikinitiative.kerndatensatz.mtb` | `2026.0.1` |
| `de.medizininformatikinitiative.kerndatensatz.pros` | `2026.7.0` |
| `de.medizininformatikinitiative.kerndatensatz.seltene` | `2026.0.1` |

The release configuration is recorded in:

- [`validator/Dockerfile` at `v0.0.1-alpha.9`](https://github.com/medizininformatik-initiative/mii-fhir-validator/blob/v0.0.1-alpha.9/validator/Dockerfile) — `ARG IG_LIST` defines the IGs baked into the image.
- [`.env.default` at `v0.0.1-alpha.9`](https://github.com/medizininformatik-initiative/mii-fhir-validator/blob/v0.0.1-alpha.9/.env.default) — `IG_PARAMS` defines the default IGs loaded at runtime via `docker-compose.yml`.

An existing `.env` file can override the image's default package set through `IG_PARAMS`. To use the 2026 set, align that variable with this release's `.env.default`, or leave it unset or empty to use the image defaults.
