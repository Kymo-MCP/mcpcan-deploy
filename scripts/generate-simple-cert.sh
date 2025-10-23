#!/bin/bash

# Simple Self-Signed Certificate Generator
# Usage: ./generate-simple-cert.sh <domain> <days>
# Example: ./generate-simple-cert.sh example.com 365

set -e

# Check if required parameters are provided
if [ $# -ne 2 ]; then
    echo "Usage: $0 <domain> <days>"
    echo "Example: $0 example.com 365"
    exit 1
fi

DOMAIN=$1
DAYS=$2

# Validate days parameter
if ! [[ "$DAYS" =~ ^[0-9]+$ ]]; then
    echo "Error: Days must be a positive integer"
    exit 1
fi

echo "Generating self-signed certificate for domain: $DOMAIN"
echo "Certificate validity: $DAYS days"

# Create output directory if it doesn't exist
OUTPUT_DIR="./certs"
mkdir -p "$OUTPUT_DIR"

# Generate private key
echo "Generating private key..."
openssl genrsa -out "$OUTPUT_DIR/${DOMAIN}.key" 2048

# Generate certificate signing request (CSR)
echo "Generating certificate signing request..."
openssl req -new -key "$OUTPUT_DIR/${DOMAIN}.key" -out "$OUTPUT_DIR/${DOMAIN}.csr" -subj "/C=CN/ST=Beijing/L=Beijing/O=MCP/OU=Dev/CN=$DOMAIN"

# Generate self-signed certificate
echo "Generating self-signed certificate..."
openssl x509 -req -in "$OUTPUT_DIR/${DOMAIN}.csr" -signkey "$OUTPUT_DIR/${DOMAIN}.key" -out "$OUTPUT_DIR/${DOMAIN}.crt" -days "$DAYS"

# Clean up CSR file
rm "$OUTPUT_DIR/${DOMAIN}.csr"

echo "Certificate generation completed!"
echo "Private key: $OUTPUT_DIR/${DOMAIN}.key"
echo "Certificate: $OUTPUT_DIR/${DOMAIN}.crt"

# Display certificate information
echo ""
echo "Certificate information:"
openssl x509 -in "$OUTPUT_DIR/${DOMAIN}.crt" -text -noout | grep -E "(Subject:|Not Before|Not After|DNS:)"