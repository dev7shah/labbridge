#!/bin/bash
# Run this ONCE to generate your release keystore.
# Store the generated doctransit.keystore file SECURELY — never commit it to git.
# Add it to .gitignore.

keytool -genkey -v \
  -keystore doctransit.keystore \
  -alias doctransit \
  -keyalg RSA \
  -keysize 2048 \
  -validity 10000 \
  -dname "CN=DocTransit, OU=Mobile, O=DocTransit, L=Mumbai, S=Maharashtra, C=IN"

echo ""
echo "Keystore created: doctransit.keystore"
echo "Add to your .gitignore and set these environment variables:"
echo "  KEYSTORE_FILE=android/doctransit.keystore"
echo "  KEYSTORE_PASSWORD=<your password>"
echo "  KEY_ALIAS=doctransit"
echo "  KEY_PASSWORD=<your password>"
