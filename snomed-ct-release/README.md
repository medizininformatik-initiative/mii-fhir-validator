# SNOMED CT Release Files

This directory is for placing SNOMED CT release files to enable the terminology validation capabilities of the Blaze server.

## What to Place Here

Download and **extract** the official SNOMED CT release files into this directory. The files should follow the standard SNOMED CT release structure.

### Download and Extract Steps

1. **Download** the SNOMED CT International Edition ZIP file (e.g., `SnomedCT_InternationalRF2_PRODUCTION_20250701T120000Z.zip`)
2. **Extract the ZIP file** into this directory
3. The extracted folder will be named something like `SnomedCT_InternationalRF2_PRODUCTION_20250701T120000Z/`
4. **Update `docker-compose.yml`** to point to your extracted folder:
   ```yaml
   volumes:
     - ./snomed-ct-release/SnomedCT_InternationalRF2_PRODUCTION_20250701T120000Z:/snomed-ct-release:ro
   ```

### Expected Directory Structure After Extraction

```
snomed-ct-release/
├── README.md  (this file)
├── SnomedCT_InternationalRF2_PRODUCTION_20250701T120000Z.zip  (downloaded)
└── SnomedCT_InternationalRF2_PRODUCTION_20250701T120000Z/  (extracted - mount this in docker-compose.yml)
    ├── Snapshot/
    │   └── Terminology/
    │       ├── sct2_Concept_Snapshot_*.txt
    │       ├── sct2_Description_Snapshot_*.txt
    │       └── sct2_Relationship_Snapshot_*.txt
    └── Full/
```

**Important:** The docker-compose.yml volume mount must point to the **extracted folder**, not the parent `snomed-ct-release/` directory.

## MII Core Data Set SNOMED CT Version Requirements

The MII Core Data Set releases depend on specific SNOMED CT International Edition versions:

| MII Release (CalVer) | SNOMED CT Version (International) | Specific Version String |
|----------------------|-----------------------------------|-------------------------|
| v2025.* | 2024-07-01 | `http://snomed.info/sct/900000000000207008/version/20240701` |
| v2026.* | 2025-07-01 | `http://snomed.info/sct/900000000000207008/version/20250701` |

**Important:** Ensure you download and place the correct SNOMED CT International Edition version that matches your MII Core Data Set release. Using the wrong version may cause validation errors or missed validation issues.

## How It's Used

The `docker-compose.yml` configuration mounts this directory and sets the `SNOMED_CT_RELEASE_PATH` environment variable:

```yaml
blaze:
  volumes:
    - ./snomed-ct-release:/snomed-ct-release
  environment:
    - SNOMED_CT_RELEASE_PATH=/snomed-ct-release
```

Blaze will detect and load SNOMED CT files from this location.
