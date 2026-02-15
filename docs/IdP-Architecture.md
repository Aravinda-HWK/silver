# Pluggable Identity Provider Architecture

## Overview

Silver Mail now supports multiple Identity Providers through a clean, pluggable architecture using the **Strategy Pattern** with a **Factory**. This allows you to:

- Switch between IdPs by changing configuration
- Add new IdPs without modifying core logic
- Maintain consistent behavior across different IdPs

## Quick Start

### 1. Configure Your Identity Provider

Edit `conf/silver.yaml`:

```yaml
# Option 1: Use Thunder (WSO2)
identity:
  provider: thunder
  thunder:
    host: ${MAIL_DOMAIN}
    port: 8090
    use_https: true

# Option 2: Use Keycloak
# identity:
#   provider: keycloak
#   keycloak:
#     host: ${MAIL_DOMAIN}
#     port: 8080
#     admin_user: admin
#     admin_password: admin
#     realm: silver-mail
```

### 2. Start Silver Mail

```bash
# Using the unified script (recommended)
./scripts/service/start-silver-unified.sh

# Or legacy scripts (deprecated)
./scripts/service/start-silver.sh          # Thunder only
./scripts/service/start-silver-keycloak.sh # Keycloak only
```

### 3. Switch Identity Providers

Simply edit `conf/silver.yaml` and change the `provider` value, then restart:

```bash
./scripts/service/stop-silver.sh
./scripts/service/start-silver-unified.sh
```

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Application Layer                        │
│              (start-silver-unified.sh)                      │
└────────────────────────────┬────────────────────────────────┘
                             │
                             │ Uses Factory
                             ▼
                   ┌─────────────────────┐
                   │  IdP Factory        │
                   │  (idp-factory.sh)   │
                   └──────────┬──────────┘
                             │
                             │ Creates Strategy
                             ▼
              ┌──────────────────────────────────┐
              │   IdentityProvider Interface     │
              │   (idp-interface.sh)             │
              ├──────────────────────────────────┤
              │ + initialize()                   │
              │ + wait_for_ready()               │
              │ + configure()                    │
              │ + get_compose_file()             │
              │ + cleanup()                      │
              └──────────────┬───────────────────┘
                             │
                ┌────────────┴────────────┐
                │                         │
                ▼                         ▼
    ┌───────────────────┐     ┌──────────────────────┐
    │ ThunderProvider   │     │ KeycloakProvider     │
    │ (Concrete)        │     │ (Concrete)           │
    └───────────────────┘     └──────────────────────┘
```

### Design Patterns

1. **Strategy Pattern**: Each IdP is a strategy implementing the same interface
2. **Factory Pattern**: Factory creates the appropriate provider based on config
3. **Dependency Inversion**: Core logic depends on abstraction (interface), not concrete implementations

## File Structure

```
silver/
├── conf/
│   └── silver.yaml                      # Configuration (includes IdP settings)
├── scripts/
│   ├── idp/                             # IdP Architecture (NEW)
│   │   ├── README.md                    # This file
│   │   ├── idp-interface.sh             # Interface contract
│   │   ├── idp-factory.sh               # Factory implementation
│   │   ├── providers/
│   │   │   ├── thunder-idp.sh           # Thunder implementation
│   │   │   ├── keycloak-idp.sh          # Keycloak implementation
│   │   │   └── custom-idp.sh.example    # Template for new IdPs
│   │   └── docker/
│   │       ├── docker-compose.thunder.yaml
│   │       └── docker-compose.keycloak.yaml
│   ├── service/
│   │   ├── start-silver-unified.sh      # NEW: Unified startup
│   │   ├── start-silver.sh              # LEGACY: Thunder only
│   │   ├── start-silver-keycloak.sh     # LEGACY: Keycloak only
│   │   ├── stop-silver.sh
│   │   └── cleanup-docker.sh            # UPDATED: Cleans all IdPs
│   └── utils/
│       ├── thunder-auth.sh              # Thunder utilities
│       ├── keycloak-auth.sh             # Keycloak utilities
│       └── shared-db-sync.sh            # Shared database utilities
└── services/
    └── docker-compose.yaml              # Core mail services
```

## Benefits

### For Users

1. **Easy Switching**: Change IdPs by editing one line in config
2. **Consistent Experience**: Same commands work for all IdPs
3. **Future-Proof**: New IdPs can be added without breaking changes

### For Developers

1. **Clean Architecture**: Separation of concerns, single responsibility
2. **Open/Closed Principle**: Open for extension, closed for modification
3. **Testability**: Each provider can be tested independently
4. **Maintainability**: Changes to one IdP don't affect others

## Adding a New Identity Provider

See the detailed guide in [scripts/idp/README.md](scripts/idp/README.md).

### Quick Steps:

1. Create `scripts/idp/providers/myidp-idp.sh` implementing the interface
2. Create `scripts/idp/docker/docker-compose.myidp.yaml`
3. Register in `scripts/idp/idp-factory.sh`
4. Add configuration to `conf/silver.yaml`
5. Test with `./scripts/service/start-silver-unified.sh`

## Comparison: Old vs New

### Old Approach (Multiple Scripts)

```bash
# Want Thunder? Run this script
./scripts/service/start-silver.sh

# Want Keycloak? Run this script
./scripts/service/start-silver-keycloak.sh

# Want to add new IdP? Duplicate 200 lines of code!
```

**Problems:**
- Code duplication
- Hard to maintain
- Easy to make mistakes
- No consistency

### New Approach (Pluggable)

```bash
# Edit config file
vim conf/silver.yaml  # Set: identity.provider = "thunder" or "keycloak"

# Run one script
./scripts/service/start-silver-unified.sh

# Want to add new IdP? Implement 5 functions!
```

**Advantages:**
- DRY (Don't Repeat Yourself)
- Easy to maintain
- Consistent behavior
- Extensible

## Migration Guide

### From Legacy Scripts to Unified Script

**Step 1**: Update your configuration

```yaml
# Add this to conf/silver.yaml
identity:
  provider: thunder  # or keycloak
```

**Step 2**: Switch to unified script

```bash
# Old way
./scripts/service/start-silver.sh

# New way
./scripts/service/start-silver-unified.sh
```

**Step 3** (Optional): Keep using legacy scripts

Legacy scripts still work but are deprecated. They will be removed in a future version.

## Troubleshooting

### Problem: "Unknown identity provider"

**Solution**: Check `conf/silver.yaml` has valid `identity.provider` setting.

```yaml
identity:
  provider: thunder  # Must be: thunder, keycloak, or custom
```

### Problem: "Provider does not implement required interface"

**Solution**: Your custom provider is missing required functions. Check:
- `<provider>_initialize`
- `<provider>_wait_for_ready`
- `<provider>_configure`
- `<provider>_get_compose_file`
- `<provider>_cleanup`

### Problem: "Failed to initialize Identity Provider"

**Solution**: Check Docker logs for your IdP:

```bash
# Thunder
docker logs thunder-server

# Keycloak
docker logs keycloak-server
```

### Problem: IdP not starting

**Solution**: Ensure docker-compose file exists and is valid:

```bash
# Check Thunder
ls -la scripts/idp/docker/docker-compose.thunder.yaml

# Check Keycloak
ls -la scripts/idp/docker/docker-compose.keycloak.yaml
```

## Testing

### Test Thunder

```bash
# Set provider in config
echo "identity:
  provider: thunder" >> conf/silver.yaml

# Start
./scripts/service/start-silver-unified.sh

# Verify
docker ps | grep thunder
curl -k https://localhost:8090/scim2/Users
```

### Test Keycloak

```bash
# Set provider in config
echo "identity:
  provider: keycloak" >> conf/silver.yaml

# Start
./scripts/service/start-silver-unified.sh

# Verify
docker ps | grep keycloak
curl http://localhost:8080/health
```

## API Reference

### Interface Contract

All providers must implement:

```bash
# Initialize the IdP service
<provider>_initialize <domain>

# Wait for IdP to be ready
<provider>_wait_for_ready <host> <port>

# Configure IdP (create realms, clients, schemas)
<provider>_configure <domain>

# Get docker-compose file path
<provider>_get_compose_file

# Cleanup and stop IdP
<provider>_cleanup
```

### Factory Methods

```bash
# Load IdP factory
source scripts/idp/idp-factory.sh

# Get provider name from config
provider=$(get_provider_from_config "conf/silver.yaml")

# Create provider instance
create_idp_provider "$provider"

# Use provider functions
$IDP_INITIALIZE "example.com"
$IDP_WAIT_FOR_READY "example.com" "8080"
$IDP_CONFIGURE "example.com"
$IDP_CLEANUP
```

## Best Practices

1. **Always use the unified script** for new deployments
2. **Test provider changes** in development before production
3. **Keep IdP configurations** in `conf/silver.yaml`
4. **Document custom providers** following the template
5. **Version control** your IdP configurations

## Future Enhancements

- [ ] OAuth2/OIDC provider support (Auth0, Okta)
- [ ] LDAP/Active Directory integration
- [ ] Multi-IdP support (federated identities)
- [ ] Provider health checks and auto-recovery
- [ ] Provider-specific metrics and monitoring
- [ ] GUI for provider selection and configuration

## Contributing

To contribute a new IdP provider:

1. Follow the template in `scripts/idp/providers/custom-idp.sh.example`
2. Implement all required interface functions
3. Test thoroughly
4. Submit PR with documentation

## Support

For issues or questions:

1. Check logs: `docker compose logs`
2. Review documentation: `scripts/idp/README.md`
3. File an issue on GitHub

## License

Same as Silver Mail System.
