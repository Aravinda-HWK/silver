# Silver Metadata Service

A Go service that sends ClamAV signature heartbeat data to the Super Platform.

This service also exposes standard OpenID Connect discovery and Thunderbird autoconfig endpoints so custom domains can advertise OAuth2-capable IMAP/SMTP settings.

## What It Does

- Monitors ClamAV signature database (`daily.cvd/cld`)
- Automatically detects server IP address
- Sends heartbeat data every 60 seconds (configurable)
- Receives results from Super Platform
- Serves `/.well-known/openid-configuration`
- Serves Thunderbird autoconfig at:
  - `/.well-known/autoconfig/mail/config-v1.1.xml`
  - `/mail/config-v1.1.xml`

## Quick Start

### 1. Configure

Edit `.env` file:
```bash
EXTERNAL_API_URL=https://your-super-platform.com/v1/silver/events
API_KEY=your-secret-api-key-here
PUSH_INTERVAL_SECONDS=60

# Optional overrides for OAuth2 discovery/autoconfig
# PUBLIC_BASE_DOMAIN=example.com
# OAUTH_ISSUER_URL=https://example.com:8090
# OAUTH_SCOPE=openid email profile
# IMAP_HOSTNAME=imap.example.com
# SMTP_HOSTNAME=smtp.example.com
```

### 2. Deploy

```bash
docker-compose up -d metadata-service
```

For Thunderbird autodiscovery from the public internet, start the `public-web` service as well. It terminates TLS on ports 80/443 and proxies discovery paths to `metadata-service`.

```bash
docker-compose up -d public-web metadata-service
```

If you need to run certbot container operations from compose, use the `certbot` profile explicitly:

```bash
docker-compose --profile certbot up -d certbot-server
```

### 3. Check Logs

```bash
docker-compose logs -f metadata-service
```

You should see:
```
Instance ID: 192.168.1.100
Sending heartbeat: {"timestamp":"2026-03-05T10:30:00Z","instance_id":"192.168.1.100"...}
Successfully pushed heartbeat to Super Platform (status: 200)
```

## Heartbeat Payload

The service sends this JSON every 60 seconds:

```json
{
  "timestamp": "2026-03-05T10:31:00Z",
  "instance_id": "192.168.1.100",
  "signature_version": "daily.cvd:27930",
  "signature_updated_at": "2026-03-04T08:55:00Z"
}
```

**Fields:**
- `timestamp` - Current time (UTC)
- `instance_id` - Server IP address (auto-detected)
- `signature_version` - ClamAV database version
- `signature_updated_at` - When signature was last updated

## Environment Variables

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `EXTERNAL_API_URL` | Yes | - | Super Platform endpoint URL |
| `API_KEY` | Yes* | - | API key for authentication |
| `PUSH_INTERVAL_SECONDS` | No | 60 | Heartbeat frequency |
| `ENABLE_PUSH_SERVICE` | No | true | Enable/disable heartbeat |
| `PORT` | No | 8888 | Service port |
| `CLAMAV_DB_PATH` | No | /var/lib/clamav | ClamAV database location |
| `PUBLIC_BASE_DOMAIN` | No | derived from request host | Base domain for discovery responses |
| `OAUTH_ISSUER_URL` | No | `https://<domain>:8090` | OAuth2 issuer used in discovery/autoconfig |
| `OAUTH_SCOPE` | No | `openid email profile` | OAuth2 scopes advertised to clients |
| `OAUTH_AUTHORIZATION_PATH` | No | `/oauth2/authorize` | Authorization endpoint path |
| `OAUTH_TOKEN_PATH` | No | `/oauth2/token` | Token endpoint path |
| `OAUTH_JWKS_PATH` | No | `/oauth2/jwks` | JWKS endpoint path |
| `OAUTH_USERINFO_PATH` | No | `/oauth2/userinfo` | Userinfo endpoint path |
| `IMAP_HOSTNAME` | No | `mail.<domain>` | IMAP host in Thunderbird XML |
| `IMAP_PORT` | No | 993 | IMAP port in Thunderbird XML |
| `SMTP_HOSTNAME` | No | `mail.<domain>` | SMTP host in Thunderbird XML |
| `SMTP_PORT` | No | 587 | SMTP port in Thunderbird XML |

*Required for receiving results from Super Platform

## API Endpoints

### GET /health

Health check (no authentication required)

```bash
curl http://localhost:8888/health
```

Response:
```json
{
  "status": "healthy",
  "timestamp": "2026-03-05T10:30:00Z"
}
```

### POST /api/results

Receive results from Super Platform (requires API key)

```bash
curl -X POST http://localhost:8888/api/results \
  -H "Content-Type: application/json" \
  -H "X-API-Key: your-secret-api-key-here" \
  -d '{
    "status": "success",
    "timestamp": "2026-03-05T10:30:00Z",
    "data": {}
  }'
```

### GET /.well-known/openid-configuration

OpenID Connect Discovery document used by clients for OAuth2/OIDC metadata.

### GET /.well-known/autoconfig/mail/config-v1.1.xml

Thunderbird autoconfig endpoint (well-known path). This is one of the standard URLs Thunderbird checks for custom domains.

### GET /mail/config-v1.1.xml

Thunderbird autoconfig endpoint for deployments that use `autoconfig.<domain>` virtual host.

## Build & Run

### Using Docker
```bash
docker-compose up -d metadata-service
```

### Using Makefile
```bash
make build    # Build binary
make run      # Run locally
make clean    # Clean up
```

### Manual Build
```bash
go build -o metadata-service main.go
./metadata-service
```

## Troubleshooting

**No heartbeats being sent?**
1. Check `EXTERNAL_API_URL` is set correctly
2. Verify `ENABLE_PUSH_SERVICE=true`
3. Check logs: `docker-compose logs metadata-service`

**Instance ID showing "unknown"?**
- Network connectivity issue
- Check logs for "Warning: could not determine server IP"

**ClamAV signature version is 0?**
1. Verify `/var/lib/clamav/daily.cvd` exists
2. Check ClamAV container is running
3. Wait for ClamAV to download signatures

**Authentication errors?**
- Verify `API_KEY` matches between client and server
- Include `X-API-Key` header in requests

## More Information

- [API Authentication Guide](./API_AUTHENTICATION.md)
- [Super Platform Integration](./SUPER_PLATFORM_INTEGRATION.md)
- [Instance ID Changes](./INSTANCE_ID_CHANGE.md)
