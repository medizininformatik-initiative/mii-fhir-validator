# Known Limitations

This page documents known limitations and caveats of the MII FHIR Validator service.

---

## Terminology Validation Requires a Running Terminology Server

The validator relies on an external terminology server for all terminology-dependent validation steps (CodeSystem `$validate-code`, ValueSet `$expand`, ValueSet `$validate-code`). If no terminology server is configured or the server is unreachable, validation will fail and produce errors.

The terminology server must be a FHIR terminology server supported by the [HL7 FHIR Validator CLI](https://confluence.hl7.org/spaces/FHIR/pages/35718580/Using+the+FHIR+Validator#UsingtheFHIRValidator-AlternateTerminologyServers). This can be:
- The local Blaze server provided via `docker-compose.yml` (default)
- The MII SU-TermServ Ontoserver via the nginx proxy (development only — see below)
- Any other compatible FHIR terminology server you operate yourself, pointed to via `TX_SERVER`

### Only terminology content present on the server can be validated

The validator can only validate codes and ValueSets that the terminology server actually knows about. If a CodeSystem or ValueSet is not loaded on the terminology server, validation against it will fail or be skipped.

This has a practical consequences: certain terminologies, e.g. HGNC or HGVS in genetics, do not yet have an available machine-readable CodeSystem representation. These codes cannot be fully validated by the terminology server and may produce warnings or errors that cannot be resolved until such a representation exists.

---

## SNOMED CT Release Files Required for Blaze

Blaze will not use SNOMED unless a full SNOMED International Release is present in `snomed-ct-release/`. SNOMED releases cannot be bundled in the repository.

**Workaround:** Download the SNOMED CT International Edition separately from https://www.nlm.nih.gov/healthit/snomedct/ and extract it into the `snomed-ct-release/` directory.

---

## Terminology Resources Must Be Uploaded to Blaze After First Start

Blaze starts empty. CodeSystems and ValueSets required for validation must be explicitly uploaded via `./scripts/terminology/upload-terminology.sh` after Blaze is healthy. Validation will return errors for any terminology-bound elements until this step is completed.

---

## Offline Operation Requires Pre-populated Package Cache

When starting without internet access, the FHIR Validator CLI must have all dependent packages already in its package cache (persisted via the `fhir-package-cache` Docker volume). Starting offline without a pre-populated cache will cause the validator to fail to load IGs.

**Workaround:** Run the validator at least once while online before switching to offline mode.

---

## MII Ontoserver Must Not Be Used for Production ETL

The MII SU-TermServ Ontoserver (`ontoserver.mii-termserv.de`) is intended for development purposes only (small numbers of validation requests, no personal/patient data). Using it for batch/production validation in ETL processes violates the terms of use.

---

## HTTP Terminology Servers Must Be Allow-listed in `fhir-settings.json`

The FHIR Validator CLI rejects HTTP (non-HTTPS) connections to terminology servers unless they are explicitly listed in `fhir-settings.json` with `"allowHttp": true`. The default configuration allows `http://blaze-terminology:8080/fhir` and `http://nginx/fhir`. Any other HTTP server will be rejected.

**Workaround:** Mount a custom `fhir-settings.json` with your server URL listed.

---