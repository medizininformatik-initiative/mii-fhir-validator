# Scripts need Node Package Manager (npm) for download of FHIR packages which are NPM format; Alternate: Debian based Node JS image
FROM node:alpine@sha256:6bd9ab43c0ec0190ca7b2d193906cb8b7edf6e7f4afa43ddeccd6452710bffb5

# Need bash (not part of alpine) to run the terminology scripts
# Upload scripts need jq and curl
RUN apk update && apk add --no-cache bash jq curl

WORKDIR /app

COPY . .

ENTRYPOINT ["bash", "/app/get-and-upload-terminology.sh"]
