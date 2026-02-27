# Policy Service Fix - Database Mode

## Problem Summary

Your policy service was getting **401 Unauthorized** errors from Thunder SCIM API, causing all mail to be deferred:

```
ERROR - IdP authentication failed
ERROR - Policy service error for user1@aravindahwk.org: IdP authentication error
```

## Root Cause

1. **Thunder requires authentication** for SCIM API access
2. **No IDP_TOKEN was configured** in environment
3. **Policy service had "fail-open" behavior** for auth errors (returned DUNNO), allowing mail through even when it couldn't verify users

## Solution Applied

### 1. Changed Error Handling

**Before:** Authentication errors returned `DUNNO` (accept mail)
**After:** All errors return `DEFER_IF_PERMIT` (temporary failure, retry later)

This ensures mail is **NOT delivered** when we can't verify recipients.

### 2. Added Database Mode

Added ability to query the shared SQLite database directly instead of using Thunder SCIM API.

**Advantages:**
- ✅ No authentication needed
- ✅ Faster (no HTTP overhead)  
- ✅ More reliable (no network issues)
- ✅ Direct access to user data

### 3. Configuration Changes

**docker-compose.yaml:**
```yaml
policy-service:
  environment:
    - USE_DATABASE=true  # ← NEW: Enable database mode
    - DB_PATH=/app/data/databases/shared.db
  volumes:
    - ./silver-config/raven/data:/app/data:ro  # ← NEW: Mount shared database
  depends_on:
    - raven-server  # ← Changed from thunder
```

**app/main.py:**
- Added `check_user_exists_from_db()` method
- Added `USE_DATABASE` environment variable support
- Modified error handling to always defer on errors
- Enhanced logging with better error messages

## Deployment Steps

### Step 1: Rebuild Policy Service

```bash
cd services

# Rebuild with updated code
docker-compose build policy-service
```

### Step 2: Restart Policy Service

```bash
# Stop old container
docker-compose down policy-service

# Start new container
docker-compose up -d policy-service
```

### Step 3: Verify Logs

```bash
# Check startup logs
docker logs policy-service

# Expected output:
# INFO - Starting Postfix Policy Service
# INFO - Mode: Database (path: /app/data/databases/shared.db)
# INFO - Listening on 0.0.0.0:9000
# INFO - Policy service initialized (mode: database)
# INFO - Policy service running on ('0.0.0.0', 9000)
```

### Step 4: Test Policy Service

```bash
# Test with a real user email
echo -e "request=smtpd_access_policy\nprotocol_state=RCPT\nrecipient=user1@aravindahwk.org\n\n" | nc localhost 9000
```

**Expected for existing user:**
```
action=DUNNO
```

**Expected for non-existent user:**
```
action=REJECT 5.1.1 <baduser@aravindahwk.org>: Recipient address rejected: User unknown in virtual mailbox table
```

### Step 5: Restart SMTP Server

```bash
# Restart to pick up policy service
docker-compose restart smtp-server
```

### Step 6: Test End-to-End

```bash
# Send test email to non-existent user
echo "Test" | mail -s "Test" nonexistent@aravindahwk.org

# Check SMTP logs
docker logs smtp-server-container | grep "User unknown"

# Expected:
# postfix/smtpd: NOQUEUE: reject: RCPT from [...]: 550 5.1.1 <nonexistent@aravindahwk.org>: Recipient address rejected: User unknown in virtual mailbox table
```

## Verification

### Check Policy Service Logs

```bash
docker logs -f policy-service
```

**Good logs (user exists):**
```
INFO - Processing request: protocol_state=RCPT, recipient=user1@aravindahwk.org, client=209.85.160.182
INFO - User found in database: user1@aravindahwk.org
INFO - ACCEPT: user1@aravindahwk.org
```

**Good logs (user not found):**
```
INFO - Processing request: protocol_state=RCPT, recipient=baduser@aravindahwk.org, client=209.85.160.182
INFO - User not found in database: baduser@aravindahwk.org
INFO - REJECT: baduser@aravindahwk.org
```

**Bad logs (database error):**
```
ERROR - Cannot open database at /app/data/databases/shared.db: unable to open database file
```

If you see database errors, check:
1. Volume is mounted correctly
2. Database file exists: `docker exec policy-service ls -la /app/data/databases/`
3. Permissions are correct

## Troubleshooting

### Database Not Found

```bash
# Check if database exists
docker exec policy-service ls -la /app/data/databases/

# Check raven logs
docker logs raven

# Ensure raven has created the database
docker exec raven ls -la /app/data/databases/
```

### Still Using API Mode

Check environment variables:
```bash
docker exec policy-service env | grep USE_DATABASE

# Should show:
# USE_DATABASE=true
```

If not, rebuild:
```bash
docker-compose down policy-service
docker-compose up -d policy-service
```

### Mail Still Being Accepted

Check Postfix configuration:
```bash
docker exec smtp-server-container postconf smtpd_recipient_restrictions

# Should include:
# check_policy_service inet:policy-service:9000
```

Restart SMTP server:
```bash
docker-compose restart smtp-server
```

## Reverting to API Mode

If you want to use Thunder SCIM API instead:

1. **Get OAuth2 token** from Thunder (see THUNDER_AUTH.md)
2. **Set in .env:**
   ```bash
   THUNDER_IDP_TOKEN=eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9...
   ```
3. **Update docker-compose.yaml:**
   ```yaml
   environment:
     - USE_DATABASE=false  # ← Change to false
   depends_on:
     - thunder  # ← Change back to thunder
   ```
4. **Rebuild and restart:**
   ```bash
   docker-compose build policy-service
   docker-compose restart policy-service
   ```

## Summary of Changes

| File | Change |
|------|--------|
| `app/main.py` | Added database mode, fixed error handling |
| `docker-compose.yaml` | Enabled `USE_DATABASE=true`, mounted shared database |
| Error behavior | Changed from fail-open to fail-closed (defer on errors) |
| Dependency | Changed from `thunder` to `raven-server` |

## Expected Behavior Now

| Scenario | Old Behavior | New Behavior |
|----------|--------------|--------------|
| User exists | ✅ Accept | ✅ Accept |
| User not found | ✅ Accept (wrong!) | ❌ Reject |
| Auth error (401) | ✅ Accept (wrong!) | ⏳ Defer |
| Database error | ✅ Accept (wrong!) | ⏳ Defer |
| Network error | ⏳ Defer | ⏳ Defer |

**Key improvement:** Mail is no longer accepted when we can't verify the recipient exists.
