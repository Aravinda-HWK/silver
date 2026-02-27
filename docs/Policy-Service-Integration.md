# Postfix Policy Service Integration Guide

## Overview

The policy service validates email recipients against the Thunder IdP before accepting mail. This prevents mail delivery to non-existent users and provides centralized user management through Thunder.

## Architecture

```
┌──────────┐         ┌──────────┐         ┌──────────────┐         ┌────────────┐
│  SMTP    │         │ Postfix  │         │   Policy     │         │  Thunder   │
│  Client  │────────▶│  SMTP    │────────▶│   Service    │────────▶│    IdP     │
│          │         │  Server  │         │  (Port 9000) │         │ (SCIM API) │
└──────────┘         └──────────┘         └──────────────┘         └────────────┘
     │                    │                       │                      │
     │  RCPT TO:          │                       │                      │
     │  user@domain.com   │                       │                      │
     ├───────────────────▶│                       │                      │
     │                    │  Policy Request       │                      │
     │                    ├──────────────────────▶│                      │
     │                    │  (attributes)         │   SCIM Query         │
     │                    │                       ├─────────────────────▶│
     │                    │                       │   GET /scim2/Users   │
     │                    │                       │   ?filter=userName   │
     │                    │                       │                      │
     │                    │                       │   User exists?       │
     │                    │                       │◀─────────────────────│
     │                    │   Policy Response     │                      │
     │                    │◀──────────────────────│                      │
     │                    │   action=DUNNO or     │                      │
     │  250 OK or         │   action=REJECT       │                      │
     │  550 User unknown  │                       │                      │
     │◀───────────────────│                       │                      │
```

## Components

### 1. Policy Service (`services/policy-service/`)

A Python-based service that:
- Listens on port 9000 for Postfix policy delegation requests
- Parses Postfix policy protocol requests
- Queries Thunder IdP SCIM API to validate recipients
- Returns policy decisions (ACCEPT/REJECT/DEFER)

### 2. Postfix Integration

Postfix is configured to check the policy service for every `RCPT TO` command:

```conf
smtpd_recipient_restrictions =
    permit_mynetworks,
    permit_sasl_authenticated,
    reject_unauth_destination,
    check_policy_service inet:policy-service:9000
```

### 3. Thunder IdP

Thunder provides the SCIM 2.0 API for user management:
- Endpoint: `https://thunder-server:8090/scim2/Users`
- Query format: `?filter=userName eq "email@domain.com"`

## Request/Response Protocol

### Postfix → Policy Service Request

When Postfix receives a `RCPT TO` command, it sends:

```
request=smtpd_access_policy
protocol_state=RCPT
protocol_name=ESMTP
client_address=192.168.1.100
client_name=mail.sender.com
reverse_client_name=mail.sender.com
helo_name=mail.sender.com
sender=sender@sender.com
recipient=user@example.com
recipient_count=0
queue_id=8045F2AB23
instance=123.456.7
size=12345
etrn_domain=
stress=
sasl_method=plain
sasl_username=authenticated_user@example.com
sasl_sender=
ccert_subject=
ccert_issuer=
ccert_fingerprint=
encryption_protocol=TLSv1.3
encryption_cipher=TLS_AES_256_GCM_SHA384
encryption_keysize=256

```

**Key Attributes:**
- `request`: Always `smtpd_access_policy`
- `protocol_state`: `RCPT` for recipient checks
- `recipient`: The email address being validated
- `client_address`: IP of the sending server
- `sasl_username`: Authenticated user (if any)

### Policy Service → Postfix Response

#### Case 1: User Exists (Accept)
```
action=DUNNO

```
**Result:** Postfix continues processing and accepts the recipient

#### Case 2: User Not Found (Reject)
```
action=REJECT 5.1.1 <user@example.com>: Recipient address rejected: User unknown in virtual mailbox table

```
**Result:** Postfix rejects with SMTP 550 error

#### Case 3: Temporary Failure (Defer)
```
action=DEFER_IF_PERMIT Service temporarily unavailable

```
**Result:** Postfix returns SMTP 451 temporary failure

### SMTP Response Codes

| Scenario | Policy Action | SMTP Code | SMTP Message | Retry? |
|----------|---------------|-----------|--------------|--------|
| User exists | `DUNNO` | 250 | OK | N/A |
| User not found | `REJECT 5.1.1` | 550 | User unknown in virtual mailbox table | No |
| IdP timeout | `DEFER_IF_PERMIT` | 451 | Service temporarily unavailable | Yes |
| IdP unreachable | `DEFER_IF_PERMIT` | 451 | Service temporarily unavailable | Yes |
| Network error | `DEFER_IF_PERMIT` | 451 | Service temporarily unavailable | Yes |
| Auth error | `DUNNO` | 250 | OK (fail-open for safety) | N/A |

## Configuration

### Environment Variables

In `services/.env`:

```bash
# Thunder IdP authentication token for policy service (optional)
# Leave empty if Thunder API doesn't require authentication
THUNDER_IDP_TOKEN=your_optional_token_here
```

### Policy Service Configuration

The service uses these environment variables (set in `docker-compose.yaml`):

```yaml
environment:
  - IDP_URL=https://thunder-server:8090
  - IDP_TOKEN=${THUNDER_IDP_TOKEN:-}
  - POLICY_HOST=0.0.0.0
  - POLICY_PORT=9000
  - CONFIG_FILE=/etc/postfix/silver.yaml
```

## Deployment

### 1. Build and Start Services

```bash
cd services
docker-compose up -d policy-service
docker-compose up -d smtp-server
```

### 2. Verify Policy Service

```bash
# Check logs
docker logs policy-service

# Expected output:
# Policy service running on ('0.0.0.0', 9000)
```

### 3. Test Policy Service

Using telnet or netcat:

```bash
# Connect to policy service
telnet localhost 9000

# Send test request
request=smtpd_access_policy
protocol_state=RCPT
recipient=test@yourdomain.com

# Press Enter twice to send
```

Expected response:
```
action=REJECT 5.1.1 <test@yourdomain.com>: Recipient address rejected: User unknown in virtual mailbox table
```

### 4. Test End-to-End

Send a test email:

```bash
# Test with non-existent user (should fail)
echo "Test" | mail -s "Test" nonexistent@yourdomain.com

# Check mail logs
docker exec smtp-server-container tail -f /var/log/mail.log

# Expected: "Recipient address rejected: User unknown"
```

## Thunder IdP Setup

### Create Test Users

```bash
# Use Thunder's SCIM API or admin console
curl -X POST https://thunder-server:8090/scim2/Users \
  -H "Content-Type: application/json" \
  -d '{
    "userName": "testuser@yourdomain.com",
    "password": "TestPass123!",
    "emails": [
      {
        "value": "testuser@yourdomain.com",
        "primary": true
      }
    ]
  }'
```

Or use Thunder's admin interface at `https://your-server:8090/develop/`

### Verify User Exists

```bash
# Query SCIM API
curl "https://thunder-server:8090/scim2/Users?filter=userName%20eq%20%22testuser@yourdomain.com%22"

# Expected response:
# {
#   "totalResults": 1,
#   "Resources": [...]
# }
```

## Monitoring and Troubleshooting

### View Policy Service Logs

```bash
docker logs -f policy-service
```

**Key log messages:**
```
INFO - Policy service running on ('0.0.0.0', 9000)
INFO - Processing request: protocol_state=RCPT, recipient=user@example.com, client=192.168.1.100
INFO - User found: user@example.com
INFO - ACCEPT: user@example.com
```

Or for rejections:
```
INFO - User not found: baduser@example.com
INFO - REJECT: baduser@example.com
```

### View Postfix Logs

```bash
docker exec smtp-server-container tail -f /var/log/mail.log
```

**Look for:**
```
postfix/smtpd[1234]: NOQUEUE: reject: RCPT from unknown[1.2.3.4]: 550 5.1.1 <baduser@example.com>: Recipient address rejected: User unknown in virtual mailbox table
```

### Common Issues

#### 1. Policy Service Not Responding

**Symptom:** Mail delivery fails with timeout

**Solution:**
```bash
# Check if service is running
docker ps | grep policy-service

# Check network connectivity
docker exec smtp-server-container nc -zv policy-service 9000

# Restart service
docker-compose restart policy-service
```

#### 2. Thunder IdP Unreachable

**Symptom:** All mail is deferred (451 errors)

**Solution:**
```bash
# Check Thunder is running
docker ps | grep thunder

# Check network connectivity
docker exec policy-service nc -zv thunder-server 8090

# Verify Thunder SCIM endpoint
curl -k https://localhost:8090/scim2/Users
```

#### 3. Authentication Errors

**Symptom:** Policy service logs show "IdP authentication failed"

**Solution:**
- Verify `THUNDER_IDP_TOKEN` is set correctly in `.env`
- Check Thunder authentication requirements
- Consider using Thunder's OAuth2 token endpoint

#### 4. All Recipients Rejected

**Symptom:** All mail is rejected, even valid users

**Solution:**
- Verify users exist in Thunder IdP
- Check SCIM filter format in policy service
- Ensure email addresses match exactly (case-sensitive)
- Check Thunder logs for API errors

## Performance Considerations

### Caching (Future Enhancement)

To reduce IdP queries, consider adding a cache:

```python
# In policy service
from functools import lru_cache
import time

@lru_cache(maxsize=1000)
def check_user_cached(email: str, timestamp: int):
    # Cache for 5 minutes (timestamp rounds to 5-min intervals)
    return check_user_exists(email)

# Use: check_user_cached(email, int(time.time() / 300))
```

### Rate Limiting

Thunder IdP may have rate limits. Monitor and adjust:
- Policy service timeout (currently 5 seconds)
- Concurrent connections
- Request batching

### High Availability

For production:
- Run multiple policy service instances
- Use load balancing
- Implement health checks
- Add metrics export (Prometheus)

## Security Best practices

1. **Network Isolation**
   - Policy service only accessible from mail-network
   - No public exposure

2. **Authentication**
   - Use `THUNDER_IDP_TOKEN` for authenticated requests
   - Rotate tokens regularly

3. **TLS/SSL**
   - Enable SSL verification in production (currently disabled for dev)
   - Use valid certificates for Thunder IdP

4. **Logging**
   - Log all decisions for audit
   - Don't log sensitive data (passwords, tokens)
   - Use structured logging for analysis

5. **Fail-Safe**
   - On permanent errors, policy service returns `DUNNO` (fail-open)
   - On temporary errors, returns `DEFER_IF_PERMIT` (retry)
   - Prevents mail outage if IdP is down

## Testing Checklist

- [ ] Policy service starts successfully
- [ ] Policy service responds to telnet test
- [ ] Postfix can connect to policy service
- [ ] Valid user email is accepted (250 OK)
- [ ] Invalid user email is rejected (550 User unknown)
- [ ] IdP down returns temporary failure (451)
- [ ] Authenticated users can send to any recipient
- [ ] Unauthenticated users can only send to valid recipients
- [ ] Logs show correct decisions
- [ ] No performance degradation under load

## References

- [Postfix Policy Delegation Protocol](http://www.postfix.org/SMTPD_POLICY_README.html)
- [Thunder SCIM 2.0 API](https://github.com/asgardeo/thunder)
- [RFC 7644 - SCIM Protocol](https://datatracker.ietf.org/doc/html/rfc7644)
- [SMTP Response Codes](https://www.rfc-editor.org/rfc/rfc5321.html#section-4.2)
