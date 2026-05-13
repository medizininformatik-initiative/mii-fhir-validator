#!/bin/bash -e

#
# This script (get-and-upload-terminology.sh) is used as ENTRYPOINT in Dockerfile to call all other scripts
#

echo "Downloading NPM Packages"
./get-mii-terminology.sh install

echo "Uploading terminology to local FHIR Server"
./upload-terminology.sh
