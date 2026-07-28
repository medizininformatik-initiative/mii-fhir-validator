FROM curlimages/curl:8.21.0 AS fetch-validator
ARG VALIDATOR_VERSION=6.9.11
RUN curl -fsSL -o /tmp/validator_cli.jar \
  https://github.com/hapifhir/org.hl7.fhir.core/releases/download/${VALIDATOR_VERSION}/validator_cli.JAR

FROM eclipse-temurin:25.0.3_9-jre-ubi10-minimal

LABEL org.opencontainers.image.title="MII FHIR Validator"
LABEL org.opencontainers.image.description="A FHIR validation service pre-configured for MII Implementation Guides"
LABEL org.opencontainers.image.url="https://medizininformatik-initiative.github.io/mii-fhir-validator/"
LABEL org.opencontainers.image.licenses="Apache-2.0"
LABEL org.opencontainers.image.source="https://github.com/medizininformatik-initiative/mii-fhir-validator"

# Create working directory and directory for IGs
WORKDIR /app

USER 10001:10001

# Copy license files
COPY LICENSE /licenses/LICENSE
COPY THIRD_PARTY_NOTICES.md /licenses/THIRD_PARTY_NOTICES.md

# Copy validator JAR
COPY --from=fetch-validator /tmp/validator_cli.jar /app/validator_cli.jar

# Für Builds hinter einem Proxy, z.B.:
#   --build-arg JAVA_TOOL_OPTIONS="-Dhttps.proxyHost=proxy.example -Dhttps.proxyPort=8080"
ARG JAVA_TOOL_OPTIONS=""

# IG list as build argument (keep in sync with IG_PARAMS in .env.default)
ARG IG_LIST="-ig de.basisprofil.r4#1.5.4 \
  -ig de.medizininformatikinitiative.kerndatensatz.meta#2026.0.0 \
  -ig de.medizininformatikinitiative.kerndatensatz.base#2026.0.1 \
  -ig de.medizininformatikinitiative.kerndatensatz.laborbefund#2026.0.3 \
  -ig de.medizininformatikinitiative.kerndatensatz.medikation#2026.0.1 \
  -ig de.medizininformatikinitiative.kerndatensatz.consent#2026.0.1-rc-2 \
  -ig de.medizininformatikinitiative.kerndatensatz.bildgebung#2026.0.0 \
  -ig de.medizininformatikinitiative.kerndatensatz.biobank#2026.0.1 \
  -ig de.medizininformatikinitiative.kerndatensatz.molgen#2026.0.4 \
  -ig de.medizininformatikinitiative.kerndatensatz.onkologie#2026.0.3 \
  -ig de.medizininformatikinitiative.kerndatensatz.patho#2026.0.2 \
  -ig de.medizininformatikinitiative.kerndatensatz.icu#2025.0.4 \
  -ig de.medizininformatikinitiative.kerndatensatz.dokument#2026.0.1 \
  -ig de.medizininformatikinitiative.kerndatensatz.mikrobiologie#2027.0.0-alpha.5 \
  -ig de.medizininformatikinitiative.kerndatensatz.mtb#2026.0.0 \
  -ig de.medizininformatikinitiative.kerndatensatz.pros#2026.4.1 \
  -ig de.medizininformatikinitiative.kerndatensatz.seltene#2026.0.1 \
  "

# Pre-build FHIR package cache with MII IGs (downloads packages during build)
RUN java -Xmx4g -Duser.home="/app/fhir-cache" -jar validator_cli.jar ${IG_LIST} -version 4.0 -tx n/a -proxy "10.10.6.12:8080" \
  && chmod -R a+rX /app/fhir-cache

# Create directory for IGs
RUN mkdir -p /igs

# Expose validator port
EXPOSE 8080

# Default IG parameters - can be overridden via IG_PARAMS environment variable
ENV DEFAULT_IG_PARAMS="${IG_LIST}"

# Advisor configuration for suppressing specific validation messages
COPY validator/advisor.json /app/validator/advisor.json

# Entrypoint script: generates fhir-settings.json at runtime if TX_SERVER uses HTTP
COPY --chmod=0555 validator/docker-entrypoint.sh /app/docker-entrypoint.sh
ENTRYPOINT ["/bin/sh", "/app/docker-entrypoint.sh"]
