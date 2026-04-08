# Certificate Directory

This directory contains certificates needed for authenticating with the MII Ontoserver.

## Required Files (for MII Ontoserver only)

### Client Certificates
- `client-cert.pem` - Your client certificate for MII Ontoserver authentication
- `client-key.key` - Your decrypted private key (PEM format, unencrypted)

**Important:** If your private key is encrypted, decrypt it first:
```bash
openssl rsa -in encrypted-key.key -out client-key.key
```

## How It Works

When using the Ontoserver profile (`docker compose --profile ontoserver up`):
- The validator connects to nginx via **HTTP** (using the `allowHttp` feature)
- Nginx proxies requests to MII Ontoserver via **HTTPS**
- Client certificates are used by nginx for authentication with MII Ontoserver

**No self-signed certificates needed:** Internal communication uses HTTP, so only the client certificates for MII authentication are required

## Security Notes

⚠️ **IMPORTANT**: Client certificate files contain sensitive authentication credentials!

- **Never commit real certificates to version control** - all certificate files are ignored by git
- Use appropriate file permissions: `chmod 600 *.key *.pem`
- Keep your certificates secure and rotate them according to MII team's policies

## File Format

Certificates and keys should be in PEM format:

**Certificate:**
```
-----BEGIN CERTIFICATE-----
[Base64 encoded certificate]
-----END CERTIFICATE-----
```

**Private Key:**
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
openssl rsa -noout -modulus -in client-key.key | openssl md5
# The MD5 hashes should match
```

## Certificate Expiration

Check certificate expiration date:

```bash
openssl x509 -in client-cert.pem -noout -enddate
```
