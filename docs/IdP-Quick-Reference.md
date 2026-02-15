# Identity Provider Quick Reference Card

## 🚀 Quick Commands

```bash
# Start with configured IdP
./scripts/service/start-silver-unified.sh

# Stop all services
./scripts/service/stop-silver.sh

# Clean up everything
./scripts/service/cleanup-docker.sh

# Check running containers
docker ps | grep -E 'thunder|keycloak'

# View logs
docker compose logs -f
```

## 📝 Configuration Template

```yaml
# conf/silver.yaml

# Thunder Configuration
identity:
  provider: thunder
  thunder:
    host: ${MAIL_DOMAIN}
    port: 8090
    use_https: true

# OR Keycloak Configuration  
identity:
  provider: keycloak
  keycloak:
    host: ${MAIL_DOMAIN}
    port: 8080
    admin_user: admin
    admin_password: admin
    realm: silver-mail
    client_id: silver-mail-client
```

## 🔧 Provider Interface

All providers MUST implement these 5 functions:

```bash
# 1. Initialize - Start the IdP service
<provider>_initialize() {
    local domain="$1"
    # Start docker compose
    # Return 0 on success, 1 on failure
}

# 2. Wait for Ready - Health check
<provider>_wait_for_ready() {
    local host="$1"
    local port="$2"
    # Poll health endpoint
    # Return 0 when ready, 1 on timeout
}

# 3. Configure - Setup realms, clients, schemas
<provider>_configure() {
    local domain="$1"
    # Authenticate, create realm, create client
    # Initialize database
    # Return 0 on success, 1 on failure
}

# 4. Get Compose File - Return docker-compose path
<provider>_get_compose_file() {
    echo "/path/to/docker-compose.<provider>.yaml"
}

# 5. Cleanup - Stop and cleanup
<provider>_cleanup() {
    # Stop docker compose
    # Return 0 on success, 1 on failure
}
```

## 🏭 Using the Factory

```bash
# Load factory
source scripts/idp/idp-factory.sh

# Get provider from config
provider=$(get_provider_from_config "conf/silver.yaml")

# Create provider instance
create_idp_provider "$provider"

# Use exported functions
$IDP_INITIALIZE "example.com"
$IDP_WAIT_FOR_READY "example.com" "8080"
$IDP_CONFIGURE "example.com"
$IDP_CLEANUP
```

## 📁 File Locations

```
scripts/idp/
├── idp-interface.sh                  # Interface contract
├── idp-factory.sh                    # Factory implementation
├── providers/
│   ├── thunder-idp.sh                # Thunder provider
│   ├── keycloak-idp.sh               # Keycloak provider
│   └── custom-idp.sh.example         # Template
└── docker/
    ├── docker-compose.thunder.yaml   # Thunder compose
    └── docker-compose.keycloak.yaml  # Keycloak compose
```

## 🆕 Adding New Provider (5 Steps)

```bash
# 1. Copy template
cp scripts/idp/providers/custom-idp.sh.example \
   scripts/idp/providers/myidp-idp.sh

# 2. Implement functions (replace 'custom' with 'myidp')
vim scripts/idp/providers/myidp-idp.sh

# 3. Create docker-compose
vim scripts/idp/docker/docker-compose.myidp.yaml

# 4. Register in factory
# Edit: scripts/idp/idp-factory.sh
# Add case: myidp) source providers/myidp-idp.sh ;;

# 5. Update config
vim conf/silver.yaml
# Add: identity.provider = "myidp"
```

## 🔍 Debugging

```bash
# Check if provider is loaded
declare -f thunder_initialize  # Should show function

# Validate provider implementation
source scripts/idp/idp-interface.sh
validate_provider_implementation "thunder"

# Check docker-compose file
cat scripts/idp/docker/docker-compose.thunder.yaml

# Test provider functions individually
source scripts/idp/providers/thunder-idp.sh
thunder_initialize "example.com"
thunder_wait_for_ready "example.com" "8090"

# Check logs
docker logs thunder-server
docker logs keycloak-server
```

## ⚠️ Common Issues

| Issue | Cause | Solution |
|-------|-------|----------|
| "Unknown provider" | Invalid provider name | Check `identity.provider` in config |
| "Missing functions" | Incomplete implementation | Implement all 5 required functions |
| "Compose file not found" | Wrong path | Check `<provider>_get_compose_file()` |
| "Health check timeout" | IdP not starting | Check `docker logs <container>` |
| "Authentication failed" | Wrong credentials | Check provider-specific config |

## 📊 Provider Comparison

| Feature | Thunder | Keycloak |
|---------|---------|----------|
| **Port** | 8090 | 8080 |
| **Protocol** | HTTPS | HTTP (dev) |
| **Health Endpoint** | `/scim2/Users` | `/health/ready` |
| **Admin UI** | Custom | Web-based |
| **Database** | SQLite | H2/PostgreSQL |
| **Realm/Org** | Organization Unit | Realm |
| **Client** | API schema | OIDC Client |

## 🧪 Testing Checklist

```bash
# 1. Verify configuration
cat conf/silver.yaml | grep -A 5 "identity:"

# 2. Load provider
source scripts/idp/idp-factory.sh
create_idp_provider "thunder"

# 3. Check exports
echo $IDP_PROVIDER
echo $IDP_INITIALIZE

# 4. Validate implementation
validate_provider_implementation "$IDP_PROVIDER"

# 5. Test startup
./scripts/service/start-silver-unified.sh

# 6. Verify containers
docker ps | grep $IDP_PROVIDER

# 7. Check health
curl -k https://localhost:8090/scim2/Users  # Thunder
curl http://localhost:8080/health/ready     # Keycloak

# 8. Test cleanup
./scripts/service/cleanup-docker.sh
```

## 📚 Documentation Links

- **Architecture:** `docs/IdP-Architecture.md`
- **Migration Guide:** `docs/IdP-Migration-Guide.md`
- **Implementation Summary:** `docs/IdP-Implementation-Summary.md`
- **Provider Guide:** `scripts/idp/README.md`

## 💡 Tips

1. **Always validate** provider implementation before using
2. **Use the template** when creating new providers
3. **Test in isolation** before integrating
4. **Check health endpoints** after startup
5. **Read logs** when debugging issues

## 🎯 Key Principles

- **Interface Segregation:** All providers implement same interface
- **Dependency Inversion:** Core depends on abstraction, not concrete
- **Single Responsibility:** Each provider handles only its IdP
- **Open/Closed:** Open for extension, closed for modification
- **DRY:** Don't Repeat Yourself - zero code duplication

---

**Keep this card handy when working with Identity Providers!**
