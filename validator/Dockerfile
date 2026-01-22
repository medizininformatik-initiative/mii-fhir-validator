FROM eclipse-temurin:17-jre

# Install required tools
RUN apt-get update && apt-get install -y curl && rm -rf /var/lib/apt/lists/*

# Create working directory
WORKDIR /app

# Copy validator JAR (should be downloaded beforehand)
COPY validator_cli.jar /app/validator_cli.jar

# Copy configuration
COPY config/ /config/

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

# Run validator in server mode
# Default parameters - can be overridden via environment variables
ENTRYPOINT ["/bin/bash", "-c", "/tmp/import-cert.sh && java ${JAVA_OPTS:--Xmx4g} -jar validator_cli.jar -server 8080 -version ${FHIR_VERSION:-4.0} ${TX_SERVER:+-tx $TX_SERVER} ${IG_PARAMS} -authorise-non-conformant-tx-servers"]
