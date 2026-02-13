# Keycloak HTTPS Issue - Fix Guide

## Problem

When accessing Keycloak admin console, you see:
```
We are sorry...
HTTPS required
```

## Root Cause

Keycloak by default requires HTTPS for security. In development mode, we need to explicitly configure it to allow HTTP.

## Solution

### Quick Fix (Restart Keycloak)

```bash
cd scripts/service
./restart-keycloak.sh
```

This will restart Keycloak with the updated HTTP configuration.

### Manual Fix

If the quick fix doesn't work, follow these steps:

#### Step 1: Stop Keycloak

```bash
cd services
docker compose -f docker-compose.keycloak.yaml down
```

#### Step 2: Remove Old Data (Optional - only if configuration changes aren't taking effect)

```bash
docker volume rm silver_keycloak-data
```

**⚠️ Warning:** This will delete all Keycloak data including users and realms!

#### Step 3: Start Keycloak

```bash
docker compose -f docker-compose.keycloak.yaml up -d
```

#### Step 4: Check Logs

```bash
docker logs -f keycloak-server
```

Wait until you see:
```
Listening on: http://0.0.0.0:8080
```

#### Step 5: Access Keycloak

Open in browser: `http://localhost:8080/admin` or `http://your-domain:8080/admin`

**Important:** Use `http://` not `https://`

## Configuration Explanation

The `docker-compose.keycloak.yaml` now includes:

```yaml
environment:
  # Allow HTTP in development
  KC_HTTP_ENABLED: "true"
  
  # Disable strict hostname checking
  KC_HOSTNAME_STRICT: "false"
  KC_HOSTNAME_STRICT_HTTPS: "false"
  
  # Proxy settings for HTTP
  KC_PROXY: "edge"
  KC_PROXY_HEADERS: "xforwarded"
```

These settings:
- **KC_HTTP_ENABLED**: Allows HTTP connections
- **KC_HOSTNAME_STRICT**: Disables strict hostname validation
- **KC_HOSTNAME_STRICT_HTTPS**: Allows HTTP instead of requiring HTTPS
- **KC_PROXY**: Configures edge proxy mode for HTTP
- **start-dev**: Runs Keycloak in development mode

## Verification

### 1. Check if Keycloak is Running

```bash
docker ps | grep keycloak
```

Expected output:
```
keycloak-server   Up   0.0.0.0:8080->8080/tcp, 8443/tcp
```

### 2. Test HTTP Access

```bash
curl -I http://localhost:8080/
```

Expected: HTTP 200 or redirect, **not** HTTPS required error

### 3. Test Admin Console

```bash
curl http://localhost:8080/admin/
```

Should return HTML content, not HTTPS error

### 4. Test Authentication

```bash
curl -X POST http://localhost:8080/realms/master/protocol/openid-connect/token \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "client_id=admin-cli" \
  -d "username=admin" \
  -d "password=admin" \
  -d "grant_type=password"
```

Should return JSON with access_token

## Common Issues

### Issue 1: Still Getting HTTPS Required

**Cause:** Browser cached the HTTPS redirect

**Solution:**
- Clear browser cache
- Try incognito/private browsing mode
- Or use `curl` to test first

### Issue 2: Connection Refused

**Cause:** Keycloak not started or port conflict

**Solution:**
```bash
# Check if something else is using port 8080
lsof -i :8080

# If cadvisor is using it, we already moved it to 8081
# Restart Keycloak
./scripts/service/restart-keycloak.sh
```

### Issue 3: Container Keeps Restarting

**Cause:** Configuration error

**Solution:**
```bash
# Check logs for errors
docker logs keycloak-server

# Common issues:
# - Database connection problems
# - Invalid environment variables
# - Port conflicts
```

### Issue 4: Changes Not Taking Effect

**Cause:** Old configuration cached in volume

**Solution:**
```bash
# Stop container
docker compose -f services/docker-compose.keycloak.yaml down

# Remove volume (⚠️ deletes all data!)
docker volume rm silver_keycloak-data

# Start fresh
docker compose -f services/docker-compose.keycloak.yaml up -d
```

## Production Setup (HTTPS)

For production, you should use HTTPS:

### 1. Get SSL Certificates

```bash
# Using Let's Encrypt
certbot certonly --standalone -d auth.yourdomain.com
```

### 2. Update docker-compose.keycloak.yaml

```yaml
environment:
  # Production settings
  KC_HOSTNAME: "auth.yourdomain.com"
  KC_HOSTNAME_STRICT: "true"
  KC_HOSTNAME_STRICT_HTTPS: "true"
  
  # SSL certificates
  KC_HTTPS_CERTIFICATE_FILE: "/opt/keycloak/conf/server.crt.pem"
  KC_HTTPS_CERTIFICATE_KEY_FILE: "/opt/keycloak/conf/server.key.pem"

volumes:
  - /etc/letsencrypt/live/auth.yourdomain.com/fullchain.pem:/opt/keycloak/conf/server.crt.pem:ro
  - /etc/letsencrypt/live/auth.yourdomain.com/privkey.pem:/opt/keycloak/conf/server.key.pem:ro

command:
  - start  # Production mode (not start-dev)
```

### 3. Configure Reverse Proxy (Recommended)

Use nginx or Apache as reverse proxy:

```nginx
server {
    listen 443 ssl;
    server_name auth.yourdomain.com;
    
    ssl_certificate /etc/letsencrypt/live/auth.yourdomain.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/auth.yourdomain.com/privkey.pem;
    
    location / {
        proxy_pass http://localhost:8080;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

## Testing After Fix

### 1. Run the test connection script

```bash
cd scripts/service
./test-keycloak-connection.sh
```

### 2. Create a test user

```bash
cd scripts/user
./keycloak_manage_users.sh add-user testuser test@example.com TestPass123
```

### 3. Access admin console

Open: `http://localhost:8080/admin` (or your domain)
- Username: `admin`
- Password: `admin`

## Summary

**For Development (HTTP):**
- Use the updated `docker-compose.keycloak.yaml`
- Access via `http://` not `https://`
- Run `./restart-keycloak.sh` after changes

**For Production (HTTPS):**
- Get proper SSL certificates
- Update configuration for HTTPS
- Use reverse proxy (recommended)
- Change default admin password!

## Quick Commands Reference

```bash
# Restart Keycloak
./scripts/service/restart-keycloak.sh

# Check logs
docker logs -f keycloak-server

# Test connection
./scripts/service/test-keycloak-connection.sh

# Access admin console
# Browser: http://localhost:8080/admin
# Username: admin
# Password: admin
```

## Need Help?

1. Check Keycloak logs: `docker logs keycloak-server`
2. Verify configuration: `docker inspect keycloak-server`
3. Test with curl: `curl http://localhost:8080/realms/master`
4. Check the Keycloak documentation: https://www.keycloak.org/documentation
