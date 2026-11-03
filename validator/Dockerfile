FROM alpine:3.24 AS fetch-validator
ARG VALIDATOR_VERSION=6.9.11
RUN wget -O /validator_cli.jar \
  https://github.com/hapifhir/org.hl7.fhir.core/releases/download/${VALIDATOR_VERSION}/validator_cli.jar

# Our API spec as JSON, served by nginx at GET /openapi.json instead of the upstream one.
FROM mikefarah/yq:4.54.1@sha256:4b3d9475d65571d28cbb19544d3820ec2945e4c8b2f18279394282b8dc3a592e AS openapi
COPY docs/public/openapi.yaml /tmp/openapi.yaml
RUN yq -o=json '.' /tmp/openapi.yaml > /tmp/openapi.json

FROM eclipse-temurin:17-jre

LABEL org.opencontainers.image.title="MII FHIR Validator"
LABEL org.opencontainers.image.description="A FHIR validation service pre-configured for MII Implementation Guides"
LABEL org.opencontainers.image.url="https://medizininformatik-initiative.github.io/mii-fhir-validator/"
LABEL org.opencontainers.image.licenses="Apache-2.0"
LABEL org.opencontainers.image.source="https://github.com/medizininformatik-initiative/mii-fhir-validator"

# Install required tools: wget (healthcheck), nginx (default-deny front on port 8080, #21)
RUN apt-get update && apt-get install -y --no-install-recommends wget nginx && rm -rf /var/lib/apt/lists/*

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
  -ig de.medizininformatikinitiative.kerndatensatz.base#2026.0.1 \
  -ig de.medizininformatikinitiative.kerndatensatz.laborbefund#2026.0.3 \
  -ig de.medizininformatikinitiative.kerndatensatz.medikation#2026.0.1 \
  -ig de.medizininformatikinitiative.kerndatensatz.consent#2026.0.1-rc-4 \
  -ig de.medizininformatikinitiative.kerndatensatz.bildgebung#2026.0.0 \
  -ig de.medizininformatikinitiative.kerndatensatz.biobank#2026.0.1 \
  -ig de.medizininformatikinitiative.kerndatensatz.molgen#2026.0.4 \
  -ig de.medizininformatikinitiative.kerndatensatz.onkologie#2026.0.3 \
  -ig de.medizininformatikinitiative.kerndatensatz.patho#2026.0.2 \
  -ig de.medizininformatikinitiative.kerndatensatz.icu#2025.0.4 \
  -ig de.medizininformatikinitiative.kerndatensatz.dokument#2026.0.1 \
  -ig de.medizininformatikinitiative.kerndatensatz.mikrobiologie#2027.0.0-ballot2 \
  -ig de.medizininformatikinitiative.kerndatensatz.mtb#2026.0.1 \
  -ig de.medizininformatikinitiative.kerndatensatz.pros#2026.7.0 \
  -ig de.medizininformatikinitiative.kerndatensatz.seltene#2026.0.1 \
"

# Pre-build FHIR package cache with MII IGs (downloads packages during build)
RUN java -Xmx4g -Duser.home="/app/fhir-cache" -jar validator_cli.jar ${IG_LIST} -version 4.0 -tx n/a
RUN chmod -R a+rX /app/fhir-cache

# Create directory for IGs
RUN mkdir -p /igs

# nginx (port 8080) is the only exposed listener; the validator listens on 127.0.0.1:8081.
EXPOSE 8080

# Healthy = nginx up and the validator answering (it opens its port only after loading the
# IGs); /health asks the validator on every probe. A long validation blocks the probe (single
# request thread): a blocked probe fails after ~3 s (nginx), so retries=20 allows
# 20 x (10 s + ~3 s) = ~260 s before Docker reports unhealthy.
HEALTHCHECK --interval=10s --timeout=5s --start-period=300s --retries=20 \
  CMD ["wget", "--no-proxy", "--tries=1", "--timeout=4", "-q", "-O", "/dev/null", "http://127.0.0.1:8080/health"]

# Default IG parameters - can be overridden via IG_PARAMS environment variable
ENV DEFAULT_IG_PARAMS="${IG_LIST}"

# Advisor configuration for suppressing specific validation messages
COPY validator/advisor.json /app/validator/advisor.json

# nginx front: route allowlist, static /health body and our OpenAPI spec
COPY validator/nginx.conf validator/health.json /app/validator/
COPY --from=openapi /tmp/openapi.json /app/validator/openapi.json

# Entrypoint script: generates fhir-settings.json at runtime if TX_SERVER uses HTTP
COPY validator/docker-entrypoint.sh /app/docker-entrypoint.sh
RUN chmod +x /app/docker-entrypoint.sh
ENTRYPOINT ["/bin/sh", "/app/docker-entrypoint.sh"]
