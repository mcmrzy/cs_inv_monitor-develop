# Quick Reference: Key Rotation Checklists

Simple, actionable checklists for fast execution during key rotation operations.

---

## JWT Secret Rotation (90 days)

**Estimated Duration**: 15-20 minutes  
**Risk Level**: Medium  
**Maintenance Window Required**: Yes

### Pre-Rotation Checklist
- [ ] Schedule maintenance window and notify users (email + in-app announcement)
- [ ] Generate new 32-byte random secret
  ```bash
  openssl rand -base64 32 | tr -d '=+/' > /tmp/new_jwt_secret.txt
  cat /tmp/new_jwt_secret.txt
  ```
- [ ] Backup current `.env.prod` file
  ```bash
  cp deploy/.env.prod deploy/.env.prod.backup.$(date +%Y%m%d_%H%M%S)
  ```
- [ ] Confirm access to production server via SSH or direct terminal
- [ ] Prepare monitoring dashboard for auth error tracking

### Rotation Steps
- [ ] Update `JWT_SECRET` in `.env.prod`:
  ```bash
  sed -i 's/^JWT_SECRET=.*/JWT_SECRET='"$(cat /tmp/new_jwt_secret.txt)"'/' deploy/.env.prod
  # OR manually edit if sed not available on Windows
  # nano deploy/.env.prod  # Replace JWT_SECRET value and save
  ```
- [ ] Verify change applied correctly:
  ```bash
  grep "^JWT_SECRET=" deploy/.env.prod
  ```
- [ ] Restart affected services:
  ```bash
  docker-compose -f deploy/docker-compose.prod.yml restart inv-api-server
  docker-compose -f deploy/docker-compose.prod.yml restart api-gateway
  ```
- [ ] Verify services running healthy:
  ```bash
  docker-compose -f deploy/docker-compose.prod.yml ps
  docker logs inv-api-server --tail 30
  docker logs api-gateway --tail 30
  ```

### Post-Rotation Verification (15 minutes monitoring)
- [ ] Monitor authentication error rates (expect temporary spike, then stabilize)
- [ ] Test login with test user account
- [ ] Verify API calls using new tokens succeed
- [ ] Check background jobs executing properly
- [ ] Confirm WebSocket connections re-establishing for active users
- [ ] Review error logs for unusual patterns

### Cleanup Tasks
- [ ] Archive old secret securely (Hashicorp Vault or encrypted storage)
- [ ] Document rotation in audit log (`docs/key_rotation_audit_log_template.csv`)
- [ ] Delete temporary secret file from server
  ```bash
  rm -f /tmp/new_jwt_secret.txt
  ```
- [ ] Send completion notification to stakeholders

**Rollback Command** (if issues detected):
```bash
cp deploy/.env.prod.backup.* deploy/.env.prod
docker-compose -f deploy/docker-compose.prod.yml restart inv-api-server api-gateway
```

---

## Refresh Token Encryption Key Rotation (180 days)

**Estimated Duration**: 60-90 minutes  
**Risk Level**: HIGH  
**Maintenance Window Required**: Yes (scheduled migration)

### Complexity Alert
This procedure requires database migration and dual-key support. Plan carefully.

### Pre-Rotation Preparation
- [ ] Review `pkg/jwt/jwt.go` implementation details
- [ ] Create database backup before migration
- [ ] Prepare dual-key configuration update:
  ```yaml
  # Add to config structure temporarily
  type Config struct {
      EncryptionKey         string `mapstructure:"encryption_key"`           // Primary
      EncryptionKeyFallback string `mapstructure:"encryption_key_fallback"` // Migration period
  }
  ```
- [ ] Develop/verify migration script `cmd/migrate_tokens.go`
- [ ] Schedule low-traffic period for migration

### Migration Steps
- [ ] Deploy application with both keys configured:
  ```bash
  # .env.prod updates
  echo "ENCRYPTION_KEY=$NEW_PRIMARY_KEY" >> deploy/.env.prod
  echo "ENCRYPTION_KEY_FALLBACK=$OLD_KEY" >> deploy/.env.prod
  ```
- [ ] Redeploy services:
  ```bash
  docker-compose -f deploy/docker-compose.prod.yml up -d --build inv-api-server
  ```
- [ ] Run token migration script:
  ```bash
  docker exec -it <inv-api-server-container-id> \
    go run cmd/migrate_tokens.go
  ```
- [ ] Verify migration successful (check logs, validate token count)
- [ ] Test token decryption with fallback key still active
- [ ] Wait 24-48 hours for traffic pattern stabilization

### Post-Migration Cleanup
- [ ] Remove fallback key from configuration:
  ```bash
  # Keep only primary key
  sed -i '/^ENCRYPTION_KEY_FALLBACK=/d' deploy/.env.prod
  ```
- [ ] Redeploy with single key configuration
- [ ] Monitor for any decryption failures
- [ ] Securely delete old encryption key from secure vault after 30 days

### Verification Checklist
- [ ] New tokens encrypt successfully with new key
- [ ] Existing tokens decrypt correctly (after migration completes)
- [ ] No increase in authentication errors
- [ ] Database token size within expected range

**Important**: Do not remove the fallback key until all stored tokens have been re-encrypted with the new primary key.

---

## SMTP Credential Rotation (60 days)

**Estimated Duration**: 10-15 minutes  
**Risk Level**: Low  
**Maintenance Window Required**: No (can be done live)

### Pre-Rotation Tasks
- [ ] Log into SMTP provider portal (Gmail/Gsuite/SendGrid/etc.)
- [ ] Generate new password/app-specific token at provider
- [ ] Verify sender address capability with new credential
- [ ] Note provider-side rate limits or restrictions

### Rotation Steps
- [ ] Update credentials at SMTP provider first (make new password active)
- [ ] Extract new password/token from provider dashboard
- [ ] Update `EMAIL_PASSWORD` in `.env.prod`:
  ```bash
  sed -i 's/^EMAIL_PASSWORD=.*/EMAIL_PASSWORD='"NEW_PROVIDER_PASSWORD"'/' deploy/.env.prod
  ```
- [ ] If `EMAIL_USERNAME` also changing:
  ```bash
  sed -i 's/^EMAIL_USERNAME=.*/EMAIL_USERNAME='"NEW_USERNAME"'/' deploy/.env.prod
  ```
- [ ] Verify config changes:
  ```bash
  grep "^EMAIL_" deploy/.env.prod
  ```
- [ ] Test email delivery immediately:
  ```bash
  curl -X POST https://your-domain.com/api/v1/test-email \
    -H "Content-Type: application/json" \
    -d '{"to": "admin@yourcompany.com"}'
  ```

### Monitoring (24 hours)
- [ ] Check email delivery success rate (target: ≥ 99%)
- [ ] Monitor bounce rates in SMTP provider dashboard
- [ ] Review application logs for SMTP connection errors
- [ ] Test password reset email flow end-to-end
- [ ] Verify invitation emails deliver successfully

### Provider-Specific Notes
- **Gmail/Gsuite**: Use "App Passwords" feature, not main account password
- **SendGrid**: Generate API key with "Mail Send" permission
- **AWS SES**: Rotate IAM access keys, not master credentials

**Rollback**: Revert to previous `EMAIL_PASSWORD` in `.env.prod` and restart service if delivery fails persistently.

---

## Redis Password Rotation (90 days)

**Estimated Duration**: 30-45 minutes  
**Risk Level**: Medium-High (cache invalidation impact)  
**Maintenance Window Required**: Recommended but optional

### High-Risk Warning
All cached data will be lost during rotation. API response times may increase temporarily.

### Pre-Rotation Assessment
- [ ] Confirm no critical in-flight transactions depend on cached state
- [ ] Identify high-traffic periods to avoid (schedule accordingly)
- [ ] Prepare monitoring queries for cache performance analysis
- [ ] Ensure database can handle increased load during cache warm-up

### Rotation Steps

#### Option A: Graceful Degradation Mode (Recommended)
- [ ] Temporarily disable RBAC cache:
  ```bash
  curl -X POST http://localhost:8080/admin/disable-cache \
    -H "Authorization: Bearer $ADMIN_TOKEN"
  ```
- [ ] Update Redis infrastructure-level password (Docker secrets/Kubernetes):
  ```bash
  # For Docker Compose environments
  docker service update inv-redis --secret-rm redis-pass --secret-add redis-pass=new_pass_file
  # OR update redis.conf directly if applicable
  ```
- [ ] Rotate application-level password reference:
  ```bash
  sed -i 's/^REDIS_PASSWORD=.*/REDIS_PASSWORD='"NEW_PASSWORD"'/' deploy/.env.prod
  ```
- [ ] Roll out service updates gradually (canary deployment):
  ```bash
  # Scale down to 1 instance first
  docker-compose -f deploy/docker-compose.prod.yml scale inv-api-server=1
  sleep 60  # Wait for stability
  # Restore full capacity
  docker-compose -f deploy/docker-compose.prod.yml scale inv-api-server=3
  ```

#### Option B: Full Restart (Faster but more downtime)
- [ ] Disable caching temporarily (graceful degradation):
  ```bash
  # Set environment flag or use admin endpoint
  ```
- [ ] Stop services cleanly:
  ```bash
  docker-compose -f deploy/docker-compose.prod.yml down inv-api-server
  ```
- [ ] Update password in `.env.prod`:
  ```bash
  sed -i 's/^REDIS_PASSWORD=.*/REDIS_PASSWORD='"NEW_PASSWORD"'/' deploy/.env.prod
  ```
- [ ] Restart services:
  ```bash
  docker-compose -f deploy/docker-compose.prod.yml up -d inv-api-server
  ```

### Post-Rotation Monitoring
- [ ] Monitor cache miss rates (expected to be high initially)
- [ ] Track API response time recovery (should warm up within 5-10 minutes)
- [ ] Verify cache hit rate returning to baseline (> 80%)
- [ ] Check database load increases are within acceptable limits
- [ ] Confirm Redis connection pool functioning correctly

### Cache Re-enablement (if disabled during rotation)
- [ ] Re-enable RBAC cache via admin endpoint
- [ ] Trigger initial cache population for common queries
- [ ] Monitor cache build-up over next 30 minutes

**Performance Expectation**: First 5 minutes post-rotation will show elevated response times as cache warms. This is normal and should self-correct automatically.

---

## Emergency Rotation (<1 hour response)

**Estimated Duration**: 30-60 minutes  
**Risk Level**: CRITICAL - All credentials rotated simultaneously  
**Maintenance Window Required**: No (emergency operation)

### Activation Criteria
Trigger emergency rotation when ANY of these conditions met:
- Confirmed credential leak in logs or code repository
- Employee termination with production access
- Security audit indicating immediate compromise risk
- Active intrusion attempt detected

### Emergency Procedure

#### Step 1: Activate Response Team (5 minutes)
- [ ] Notify security team lead immediately
- [ ] Open emergency Slack channel or bridge call
- [ ] Designate incident commander
- [ ] Start incident timeline documentation

#### Step 2: Execute Rapid Rotation Script (15 minutes)
- [ ] Navigate to deploy directory:
  ```bash
  cd deploy
  ```
- [ ] Run emergency rotation script:
  ```bash
  ./scripts/rapid-key-rotation.sh all
  ```
- [ ] Script output confirms rotation completion

#### Step 3: Force Global Logout (automated by script)
- [ ] Verify Redis session cache cleared
- [ ] Confirm all JWT tokens invalidated
- [ ] Check service restart logs for successful rollouts

#### Step 4: Enable Enhanced Logging (5 minutes)
- [ ] Increase application log verbosity:
  ```bash
  docker service update inv-api-server --log-driver json-file --log-opt max-size=10m --log-opt max-file=10
  ```
- [ ] Enable verbose authentication logging
- [ ] Route critical auth events to separate monitoring stream

#### Step 5: User Communication (15-20 minutes)
- [ ] Post emergency announcement on public-facing login page:
  ```html
  <div class="emergency-banner">
    <strong>Security Maintenance:</strong> We've performed urgent security updates. 
    Please log in again. Our team is monitoring systems closely.
  </div>
  ```
- [ ] Send mass notification email explaining situation (without revealing sensitive details)
- [ ] Update status page with incident timeline and expected resolution time

#### Step 6: Post-Incident Validation (30 minutes)
- [ ] Test authentication with known-good credentials
- [ ] Verify all services responding correctly
- [ ] Monitor error spikes and unusual patterns
- [ ] Conduct basic functionality checks across critical paths

### Post-Incident Requirements (within 48 hours)
- [ ] Complete root cause analysis report
- [ ] Document lessons learned
- [ ] Schedule post-mortem meeting with all stakeholders
- [ ] Identify preventive controls to reduce recurrence
- [ ] Update this policy based on findings
- [ ] File formal incident report (INC-YYYY-NNN)

**Communication Template** (adapt for your channels):
```
Subject: Urgent Security Update Required

Dear Users,

We recently performed an emergency security rotation affecting all authentication 
credentials. This proactive measure was taken in response to [brief reason without 
compromising security].

Impact:
- All active sessions have been terminated
- You will need to log in again using your existing credentials
- No action required beyond re-authentication

If you experience any issues logging in, please contact support@yourcompany.com.

We apologize for any inconvenience and appreciate your understanding as we maintain 
the highest security standards for our platform.

Best regards,
Security Team
```

---

## Quick Troubleshooting

### Common Issues After Rotation

**Issue**: Authentication failing for all users  
**Cause**: Service not restarted or config not updated  
**Fix**: Verify `.env.prod` changed, confirm services restarted successfully  

**Issue**: High 401 error rate persisting > 30 minutes  
**Cause**: Mobile/desktop apps still using old tokens  
**Fix**: This is expected behavior; users will naturally refresh tokens. Monitor for normalization.

**Issue**: Email delivery failing after SMTP rotation  
**Cause**: Incorrect password or provider not accepting new credentials  
**Fix**: Double-check password copied exactly from provider portal; verify account not locked

**Issue**: Cache performance degraded after Redis rotation  
**Cause**: Normal cache warm-up period  
**Fix**: Wait 5-10 minutes; cache will rebuild automatically. If not improving, check Redis connectivity.

**Issue**: Background jobs not executing  
**Cause**: Service dependencies not restarting in correct order  
**Fix**: Restart services in sequence: Redis → PostgreSQL → inv-api-server → api-gateway

---

## Contact Support

For assistance with key rotation procedures:
- **Security Team**: security@company.com
- **DevOps On-Call**: devops-oncall@company.com (Slack: #devops-incidents)
- **Emergency Hotline**: +1-XXX-XXX-XXXX (for critical incidents only)

**Document Version**: 1.0  
**Last Updated**: July 21, 2026  
**Owner**: Security Operations Center
