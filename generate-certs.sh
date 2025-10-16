#!/bin/bash

# Generate self-signed certificate for MCP development environment
CERT_DIR="./certs"
DOMAIN="demo-mcp-box.itqm.cn"

# Create certificate directory if it doesn't exist
mkdir -p "$CERT_DIR"

# Generate private key
openssl genrsa -out "$CERT_DIR/tls.key" 2048

# Generate self-signed certificate
openssl req -new -x509 -key "$CERT_DIR/tls.key" -out "$CERT_DIR/tls.crt" -days 3650 \
    -subj "/C=CN/ST=Beijing/L=Beijing/O=MCP/OU=Dev/CN=$DOMAIN"

echo "Certificate generated successfully:"
echo "  Private key: $CERT_DIR/tls.key"
echo "  Certificate: $CERT_DIR/tls.crt"