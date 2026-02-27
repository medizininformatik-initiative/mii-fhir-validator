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
│         ▲  (→ host:8080)           (→ host:8082) │
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
│           ▲                                  │ HTTPS + cert   │
└───────────┼──────────────────────────────────┼───────────────┘
            │                                  ▼
       Client                  ontoserver.mii-termserv.de
```

## Pre-configured Implementation Guides

The Docker image ships with a set of MII IGs pre-cached at build time. Refer to the list of IGs here:

- [`validator/Dockerfile`](https://github.com/medizininformatik-initiative/mii-fhir-validator/blob/main/validator/Dockerfile) — `ARG IG_LIST` defines the IGs baked into the image
- [`.env.default`](https://github.com/medizininformatik-initiative/mii-fhir-validator/blob/main/.env.default) — `IG_PARAMS` defines the default IGs loaded at runtime via `docker-compose.yml`