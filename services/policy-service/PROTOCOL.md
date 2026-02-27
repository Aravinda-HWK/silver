# Postfix Policy Protocol - Quick Reference

## Request Format

When Postfix processes an SMTP `RCPT TO` command, it sends a policy request in the following format:

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

**Important:** The request ends with a blank line (`\n\n`).

## Key Attributes

| Attribute | Description | Example |
|-----------|-------------|---------|
| `request` | Always `smtpd_access_policy` | `smtpd_access_policy` |
| `protocol_state` | SMTP command being processed | `RCPT`, `MAIL`, `DATA`, etc. |
| `protocol_name` | SMTP protocol name | `ESMTP`, `SMTP` |
| `client_address` | IP address of connecting client | `192.168.1.100` |
| `client_name` | Hostname of connecting client | `mail.sender.com` |
| `helo_name` | HELO/EHLO name from client | `mail.sender.com` |
| `sender` | Envelope sender (MAIL FROM) | `sender@sender.com` |
| `recipient` | Envelope recipient (RCPT TO) | `user@example.com` |
| `queue_id` | Postfix queue ID | `8045F2AB23` |
| `sasl_method` | SASL authentication method | `plain`, `login`, `cram-md5` |
| `sasl_username` | Authenticated username | `user@example.com` |
| `encryption_protocol` | TLS protocol version | `TLSv1.3`, `TLSv1.2` |
| `encryption_cipher` | TLS cipher suite | `TLS_AES_256_GCM_SHA384` |
| `size` | Message size (if known) | `12345` |

## Response Format

The policy service must respond with an action followed by a blank line.

### Accept (User exists)
```
action=DUNNO

```
**Result:** Postfix continues processing. Other checks still apply.

### Reject (User not found)
```
action=REJECT 5.1.1 <user@example.com>: Recipient address rejected: User unknown in virtual mailbox table

```
**Result:** Postfix immediately rejects with 550 error.

### Temporary Failure (Service error)
```
action=DEFER_IF_PERMIT Service temporarily unavailable

```
**Result:** Postfix returns 451 temporary failure. Sender should retry.

### Other Actions

| Action | Meaning |
|--------|---------|
| `action=OK` | Accept and skip remaining restrictions |
| `action=REJECT [text]` | Reject with optional custom message |
| `action=DEFER [text]` | Temporary failure (always defer) |
| `action=DEFER_IF_REJECT [text]` | Defer if result would be reject |
| `action=DEFER_IF_PERMIT [text]` | Defer if result would be permit |
| `action=DUNNO` | Continue to next restriction |
| `action=HOLD [reason]` | Place in hold queue |
| `action=DISCARD [reason]` | Silently discard |
| `action=REDIRECT user` | Redirect to different recipient |
| `action=FILTER transport:nexthop` | Route through content filter |

**Note:** For recipient validation, use:
- `DUNNO` to accept
- `REJECT 5.1.1` to reject
- `DEFER_IF_PERMIT` for temporary errors

## SMTP Response Codes

| Policy Action | SMTP Code | Category | Retry? |
|---------------|-----------|----------|--------|
| `DUNNO` | 250 | Success | N/A |
| `OK` | 250 | Success | N/A |
| `REJECT 4.x.x` | 450-451 | Temporary failure | Yes |
| `REJECT 5.x.x` | 550-551 | Permanent failure | No |
| `DEFER` | 451 | Temporary failure | Yes |
| `DEFER_IF_PERMIT` | 451 | Temporary failure | Yes |

### Common Enhanced Status Codes

| Code | Meaning | Use Case |
|------|---------|----------|
| `4.3.0` | Temporary system problem | Server error, try later |
| `4.7.1` | Greylisted | Anti-spam greylisting |
| `5.1.1` | Bad destination mailbox | User not found |
| `5.7.1` | Delivery not authorized | Policy rejection |
| `5.7.7` | Message integrity failure | DKIM/SPF failure |

## Protocol State Values

| State | When Checked | Typical Use |
|-------|--------------|-------------|
| `CONNECT` | Client connects | IP blacklisting, rate limiting |
| `EHLO` | EHLO/HELO command | Hostname validation |
| `MAIL` | MAIL FROM command | Sender validation |
| `RCPT` | RCPT TO command | **Recipient validation** ← Used here |
| `DATA` | DATA command | Size limits, content checks |
| `END-OF-MESSAGE` | After message body | Content filtering |
| `VRFY` | VRFY command | Address verification |
| `ETRN` | ETRN command | Queue flushing |

## Testing with Netcat

```bash
# Connect to policy service
nc localhost 9000

# Paste this request (press Enter twice after last line):
request=smtpd_access_policy
protocol_state=RCPT
recipient=test@example.com

# Expected response:
action=REJECT 5.1.1 <test@example.com>: Recipient address rejected: User unknown in virtual mailbox table
```

## Testing with Python

```python
import socket

def test_policy(recipient):
    s = socket.socket()
    s.connect(('localhost', 9000))
    
    request = f"""request=smtpd_access_policy
protocol_state=RCPT
recipient={recipient}

"""
    s.send(request.encode())
    response = s.recv(1024).decode()
    s.close()
    
    return response

print(test_policy('user@example.com'))
```

## Implementation Tips

1. **Always terminate request with `\n\n`** - Postfix waits for blank line
2. **Respond quickly** - Postfix has timeout (default 100s but should be faster)
3. **Use `DEFER_IF_PERMIT` for errors** - Prevents mail loss
4. **Log all decisions** - Important for debugging
5. **Handle connection reuse** - Postfix may send multiple requests per connection
6. **Validate input** - Check that required attributes exist
7. **Return immediately** - Don't block for async operations

## Error Handling Best Practices

| Scenario | Recommended Action | Reason |
|----------|-------------------|--------|
| IdP timeout | `DEFER_IF_PERMIT` | Temporary problem |
| IdP unreachable | `DEFER_IF_PERMIT` | Network issue |
| Invalid request | `DUNNO` | Let other checks handle it |
| Missing recipient | `DUNNO` | Let other checks handle it |
| Internal error | `DEFER_IF_PERMIT` | Safe fallback |
| User not found | `REJECT 5.1.1` | Permanent failure |
| User exists | `DUNNO` | Continue processing |

## References

- [Postfix SMTPD Policy Documentation](http://www.postfix.org/SMTPD_POLICY_README.html)
- [Postfix Access Policy Delegation](http://www.postfix.org/postconf.5.html#smtpd_recipient_restrictions)
- [RFC 5321 - SMTP](https://www.rfc-editor.org/rfc/rfc5321.html)
- [RFC 3463 - Enhanced Status Codes](https://www.rfc-editor.org/rfc/rfc3463.html)
