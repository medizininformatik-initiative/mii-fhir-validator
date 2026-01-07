# Certificate Directory

This directory contains certificates needed for the FHIR validator setup.

## Required Files

### Self-Signed Certificate (Generated)
- `self-signed.crt` - Self-signed certificate for internal HTTPS
- `self-signed.key` - Private key for self-signed certificate

**Generate these by running:**
```bash
../../scripts/generate-self-signed-cert.sh
```

### Client Certificates (Provided by terminology server administrator)
- `client-cert.pem` - Your client certificate for terminology server authentication
- `client-key.key` - Your decrypted private key (PKCS8 format, unencrypted)

**Important:** If your private key is encrypted, decrypt it first:
```bash
openssl pkcs8 -in client-key-encrypted.key -out client-key.key
```

## Why Two Sets of Certificates?

1. **Self-signed certificate** (`self-signed.*`): Used for internal HTTPS between the validator and nginx
   - The FHIR validator forces HTTPS even for internal connections
   - This certificate is self-generated and only used within the Docker network

2. **Client certificates** (`client-cert.pem`, `client-key.key`): Used by nginx to authenticate with the remote terminology server
   - These are provided by the terminology server administrator
   - They enable mutual TLS (mTLS) authentication

## Security Notes

⚠️ **IMPORTANT**: Client certificate files contain sensitive authentication credentials!

- **Never commit real certificates to version control** - all certificate files are ignored by git
- Use appropriate file permissions: `chmod 600 *.key *.pem`
- The self-signed certificate is safe to regenerate anytime

## File Format

Certificates should be in PEM format:

```
-----BEGIN CERTIFICATE-----
[Base64 encoded certificate]
-----END CERTIFICATE-----
```

Keys should also be in PEM format:

```
-----BEGIN PRIVATE KEY-----
[Base64 encoded key]
-----END PRIVATE KEY-----
```
-----BEGIN PRIVATE KEY-----
[Base64 encoded private key]
-----END PRIVATE KEY-----
```

## Testing Certificates

To verify your certificate and key are valid:

```bash
# Check certificate details
openssl x509 -in client-cert.pem -text -noout

# Verify certificate and key match
openssl x509 -noout -modulus -in client-cert.pem | openssl md5
openssl rsa -noout -modulus -in client-key.pem | openssl md5
# The MD5 hashes should match
```

## Certificate Expiration

Check certificate expiration date:

```bash
openssl x509 -in client-cert.pem -noout -enddate
```
