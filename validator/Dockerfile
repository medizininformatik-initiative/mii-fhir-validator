FROM alpine AS fetch-validator
ARG VALIDATOR_VERSION=6.9.4
RUN wget -O /validator_cli.jar \
  https://github.com/hapifhir/org.hl7.fhir.core/releases/download/${VALIDATOR_VERSION}/validator_cli.jar

FROM eclipse-temurin:17-jre

LABEL org.opencontainers.image.title="MII FHIR Validator"
LABEL org.opencontainers.image.description="A FHIR validation service pre-configured for MII Implementation Guides"
LABEL org.opencontainers.image.url="https://medizininformatik-initiative.github.io/mii-fhir-validator/"
LABEL org.opencontainers.image.licenses="Apache-2.0"
LABEL org.opencontainers.image.source="https://github.com/medizininformatik-initiative/mii-fhir-validator"

# Install required tools
RUN apt-get update && apt-get install -y wget && rm -rf /var/lib/apt/lists/*

# Create working directory
WORKDIR /app

# Copy license files
COPY LICENSE /licenses/LICENSE
COPY THIRD_PARTY_NOTICES.md /licenses/THIRD_PARTY_NOTICES.md

# Copy validator JAR
COPY --from=fetch-validator /validator_cli.jar /app/validator_cli.jar

# IG list as build argument (keep in sync with IG_PARAMS in .env.default)
ARG IG_LIST="-ig de.basisprofil.r4#1.5.4 \
  -ig de.medizininformatikinitiative.kerndatensatz.meta#2026.0.0 \
  -ig de.medizininformatikinitiative.kerndatensatz.base#2026.0.0 \
  -ig de.medizininformatikinitiative.kerndatensatz.laborbefund#2026.0.1 \
  -ig de.medizininformatikinitiative.kerndatensatz.medikation#2026.0.1 \
  -ig de.medizininformatikinitiative.kerndatensatz.consent#2026.0.1-rc-2 \
  -ig de.medizininformatikinitiative.kerndatensatz.bildgebung#2026.0.0 \
  -ig de.medizininformatikinitiative.kerndatensatz.biobank#2026.0.1 \
  -ig de.medizininformatikinitiative.kerndatensatz.molgen#2026.0.4 \
  -ig de.medizininformatikinitiative.kerndatensatz.onkologie#2026.0.3 \
  -ig de.medizininformatikinitiative.kerndatensatz.patho#2026.0.2 \
  -ig de.medizininformatikinitiative.kerndatensatz.icu#2026.0.2 \
"

# Pre-build FHIR package cache with MII IGs (downloads packages during build)
RUN java -Xmx4g -jar validator_cli.jar ${IG_LIST} -version 4.0

# Create directory for IGs
RUN mkdir -p /igs

# Expose validator port
EXPOSE 8080

# Default IG parameters - can be overridden via IG_PARAMS environment variable
ENV DEFAULT_IG_PARAMS="${IG_LIST}"

# Advisor configuration for suppressing specific validation messages
COPY validator/advisor.json /app/validator/advisor.json

# Entrypoint script: generates fhir-settings.json at runtime if TX_SERVER uses HTTP
COPY validator/docker-entrypoint.sh /app/docker-entrypoint.sh
RUN chmod +x /app/docker-entrypoint.sh
ENTRYPOINT ["/bin/sh", "/app/docker-entrypoint.sh"]
