# Thunder IdP Authentication Setup

## Problem

The policy service is getting 401 (Unauthorized) errors when querying Thunder's SCIM API:

```
ERROR - IdP authentication failed
ERROR - Policy service error for user@domain.com: IdP authentication error
```

This causes all mail to be deferred with:
```
action=DEFER_IF_PERMIT IdP authentication required - check IDP_TOKEN configuration
```

## Recommended Solution: Use Shared Database

Since Raven and the policy service both need user information, the simplest approach is to query the shared database directly.

### Implementation

1. **Update docker-compose.yaml**:

```yaml
policy-service:
  build:
    context: ./policy-service
  volumes:
    - ../conf/silver.yaml:/etc/postfix/silver.yaml:ro
    - ./silver-config/raven/data:/app/data:ro  # Add shared database access
```

2. **Install SQLite dependency** in `services/policy-service/requirements.txt`:

```
aiohttp==3.9.1
pyyaml==6.0.1
aiosqlite==0.19.0
```

3. **Update the code** to query database directly instead of SCIM API.

This avoids the authentication issue entirely and provides direct access to user data.

## Alternative: Get Thunder OAuth2 Token

If you prefer to use the SCIM API:

### Step 1: Access Thunder Admin Console

```bash
# Open in browser
https://your-server:8090/develop/
```

### Step 2: Create Service Application

1. Navigate to **Applications** → **New Application**
2. Create **Machine-to-Machine** app:
   - Name: `Policy Service`
   - Grant Type: `Client Credentials`
   - Scopes: `internal_user_mgt_view`

### Step 3: Get Token

```bash
curl -X POST https://localhost:8090/oauth2/token \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=client_credentials" \
  -d "client_id=YOUR_CLIENT_ID" \
  -d "client_secret=YOUR_CLIENT_SECRET" \
  -k
```

### Step 4: Add to .env

```bash
THUNDER_IDP_TOKEN=eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9...
```

### Step 5: Restart

```bash
docker-compose restart policy-service
```

## Testing

```bash
# Test policy service
echo -e "request=smtpd_access_policy\nprotocol_state=RCPT\nrecipient=user1@yourdomain.com\n\n" | nc localhost 9000

# Check logs
docker logs -f policy-service
```
