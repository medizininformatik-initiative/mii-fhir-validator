FROM eclipse-temurin:17-jre

# Install required tools
RUN apt-get update && apt-get install -y curl && rm -rf /var/lib/apt/lists/*

# Create working directory
WORKDIR /app

# Copy validator JAR (should be downloaded beforehand)
COPY validator_cli.jar /app/validator_cli.jar

# Pre-build FHIR package cache with MII IGs
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

# Create certificate import script
RUN echo '#!/bin/bash\n\
if [ -f /etc/nginx/certs/self-signed.crt ]; then\n\
  # Check if certificate is already imported\n\
  if ! keytool -list -keystore ${JAVA_HOME}/lib/security/cacerts -storepass changeit -alias nginx-self-signed &>/dev/null; then\n\
    keytool -import -trustcacerts -noprompt -alias nginx-self-signed \\\n\
      -file /etc/nginx/certs/self-signed.crt \\\n\
      -keystore ${JAVA_HOME}/lib/security/cacerts \\\n\
      -storepass changeit\n\
  fi\n\
fi' > /tmp/import-cert.sh && chmod +x /tmp/import-cert.sh

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

# Run validator in server mode
# Default parameters - can be overridden via environment variables
ENTRYPOINT ["/bin/bash", "-c", "/tmp/import-cert.sh && java ${JAVA_OPTS:--Xmx4g} -jar validator_cli.jar -server 8080 -version ${FHIR_VERSION:-4.0} ${TX_SERVER:+-tx $TX_SERVER} ${IG_PARAMS:-$DEFAULT_IG_PARAMS} -authorise-non-conformant-tx-servers"]
