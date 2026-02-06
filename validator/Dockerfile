FROM eclipse-temurin:17-jre

# Install required tools
RUN apt-get update && apt-get install -y curl && rm -rf /var/lib/apt/lists/*

# Create working directory
WORKDIR /app

# Copy validator JAR - supports both patched (allowHttp) and standard versions
# The build will use whichever JAR file is present
COPY validator_cli*.jar /app/validator_cli.jar

# Copy FHIR settings file
COPY fhir-settings.json /app/fhir-settings.json

# Pre-build FHIR package cache with MII IGs (downloads packages during build)
RUN java -Xmx4g -jar validator_cli.jar \
  -ig de.basisprofil.r4#1.5.4 \
  -ig de.medizininformatikinitiative.kerndatensatz.meta#2026.0.0 \
  -ig de.medizininformatikinitiative.kerndatensatz.base#2026.0.0 \
  -ig de.medizininformatikinitiative.kerndatensatz.laborbefund#2026.0.0 \
  -ig de.medizininformatikinitiative.kerndatensatz.medikation#2026.0.0 \
  -ig de.medizininformatikinitiative.kerndatensatz.consent#2026.0.0 \
  -ig de.medizininformatikinitiative.kerndatensatz.bildgebung#2026.0.0 \
  -ig de.medizininformatikinitiative.kerndatensatz.biobank#2026.0.0 \
  -ig de.medizininformatikinitiative.kerndatensatz.molgen#2026.0.4 \
  -ig de.medizininformatikinitiative.kerndatensatz.onkologie#2026.0.0 \
  -ig de.medizininformatikinitiative.kerndatensatz.patho#2026.0.0 \
  -ig de.medizininformatikinitiative.kerndatensatz.icu#2026.0.0-ballot \
  -version 4.0

# Create directory for IGs
RUN mkdir -p /igs

# Expose validator port
EXPOSE 8080

# Default IG parameters - can be overridden via IG_PARAMS environment variable
ENV DEFAULT_IG_PARAMS="-ig de.basisprofil.r4#1.5.4 \
-ig de.medizininformatikinitiative.kerndatensatz.meta#2026.0.0 \
-ig de.medizininformatikinitiative.kerndatensatz.base#2026.0.0 \
-ig de.medizininformatikinitiative.kerndatensatz.laborbefund#2026.0.0 \
-ig de.medizininformatikinitiative.kerndatensatz.medikation#2026.0.0 \
-ig de.medizininformatikinitiative.kerndatensatz.consent#2026.0.0 \
-ig de.medizininformatikinitiative.kerndatensatz.bildgebung#2026.0.0 \
-ig de.medizininformatikinitiative.kerndatensatz.biobank#2026.0.0 \
-ig de.medizininformatikinitiative.kerndatensatz.molgen#2026.0.4 \
-ig de.medizininformatikinitiative.kerndatensatz.onkologie#2026.0.0 \
-ig de.medizininformatikinitiative.kerndatensatz.patho#2026.0.0 \
-ig de.medizininformatikinitiative.kerndatensatz.icu#2026.0.0-ballot"

# Run validator in server mode with HTTP support via fhir-settings.json
# Default parameters - can be overridden via environment variables
ENTRYPOINT ["/bin/bash", "-c", "java ${JAVA_OPTS:--Xmx4g} -jar validator_cli.jar -server 8080 -version ${FHIR_VERSION:-4.0} ${TX_SERVER:+-tx $TX_SERVER} -fhir-settings /app/fhir-settings.json ${IG_PARAMS:-$DEFAULT_IG_PARAMS} -authorise-non-conformant-tx-servers"]
