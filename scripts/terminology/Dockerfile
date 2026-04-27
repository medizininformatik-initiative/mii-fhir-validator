# Scripts need Node Package Manager (npm) for download of FHIR packages which are NPM format; Alternate: Debian based Node JS image
FROM node:alpine

# Need bash (not part of alpine) to run the terminology scripts
# Upload scripts need jq and curl
RUN apk update && apk add --no-cache bash jq curl

WORKDIR /app

COPY . .

ENTRYPOINT ["bash", "/app/get-and-upload-terminology.sh"]
