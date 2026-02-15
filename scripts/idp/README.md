# Identity Provider (IdP) Architecture

This directory contains the pluggable Identity Provider architecture for Silver Mail System.

## Architecture Overview

The IdP subsystem follows the **Strategy Pattern** with a **Factory** to enable runtime selection of different identity providers without changing the core email system startup logic.

```
┌─────────────────────────────────────────────────────────────┐
│                    Silver Mail Startup                      │
│                   (start-silver.sh)                         │
└────────────────────────────┬────────────────────────────────┘
                             │
                             │ reads config
                             ▼
                   ┌─────────────────────┐
                   │   silver.yaml       │
                   │ identity:           │
                   │   provider: thunder │
                   └──────────┬──────────┘
                             │
                             │ provider name
                             ▼
                   ┌─────────────────────┐
                   │  IdP Factory        │
                   │  (idp-factory.sh)   │
                   └──────────┬──────────┘
                             │
                             │ creates instance
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
    │ (thunder-idp.sh)  │     │ (keycloak-idp.sh)    │
    └───────────────────┘     └──────────────────────┘
```

## Design Principles

### 1. **Clean Architecture**
- **Interface Segregation**: Each IdP implements a common interface
- **Dependency Inversion**: Core startup depends on abstractions, not concrete implementations
- **Single Responsibility**: Each provider handles only its own configuration
- **Open/Closed**: Open for extension (new IdPs), closed for modification (core logic)

### 2. **Strategy Pattern**
Each IdP is a strategy that implements the same interface:
- `initialize()` - Start the IdP service
- `wait_for_ready()` - Wait for IdP to be healthy
- `configure()` - Set up realms, clients, schemas
- `get_compose_file()` - Return docker-compose file path
- `cleanup()` - Clean up resources

### 3. **Factory Pattern**
The factory (`idp-factory.sh`) creates the appropriate provider based on configuration:
```bash
create_idp_provider "thunder"   # Returns ThunderProvider
create_idp_provider "keycloak"  # Returns KeycloakProvider
```

## Directory Structure

```
scripts/
├── idp/
│   ├── README.md                    # This file
│   ├── idp-interface.sh             # Interface contract (function signatures)
│   ├── idp-factory.sh               # Factory to create providers
│   ├── providers/
│   │   ├── thunder-idp.sh           # Thunder (WSO2) implementation
│   │   ├── keycloak-idp.sh          # Keycloak implementation
│   │   └── custom-idp.sh.example    # Template for new providers
│   └── docker/
│       ├── docker-compose.thunder.yaml
│       └── docker-compose.keycloak.yaml
├── service/
│   ├── start-silver.sh              # Unified startup script (refactored)
│   └── ...
└── utils/
    ├── thunder-auth.sh
    ├── keycloak-auth.sh
    └── ...
```

## Configuration

Add to `conf/silver.yaml`:

```yaml
identity:
  provider: thunder    # Options: thunder, keycloak, custom
  
  # Provider-specific settings
  thunder:
    host: ${MAIL_DOMAIN}
    port: 8090
    use_https: true
    
  keycloak:
    host: ${MAIL_DOMAIN}
    port: 8080
    admin_user: admin
    admin_password: admin
    realm: silver-mail
```

## Adding a New Identity Provider

### Step 1: Create Provider Implementation

Create `scripts/idp/providers/myidp-idp.sh`:

```bash
#!/bin/bash

# Source the interface
source "$(dirname "${BASH_SOURCE[0]}")/../idp-interface.sh"

# ============================================
# MyIdP Provider Implementation
# ============================================

myidp_initialize() {
    local domain="$1"
    echo "  - Starting MyIdP service..."
    
    # Start docker-compose
    local compose_file="$(dirname "${BASH_SOURCE[0]}")/../docker/docker-compose.myidp.yaml"
    (cd "$(dirname "$compose_file")" && docker compose -f "$(basename "$compose_file")" up -d)
    
    return $?
}

myidp_wait_for_ready() {
    local host="$1"
    local port="$2"
    
    echo "  - Waiting for MyIdP to be ready..."
    local max_wait=120
    local wait_count=0
    
    while [ $wait_count -lt $max_wait ]; do
        if curl -s -f "http://${host}:${port}/health" > /dev/null 2>&1; then
            echo -e "${GREEN}  ✓ MyIdP is ready${NC}"
            return 0
        fi
        sleep 2
        wait_count=$((wait_count + 2))
        echo -n "."
    done
    
    echo -e "${RED}\n✗ MyIdP did not become ready in time${NC}"
    return 1
}

myidp_configure() {
    local domain="$1"
    
    echo "  - Configuring MyIdP..."
    
    # Add your configuration logic here
    # Example: Create clients, set up authentication, etc.
    
    return 0
}

myidp_get_compose_file() {
    echo "$(dirname "${BASH_SOURCE[0]}")/../docker/docker-compose.myidp.yaml"
}

myidp_cleanup() {
    echo "  - Cleaning up MyIdP..."
    local compose_file="$(myidp_get_compose_file)"
    (cd "$(dirname "$compose_file")" && docker compose -f "$(basename "$compose_file")" down)
    return 0
}

# Export functions following the interface contract
export -f myidp_initialize
export -f myidp_wait_for_ready
export -f myidp_configure
export -f myidp_get_compose_file
export -f myidp_cleanup
```

### Step 2: Create Docker Compose File

Create `scripts/idp/docker/docker-compose.myidp.yaml`

### Step 3: Register in Factory

Update `scripts/idp/idp-factory.sh`:

```bash
case "$provider_name" in
    thunder)
        source "${PROVIDERS_DIR}/thunder-idp.sh"
        ;;
    keycloak)
        source "${PROVIDERS_DIR}/keycloak-idp.sh"
        ;;
    myidp)  # Add this
        source "${PROVIDERS_DIR}/myidp-idp.sh"
        ;;
    *)
        echo -e "${RED}✗ Unknown identity provider: ${provider_name}${NC}" >&2
        return 1
        ;;
esac
```

### Step 4: Update Configuration

Add to `conf/silver.yaml`:

```yaml
identity:
  provider: myidp
  myidp:
    host: ${MAIL_DOMAIN}
    port: 9000
```

### Step 5: Test

```bash
./scripts/service/start-silver.sh
```

## Benefits

1. **Zero Core Changes**: Adding a new IdP requires no changes to core startup logic
2. **Consistent Interface**: All IdPs implement the same contract
3. **Easy Testing**: Each provider can be tested independently
4. **Configuration-Driven**: Switch IdPs by changing config file
5. **Clean Separation**: IdP logic is isolated from email system logic

## Migration Guide

### From Old Scripts to New Architecture

**Before** (Multiple scripts):
```bash
./scripts/service/start-silver.sh          # Thunder
./scripts/service/start-silver-keycloak.sh # Keycloak
```

**After** (Single script):
```bash
# Edit conf/silver.yaml: identity.provider = "thunder" or "keycloak"
./scripts/service/start-silver.sh
```

## Testing

```bash
# Test Thunder
echo "identity:
  provider: thunder" >> conf/silver.yaml
./scripts/service/start-silver.sh

# Test Keycloak
echo "identity:
  provider: keycloak" >> conf/silver.yaml
./scripts/service/start-silver.sh
```

## Troubleshooting

- Check IdP-specific logs: `docker logs <idp-container>`
- Verify provider is loaded: Check factory output
- Validate configuration: Ensure `identity.provider` is set in silver.yaml
- Check interface compliance: Ensure all required functions are implemented

## Future Enhancements

- Support for OAuth2/OIDC providers (Auth0, Okta, etc.)
- LDAP/Active Directory integration
- Custom authentication backends
- Multi-tenancy support
