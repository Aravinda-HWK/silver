# Postfix Policy Service

This service implements the Postfix policy delegation protocol to validate recipients against the Thunder IdP before accepting mail.

## Overview

The policy service:
- Listens on port 9000 for policy requests from Postfix
- Validates recipients by querying the Thunder IdP SCIM API
- Returns policy decisions (ACCEPT/REJECT/DEFER) to Postfix

## Request Format

Postfix sends requests in the following format:

```
request=smtpd_access_policy
protocol_state=RCPT
protocol_name=ESMTP
client_address=1.2.3.4
client_name=mail.example.com
reverse_client_name=mail.example.com
helo_name=mail.example.com
sender=sender@example.com
recipient=user@example.com
recipient_count=0
queue_id=8045F2AB23
instance=123.456.7
size=12345
etrn_domain=
stress=
sasl_method=
sasl_username=
sasl_sender=
ccert_subject=
ccert_issuer=
ccert_fingerprint=
encryption_protocol=TLSv1.2
encryption_cipher=ECDHE-RSA-AES256-GCM-SHA384
encryption_keysize=256

```

(Request ends with an empty line)

## Response Format

The service responds with one of:

### User Exists (Accept)
```
action=DUNNO

```

### User Not Found (Reject)
```
action=REJECT 5.1.1 <user@example.com>: Recipient address rejected: User unknown in virtual mailbox table

```

### Temporary Failure
```
action=DEFER_IF_PERMIT Service temporarily unavailable

```

## Response Codes

| Case | SMTP Response Code | Action |
|------|-------------------|--------|
| User exists | 250 OK | Accept mail |
| User not found | 550 5.1.1 | Reject with "User unknown" |
| IdP unreachable | 451 4.3.0 | Temporary failure (retry later) |
| Service error | 451 4.3.0 | Temporary failure |

## Configuration

Environment variables:

- `IDP_URL`: Base URL of Thunder IdP (default: `https://thunder-server:8090`)
- `IDP_TOKEN`: Optional authentication token for IdP API calls
- `POLICY_HOST`: Host to bind to (default: `0.0.0.0`)
- `POLICY_PORT`: Port to listen on (default: `9000`)
- `CONFIG_FILE`: Path to silver.yaml config file (default: `/etc/postfix/silver.yaml`)

## Integration with Postfix

In Postfix's `main.cf`, add:

```
smtpd_recipient_restrictions =
    permit_mynetworks,
    reject_unauth_destination,
    check_policy_service inet:policy-service:9000
```

This tells Postfix to:
1. Allow mail from trusted networks
2. Reject unauthorized destinations (relay blocking)
3. Check the policy service for recipient validation

## How It Works

1. **Postfix receives RCPT TO command** during SMTP conversation
2. **Postfix sends policy request** to this service on port 9000
3. **Service extracts recipient** email from the request
4. **Service queries Thunder IdP** using SCIM API:
   ```
   GET /scim2/Users?filter=userName eq "user@example.com"
   ```
5. **Service checks response**:
   - If `totalResults > 0`: User exists → Return `DUNNO` (accept)
   - If `totalResults == 0`: User not found → Return `REJECT`
   - If IdP unreachable: Return `DEFER_IF_PERMIT` (temporary failure)
6. **Postfix applies decision** and continues SMTP conversation

## Thunder IdP Integration

The service uses Thunder's SCIM 2.0 API:

- **Endpoint**: `/scim2/Users`
- **Method**: GET
- **Query**: `filter=userName eq "email@domain.com"`
- **Response**: JSON with `totalResults` field

Example successful response:
```json
{
  "totalResults": 1,
  "Resources": [
    {
      "userName": "user@example.com",
      "id": "123456",
      "emails": [...]
    }
  ]
}
```

## Testing

You can test the service using telnet or nc:

```bash
# Connect to the service
telnet localhost 9000

# Send a test request
request=smtpd_access_policy
protocol_state=RCPT
recipient=test@example.com

# (Press Enter twice to send)
```

Expected response:
```
action=REJECT 5.1.1 <test@example.com>: Recipient address rejected: User unknown in virtual mailbox table
```

Or for an existing user:
```
action=DUNNO
```

## Logging

The service logs all requests and decisions:

```
2024-01-15 10:30:45 - INFO - Policy service running on ('0.0.0.0', 9000)
2024-01-15 10:31:02 - INFO - Processing request: protocol_state=RCPT, recipient=user@example.com, client=192.168.1.100
2024-01-15 10:31:02 - INFO - User found: user@example.com
2024-01-15 10:31:02 - INFO - ACCEPT: user@example.com
```

## Security Considerations

1. **Internal Network Only**: The policy service should only be accessible from the mail network
2. **IdP Authentication**: Use `IDP_TOKEN` for authenticated requests to Thunder
3. **SSL/TLS**: In production, enable SSL certificate verification for IdP connections
4. **Rate Limiting**: Consider implementing rate limiting to prevent abuse
5. **Logging**: Ensure logs don't contain sensitive information

## Future Enhancements

- Add caching layer to reduce IdP queries
- Support for multiple IdP backends
- Metrics and monitoring integration
- Configuration hot-reloading
- Support for group-based policies
