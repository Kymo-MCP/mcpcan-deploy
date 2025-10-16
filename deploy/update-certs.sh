#!/bin/bash

# Update certificates in values-dev.yaml from generated certificate files
CERT_DIR="./certs"
VALUES_FILE="./helm/values-dev.yaml"

if [ ! -f "$CERT_DIR/tls.crt" ] || [ ! -f "$CERT_DIR/tls.key" ]; then
    echo "Certificate files not found. Please run ./generate-certs.sh first."
    exit 1
fi

# Read certificate and key files
CERT_CONTENT=$(cat "$CERT_DIR/tls.crt" | sed 's/^/      /')
KEY_CONTENT=$(cat "$CERT_DIR/tls.key" | sed 's/^/      /')

# Update only the secrets section in values-dev.yaml
# Create a temporary file to store the updated content
temp_file=$(mktemp)

# Read the original file and replace only the secrets section
awk '
BEGIN { in_secrets = 0; in_tls = 0; skip_content = 0 }
/^secrets:/ { in_secrets = 1; print; next }
in_secrets && /^  tls:/ { in_tls = 1; print; next }
in_tls && /^    crt: \|/ { 
    print "    crt: |"
    print "'"$CERT_CONTENT"'"
    skip_content = 1
    next 
}
in_tls && /^    key: \|/ { 
    print "    key: |"
    print "'"$KEY_CONTENT"'"
    skip_content = 1
    next 
}
skip_content && /^      / { next }
skip_content && !/^      / { skip_content = 0 }
/^[a-zA-Z]/ && !/^secrets:/ { in_secrets = 0; in_tls = 0; skip_content = 0 }
!skip_content { print }
' "$VALUES_FILE" > "$temp_file"

# Replace the original file
mv "$temp_file" "$VALUES_FILE"

echo "Certificates updated in $VALUES_FILE successfully!"