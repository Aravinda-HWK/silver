# Migration Guide: Legacy IdP Scripts → Pluggable Architecture

## Overview

This guide helps you migrate from the legacy Identity Provider scripts to the new pluggable architecture.

## What Changed?

### Before (Legacy)

```
scripts/service/
├── start-silver.sh          ← Thunder only, 200 lines
└── start-silver-keycloak.sh ← Keycloak only, 200 lines
```

**Problems:**
- Code duplication (80% identical)
- Hard to add new IdPs
- Inconsistent behavior
- Difficult to maintain

### After (Pluggable)

```
scripts/
├── idp/                          ← NEW: Pluggable IdP system
│   ├── idp-interface.sh          ← Interface contract
│   ├── idp-factory.sh            ← Factory pattern
│   ├── providers/
│   │   ├── thunder-idp.sh        ← Thunder implementation
│   │   ├── keycloak-idp.sh       ← Keycloak implementation
│   │   └── custom-idp.sh.example ← Template
│   └── docker/
│       ├── docker-compose.thunder.yaml
│       └── docker-compose.keycloak.yaml
└── service/
    ├── start-silver-unified.sh   ← NEW: One script for all IdPs
    ├── start-silver.sh           ← LEGACY: Still works
    └── start-silver-keycloak.sh  ← LEGACY: Still works
```

**Benefits:**
- Zero code duplication
- Easy to add new IdPs (just implement 5 functions)
- Consistent behavior across all IdPs
- Clean architecture (Strategy + Factory patterns)

## Migration Steps

### Step 1: Backup Current Setup

```bash
# Backup your configuration
cp conf/silver.yaml conf/silver.yaml.backup

# Backup your scripts (optional)
cp -r scripts scripts.backup
```

### Step 2: Update Configuration File

Add the Identity Provider configuration to `conf/silver.yaml`:

```yaml
# ===============================================================
#          Identity Provider Configuration
# ===============================================================

# For Thunder (WSO2)
identity:
  provider: thunder
  thunder:
    host: ${MAIL_DOMAIN}
    port: 8090
    use_https: true

# OR for Keycloak
# identity:
#   provider: keycloak
#   keycloak:
#     host: ${MAIL_DOMAIN}
#     port: 8080
#     admin_user: admin
#     admin_password: admin
#     realm: silver-mail
#     client_id: silver-mail-client
```

### Step 3: Test the New Unified Script

```bash
# Stop current services
./scripts/service/stop-silver.sh

# Start using the new unified script
./scripts/service/start-silver-unified.sh
```

### Step 4: Verify Everything Works

```bash
# Check all containers are running
docker ps

# Check IdP-specific container
docker ps | grep thunder    # for Thunder
docker ps | grep keycloak   # for Keycloak

# Check logs
docker compose logs -f
```

### Step 5: Update Your Workflows

Replace old script references with new ones:

**Old:**
```bash
./scripts/service/start-silver.sh          # Thunder
./scripts/service/start-silver-keycloak.sh # Keycloak
```

**New:**
```bash
# Edit conf/silver.yaml to set identity.provider
./scripts/service/start-silver-unified.sh  # Works for all IdPs
```

## Switching Between IdPs

### From Thunder to Keycloak

1. Stop current services:
```bash
./scripts/service/stop-silver.sh
```

2. Edit `conf/silver.yaml`:
```yaml
identity:
  provider: keycloak  # Changed from 'thunder'
  keycloak:
    host: ${MAIL_DOMAIN}
    port: 8080
    admin_user: admin
    admin_password: admin
    realm: silver-mail
```

3. Start services:
```bash
./scripts/service/start-silver-unified.sh
```

### From Keycloak to Thunder

1. Stop current services:
```bash
./scripts/service/stop-silver.sh
```

2. Edit `conf/silver.yaml`:
```yaml
identity:
  provider: thunder  # Changed from 'keycloak'
  thunder:
    host: ${MAIL_DOMAIN}
    port: 8090
    use_https: true
```

3. Start services:
```bash
./scripts/service/start-silver-unified.sh
```

## Comparison Table

| Feature | Legacy Scripts | Pluggable Architecture |
|---------|---------------|------------------------|
| **Number of Scripts** | 2 (one per IdP) | 1 (unified) |
| **Code Duplication** | ~160 lines duplicated | 0 lines duplicated |
| **Adding New IdP** | Copy 200 lines, modify everywhere | Implement 5 functions |
| **Configuration** | Hardcoded in script | Centralized in YAML |
| **Maintainability** | Difficult | Easy |
| **Testability** | Hard to test independently | Each provider is isolated |
| **Consistency** | May diverge over time | Always consistent |
| **Architecture** | Procedural | Strategy + Factory patterns |

## Troubleshooting

### Issue: "No identity provider configured"

**Cause:** Missing `identity:` section in `conf/silver.yaml`

**Solution:**
```yaml
# Add this to conf/silver.yaml
identity:
  provider: thunder  # or keycloak
```

### Issue: Legacy script still being used in automation

**Cause:** Old scripts referenced in CI/CD or cron jobs

**Solution:** Update automation to use unified script:

```bash
# Old (in CI/CD)
./scripts/service/start-silver.sh

# New (in CI/CD)
./scripts/service/start-silver-unified.sh
```

### Issue: Docker compose file not found

**Cause:** IdP docker-compose files not in new location

**Solution:** Files should be in `scripts/idp/docker/`:

```bash
ls -la scripts/idp/docker/
# Should show:
# docker-compose.thunder.yaml
# docker-compose.keycloak.yaml
```

### Issue: Functions not found

**Cause:** Factory not sourced correctly

**Solution:** Ensure factory is sourced before use:

```bash
source scripts/idp/idp-factory.sh
create_idp_provider "thunder"
```

## Rollback Plan

If you need to rollback to legacy scripts:

1. Stop unified setup:
```bash
./scripts/service/stop-silver.sh
```

2. Use legacy script:
```bash
# For Thunder
./scripts/service/start-silver.sh

# For Keycloak
./scripts/service/start-silver-keycloak.sh
```

3. Legacy scripts still work and will continue to work until next major version.

## Timeline

- **v1.0**: Legacy scripts (current for existing users)
- **v2.0**: Pluggable architecture introduced (NEW)
- **v2.x**: Both legacy and new scripts supported
- **v3.0**: Legacy scripts deprecated
- **v4.0**: Legacy scripts removed

## Benefits After Migration

### For Administrators

1. **Single Entry Point**: One script to start any IdP configuration
2. **Easy Switching**: Change IdP by editing config file
3. **Consistent Behavior**: Same workflow for all IdPs

### For Developers

1. **DRY Code**: No duplication, easier maintenance
2. **Easy Extension**: Add new IdPs without touching core logic
3. **Clean Architecture**: Testable, maintainable, scalable

### For Contributors

1. **Clear Contract**: Interface defines what providers must do
2. **Template Available**: Copy and customize for new IdPs
3. **Isolated Changes**: Changes to one provider don't affect others

## Testing Matrix

| Test Case | Legacy | Unified | Result |
|-----------|--------|---------|--------|
| Start with Thunder | ✅ | ✅ | Both work |
| Start with Keycloak | ✅ | ✅ | Both work |
| Switch IdPs | ❌ Manual | ✅ Config change | Unified easier |
| Add new IdP | ❌ Copy script | ✅ 5 functions | Unified easier |
| Maintain consistency | ⚠️ Hard | ✅ Automatic | Unified better |

## Checklist

Use this checklist to ensure smooth migration:

- [ ] Backup current `conf/silver.yaml`
- [ ] Add `identity:` section to `conf/silver.yaml`
- [ ] Test unified script in development
- [ ] Verify all containers start correctly
- [ ] Check IdP health endpoints
- [ ] Update documentation/runbooks
- [ ] Update CI/CD pipelines
- [ ] Update cron jobs/automation
- [ ] Train team on new workflow
- [ ] Monitor for issues

## Support

If you encounter issues during migration:

1. **Check Logs**: `docker compose logs -f`
2. **Review Config**: Ensure `conf/silver.yaml` is valid
3. **Test Providers**: Run `scripts/idp/providers/<provider>-idp.sh` directly
4. **Validate Interface**: Check all required functions are implemented
5. **Rollback if Needed**: Legacy scripts still work

## Next Steps

After successful migration:

1. **Update Documentation**: Reflect new setup in your docs
2. **Train Team**: Ensure everyone knows the new workflow
3. **Monitor**: Watch for any issues in production
4. **Optimize**: Consider adding custom providers if needed
5. **Contribute**: Share your custom providers with the community

## Conclusion

The pluggable architecture provides a cleaner, more maintainable way to manage Identity Providers in Silver Mail. While legacy scripts still work, migrating to the unified approach will make your setup more flexible and easier to maintain long-term.

For questions or issues, refer to:
- [IdP Architecture Documentation](./IdP-Architecture.md)
- [Main README](../scripts/idp/README.md)
- GitHub Issues
