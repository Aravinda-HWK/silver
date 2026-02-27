# Policy Service - Database vs API Approach

## Current Issue

The policy service is receiving **401 Unauthorized** errors from Thunder SCIM API because it requires authentication tokens.

## Solution Options

### Option 1: Use Shared Database (RECOMMENDED - Simplest)

Query the SQLite database directly that's shared between Raven and Thunder.

**Advantages:**
- No authentication needed
- Faster (no HTTP overhead)
- Direct access to user data
- No token expiration issues

**Disadvantages:**
- Coupled to database schema
- Need to ensure database is accessible

### Option 2: Fix Thunder Authentication  

Get proper OAuth2 token from Thunder for SCIM API access.

**Advantages:**
- Uses standard SCIM protocol
- Decoupled from database
- Better for microservices

**Disadvantages:**
- Requires token management
- Tokens expire and need refresh
- Additional HTTP latency

## Quick Fix: Use Database Approach

### Step 1: Update requirements.txt

```bash
cd services/policy-service
```

Add `aiosqlite` to `requirements.txt`:

```txt
aiohttp==3.9.1
pyyaml==6.0.1
aiosqlite==0.19.0
```

### Step 2: Update docker-compose.yaml

Add the shared database volume to policy-service:

```yaml
policy-service:
  build:
    context: ./policy-service
    dockerfile: Dockerfile
  container_name: policy-service
  expose:
    - "9000"
  environment:
    - IDP_URL=https://thunder-server:8090
    - IDP_TOKEN=${THUNDER_IDP_TOKEN:-}
    - POLICY_HOST=0.0.0.0
    - POLICY_PORT=9000
    - CONFIG_FILE=/etc/postfix/silver.yaml
    - USE_DATABASE=true  # Enable database mode
  volumes:
    - ../conf/silver.yaml:/etc/postfix/silver.yaml:ro
    - ./silver-config/raven/data:/app/data:ro  # ADD THIS LINE
  networks:
    - mail-network
  restart: unless-stopped
  depends_on:
    - raven-server  # Changed from thunder
```

### Step 3: Rebuild and Restart

```bash
cd services

# Rebuild policy service with new dependencies
docker-compose build policy-service

# Restart policy service
docker-compose up -d policy-service

# Check logs
docker logs -f policy-service
```

### Step 4: Test

```bash
# Test with a real user
echo -e "request=smtpd_access_policy\nprotocol_state=RCPT\nrecipient=user1@aravindahwk.org\n\n" | nc localhost 9000

# Should see in logs:
# INFO - User found in database: user1@aravindahwk.org
# INFO - ACCEPT: user1@aravindahwk.org
```

## Implementation

I'll provide updated code that detects if `USE_DATABASE=true` and uses database query instead of SCIM API.

The code change will be in `app/main.py`:
- Add `check_user_exists_from_db()` method
- Modify `__init__` to check `USE_DATABASE` env var
- Use database method if enabled, otherwise use SCIM API

This gives you flexibility to choose the approach.
