# Silver Mail with Keycloak Integration

This directory contains the Keycloak-based authentication setup for Silver Mail System.

## Overview

The Keycloak integration provides enterprise-grade identity and access management for Silver Mail, offering features like:

- **Single Sign-On (SSO)**: Centralized authentication across applications
- **User Federation**: Connect to LDAP, Active Directory, or custom user stores
- **Fine-grained Authorization**: Role-based and attribute-based access control
- **Social Login**: Integration with Google, Facebook, GitHub, etc.
- **Multi-factor Authentication**: Enhanced security with 2FA/MFA
- **Admin Console**: Web-based user and client management

## Files

- **`start-silver-keycloak.sh`**: Main setup script that starts Silver Mail with Keycloak
- **`keycloak-auth.sh`**: Utility functions for Keycloak API authentication
- **`docker-compose.keycloak.yaml`**: Keycloak service definition

## Quick Start

### 1. Configure Domain

Edit `conf/silver.yaml` and set your domain:

```yaml
domains:
  - domain: mail.example.com
    dkim-selector: mail
    dkim-key-size: 2048
```

### 2. Run the Setup Script

```bash
cd scripts/service
./start-silver-keycloak.sh
```

The script will:
1. Validate domain configuration
2. Update `/etc/hosts` for local development
3. Start Docker services (SeaweedFS, Keycloak, Silver Mail)
4. Create Keycloak realm and client
5. Display configuration information

### 3. Access Keycloak Admin Console

After setup completes, access the Keycloak admin console:

- **URL**: `http://your-domain:8080/admin`
- **Username**: `admin`
- **Password**: `admin`

⚠️ **Important**: Change the admin password immediately in production!

## Architecture

```
┌─────────────────┐
│   Mail Client   │
└────────┬────────┘
         │
         ▼
┌─────────────────────────────────────────┐
│          Silver Mail System             │
│  ┌──────────┐  ┌──────────┐            │
│  │   SMTP   │  │   IMAP   │            │
│  │  Server  │  │  Server  │            │
│  └─────┬────┘  └─────┬────┘            │
│        │             │                  │
│        └─────────────┴──────────┐       │
│                                  ▼       │
│                         ┌────────────────┤
│                         │   Keycloak    ││
│                         │  Identity     ││
│                         │  Provider     ││
│                         └────────────────┤
└─────────────────────────────────────────┘
```

## Keycloak Configuration

### Default Realm

- **Name**: `silver-mail`
- **Display Name**: Silver Mail
- **Client ID**: `silver-mail-client`

### User Management

#### Creating Users via Admin Console

1. Log in to Keycloak admin console
2. Select `silver-mail` realm
3. Navigate to **Users** → **Add user**
4. Fill in user details:
   - Username (required)
   - Email (required)
   - First name (optional)
   - Last name (optional)
5. Click **Save**
6. Go to **Credentials** tab and set password

#### Creating Users via API

Use the `keycloak-auth.sh` utility:

```bash
source scripts/utils/keycloak-auth.sh

# Authenticate
keycloak_authenticate "mail.example.com" "8080" "silver-mail"

# Create user
keycloak_create_user \
  "mail.example.com" \
  "8080" \
  "silver-mail" \
  "$KEYCLOAK_ACCESS_TOKEN" \
  "john.doe" \
  "john.doe@example.com" \
  "John" \
  "Doe"
```

## Production Deployment

### Security Best Practices

1. **Change Default Credentials**
   ```bash
   # Update in docker-compose.keycloak.yaml
   KEYCLOAK_ADMIN: your-admin-username
   KEYCLOAK_ADMIN_PASSWORD: your-strong-password
   ```

2. **Use PostgreSQL Database**
   
   Uncomment the PostgreSQL service in `docker-compose.keycloak.yaml` and update Keycloak environment:
   
   ```yaml
   KC_DB: postgres
   KC_DB_URL: jdbc:postgresql://keycloak-db:5432/keycloak
   KC_DB_USERNAME: keycloak
   KC_DB_PASSWORD: secure_password_here
   ```

3. **Enable HTTPS**
   
   Configure SSL/TLS certificates:
   
   ```yaml
   KC_HTTPS_CERTIFICATE_FILE: /path/to/cert.pem
   KC_HTTPS_CERTIFICATE_KEY_FILE: /path/to/key.pem
   ```

4. **Set Hostname**
   
   ```yaml
   KC_HOSTNAME: auth.example.com
   KC_HOSTNAME_STRICT: "true"
   KC_HOSTNAME_STRICT_HTTPS: "true"
   ```

5. **Use Production Mode**
   
   Replace `start-dev` with `start` in command section

### Performance Tuning

1. **Database Connection Pool**
   
   Add to Keycloak environment:
   ```yaml
   KC_DB_POOL_INITIAL_SIZE: 20
   KC_DB_POOL_MAX_SIZE: 100
   ```

2. **Caching**
   
   Configure Infinispan for distributed caching in clustered deployments

3. **Resource Limits**
   
   Add to Keycloak service:
   ```yaml
   deploy:
     resources:
       limits:
         cpus: '2.0'
         memory: 2G
       reservations:
         cpus: '1.0'
         memory: 1G
   ```

## Integration with Silver Mail

### SMTP Authentication

Keycloak can be integrated with Silver Mail's SMTP server for authentication:

1. Configure Postfix to use Keycloak LDAP federation
2. Or use a custom authentication proxy that validates against Keycloak

### IMAP Authentication

Similar to SMTP, configure Dovecot to authenticate against Keycloak:

1. Use LDAP user federation
2. Or implement OAuth2 bearer token authentication

## Troubleshooting

### Keycloak Not Starting

Check logs:
```bash
docker logs keycloak-server
```

Common issues:
- Port 8080 already in use
- Insufficient memory
- Database connection issues

### Authentication Failures

1. Verify admin credentials
2. Check realm name is correct
3. Ensure client is properly configured
4. Review Keycloak server logs

### Health Check Failures

Test manually:
```bash
curl http://localhost:8080/health/ready
curl http://localhost:8080/health/live
```

## API Reference

### Authentication Functions

#### `keycloak_authenticate`

Authenticates with Keycloak and obtains an access token.

**Parameters:**
- `$1`: Keycloak host
- `$2`: Keycloak port
- `$3`: Realm name (default: "master")
- `$4`: Admin username (default: "admin")
- `$5`: Admin password (default: "admin")

**Exports:**
- `KEYCLOAK_ACCESS_TOKEN`

#### `keycloak_create_realm`

Creates a new Keycloak realm.

**Parameters:**
- `$1`: Keycloak host
- `$2`: Keycloak port
- `$3`: Access token
- `$4`: Realm name
- `$5`: Realm display name

**Exports:**
- `REALM_NAME`

#### `keycloak_create_client`

Creates a new client in the specified realm.

**Parameters:**
- `$1`: Keycloak host
- `$2`: Keycloak port
- `$3`: Realm name
- `$4`: Access token
- `$5`: Client ID
- `$6`: Client name

**Exports:**
- `CLIENT_UUID`
- `CLIENT_ID`

#### `keycloak_create_user`

Creates a new user in the specified realm.

**Parameters:**
- `$1`: Keycloak host
- `$2`: Keycloak port
- `$3`: Realm name
- `$4`: Access token
- `$5`: Username
- `$6`: Email
- `$7`: First name (optional)
- `$8`: Last name (optional)

**Exports:**
- `USER_ID`

## Additional Resources

- [Keycloak Documentation](https://www.keycloak.org/documentation)
- [Keycloak REST API](https://www.keycloak.org/docs-api/latest/rest-api/)
- [Server Administration Guide](https://www.keycloak.org/docs/latest/server_admin/)
- [Authorization Services](https://www.keycloak.org/docs/latest/authorization_services/)

## Support

For issues related to:
- **Keycloak**: Check official Keycloak documentation and community forums
- **Silver Mail integration**: Submit issues to the Silver Mail repository
- **General setup**: Review the main Silver Mail documentation

## License

This integration follows the same license as the Silver Mail project.
