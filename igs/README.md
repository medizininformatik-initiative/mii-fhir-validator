# Implementation Guides

Place FHIR Implementation Guide packages in this directory for offline validation.

## Format

Implementation Guides should be in `.tgz` format (NPM package format).

## Downloading IGs

You can download IGs from the FHIR registry:

```bash
# Example: Download from packages.fhir.org
curl -L https://packages.fhir.org/de.medizininformatikinitiative.kerndatensatz.base/2026.0.0 -o de.medizininformatikinitiative.kerndatensatz.base-2026.0.0.tgz

# Or with wget (if installed)
wget https://packages.fhir.org/de.medizininformatikinitiative.kerndatensatz.base/2026.0.0 -O de.medizininformatikinitiative.kerndatensatz.base-2026.0.0.tgz

# Or use the FHIR package manager
npm install -g fhir-package-loader
fhir-package-loader de.medizininformatikinitiative.kerndatensatz.base@2026.0.0
```

## Loading IGs in the Validator

The validator can load IGs from this directory using the `-ig` parameter:

```bash
java -jar validator_cli.jar \
  -version 4.0 \
  -ig /igs/de.medizininformatikinitiative.kerndatensatz.base-2026.0.0.tgz
```

## Pre-loading for Offline Use

For completely offline environments:

1. Download all required IGs while online
2. Place them in this directory
3. Configure the validator to use local IGs only
4. The validator will cache and use these packages
