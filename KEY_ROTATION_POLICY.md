# Production Security Key Rotation Policy

## 1. Overview

This document outlines the policies and procedures for rotating security-critical credentials in production environments to maintain system security, ensure compliance with industry standards, and minimize unauthorized access risks. Regular key rotation is a fundamental security practice that limits the impact of potential credential compromises and demonstrates security maturity to auditors and stakeholders.

**Scope**: This policy applies to all production systems including `api-gateway`, `inv-api-server`, Redis cache, SMTP email services, and related infrastructure managed through `deploy/.env.prod` and associated configuration files.

**Effective Date**: July 21, 2026  
**Review Cycle**: Annual review required, or immediately following security incidents

---

## 2. Key Types and Rotation Frequencies

### 2.1 JWT Secret Keys

**Location**: `deploy/.env.prod` variable `JWT_SECRET`

**Rotation Frequency**: Every 90 days (quarterly) or immediately upon compromise

**Security Classification**: CRITICAL  
**Owner**: Security Team / DevOps Engineer

**Impact Assessment**: 
- All active user sessions will be invalidated immediately after rotation
- Users must re-login after rotation (tokens invalidated within seconds of restart)
- API calls using old tokens will fail with 401 Unauthorized errors
- Background services and scheduled jobs need coordinated restart windows
- Third-party integrations using JWT for authentication must be updated simultaneously

**Risk Window**: Minimum 5-minute window during service restart where authentication may fail temporarily

**Procedure Reference**: See Section 4.1 for detailed step-by-step instructions

---

### 2.2 Refresh Token Encryption Key

**Location**: Custom encryption key used in `pkg/jwt/jwt.go` 

**Rotation Frequency**: Every 180 days (semi-annually)

**Special Considerations**:
- Old encrypted refresh tokens stored in database become unreadable without the original key
- All active sessions will need token renewal over a grace period
- Database may require decryption/re-encryption of stored tokens during migration
- Long-running mobile app sessions on user devices will expire sooner than expected

**Complexity Level**: HIGH - Requires database migration strategy and dual-key support during transition

**Grace Period**: Recommended 7-day transition period where both old and new keys are supported

**Procedure Reference**: See Section 4.2 for complex migration procedure

---

### 2.3 SMTP Credentials

**Location**: Email service configuration in `config.docker.yaml` and `deploy/.env.prod` variables `EMAIL_HOST`, `EMAIL_PORT`, `EMAIL_USERNAME`, `EMAIL_PASSWORD`

**Rotation Frequency**: Every 60 days (compliance requirement for email authentication)

**Compliance Driver**: SOC 2 Type II requirements mandate quarterly credential rotation for external communication services

**Impact Assessment**:
- Email delivery will fail until credentials are updated in application configuration
- Password reset emails, invitation emails, and notification emails will bounce
- No user-facing impact if rotation completed before SMTP provider enforces change

**Risk Window**: Temporary email delivery interruption (typically < 15 minutes)

**Procedure Reference**: See Section 4.3 for step-by-step SMTP credential updates

---

### 2.4 Redis Password

**Location**: `deploy/.env.prod` variable `REDIS_PASSWORD`

**Rotation Frequency**: Every 90 days

**Impact**: All cached session data, authorization cache, temporary tokens lost on rotation

**Cache Impact Assessment**:
- RBAC permission cache cleared (users experience initial auth delay until cache rebuilds)
- Session state information lost (active WebSocket connections may drop)
- API response caching disabled temporarily (increased database load during warm-up period)
- Performance degradation expected for first 5-10 minutes post-rotation

**Pre-Rotation Checklist**:
- Confirm no critical in-flight transactions depend on cached state
- Prepare monitoring queries for post-rotation cache performance analysis
- Schedule during low-traffic periods when cache warm-up impact is minimized

**Procedure Reference**: See Section 4.4 for safe Redis password rotation with minimal disruption

---

### 2.5 Database Encryption Keys

**Location**: PostgreSQL connection strings in `config.docker.yaml`

**Rotation Frequency**: Annually (12 months)

**Additional Notes**: Database encryption key rotation requires maintenance window and may involve data re-encryption. Coordinate with database administrator.

**Procedure Reference**: Contact Database Administration Team for specialized procedure

---

## 3. Emergency Rotation Procedures

### When to Rotate Immediately:

Trigger immediate rotation under any of the following circumstances:

1. **Suspected credential leak** discovered in logs, code repository, or memory dumps
2. **Employee termination** involving personnel with access to production credentials
3. **Security audit findings** indicating potential compromise risk
4. **Compliance mandate changes** requiring immediate credential updates
5. **Phishing attack** targeting authentication credentials
6. **Supply chain attack** affecting third-party service integrations

### Emergency Procedure Protocol:

1. **Immediate Notification** (within 15 minutes):
   - Activate incident response team via Slack emergency channel
   - Notify security team lead and DevOps manager
   - Document time of discovery and initial assessment

2. **Execute Rapid Rotation** (target: < 60 minutes):
   - Use pre-tested rapid rotation script (Section 5)
   - Rotate all affected credentials simultaneously to prevent partial deployment issues
   - Force logout of all users globally as precautionary measure

3. **Post-Rotation Monitoring** (first 2 hours):
   - Monitor authentication error spikes (expect temporary increase)
   - Track failed login attempts for anomaly detection
   - Verify background services functioning correctly
   - Check third-party integration health

4. **Root Cause Investigation** (within 24 hours):
   - Conduct forensic analysis of suspected compromise vector
   - Review access logs for unauthorized access attempts
   - Identify scope of potential exposure
   - Prepare incident report for management review

---

## 4. Detailed Rotation Procedures

*Detailed procedures provided in subsequent sections cover:*
- *Section 4.1: JWT Secret Rotation*
- *Section 4.2: Refresh Token Encryption Key Rotation*
- *Section 4.3: SMTP Credential Updates*
- *Section 4.4: Redis Password Rotation*
- *Section 4.5: Database Connection Key Rotation*

*Each section includes prerequisites, step-by-step commands, verification steps, and rollback procedures.*

---

## 5. Rapid Emergency Rotation

For immediate threats requiring sub-hour response times:

### Emergency Response Package:

**Script Location**: `deploy/scripts/rapid-key-rotation.sh`

**Prerequisites**:
- Script has executable permissions (`chmod +x deploy/scripts/rapid-key-rotation.sh`)
- SSH access to production server confirmed
- Incident commander designated and communicating via dedicated channel

### Procedure Steps:

1. **Activate Incident Response** (5 minutes):
   ```bash
   # Create incident timestamp for tracking
   INCIDENT_TIMESTAMP=$(date +%Y%m%d_%H%M%S)
   echo "Starting emergency rotation at $INCIDENT_TIMESTAMP"
   ```

2. **Execute Rapid Rotation** (10-15 minutes):
   ```bash
   ./deploy/scripts/rapid-key-rotation.sh all
   ```

3. **Force Global Logout** (automated by script):
   - Clear Redis session cache completely
   - Invalidate all JWT tokens simultaneously
   - Restart api-gateway and inv-api-server containers

4. **Enable Enhanced Logging** (automated):
   - Increase log verbosity for authentication components
   - Enable detailed audit logging for all auth events
   - Route critical auth logs to separate monitoring dashboard

5. **User Communication** (15-30 minutes):
   - Post emergency announcement on login page
   - Send mass notification email explaining situation
   - Update status page with incident timeline

6. **Post-Incident Actions** (within 48 hours):
   - Conduct post-mortem meeting with all stakeholders
   - Document root cause and lessons learned
   - Update this policy based on lessons identified
   - Implement additional preventive controls if gaps identified

---

## 6. Verification and Monitoring

### Automated Validation Checks (run via CI/CD pipeline):

After every rotation, automatically execute the following verifications:

1. **Health Check Endpoint Validation**:
   ```bash
   curl -f https://your-domain.com/api/v1/health || exit 1
   ```

2. **Authentication Flow Testing**:
   - Test user login with test account
   - Verify JWT token generation succeeds
   - Validate token expiration behavior matches expectations

3. **Authorization Functionality**:
   - Confirm admin users can access administrative endpoints
   - Verify regular users cannot access restricted resources
   - Test role-based permission boundaries

4. **Service Dependency Checks**:
   - Verify database connectivity
   - Confirm Redis cache operations functional
   - Test email delivery capability
   - Check WebSocket connection stability

### Manual Validation Checklist:

Within 30 minutes of rotation completion:

- [ ] Log into admin panel successfully with known-good credentials
- [ ] Create test organization and verify it appears in dashboard
- [ ] Send test invitation email and confirm receipt
- [ ] Trigger device transfer request and monitor success
- [ ] Verify real-time telemetry streaming working correctly
- [ ] Check scheduled jobs executing as expected
- [ ] Test password reset flow end-to-end

### Monitoring Metrics Thresholds:

Track these metrics for 60 minutes post-rotation:

| Metric | Expected Baseline | Acceptable Spike Limit | Alert Threshold |
|--------|------------------|----------------------|-----------------|
| Login Success Rate | ≥ 99% | ≥ 98% | < 95% for 5min |
| Auth Error Spike | < 1% | < 5% of baseline | > 10% for 5min |
| Cache Hit Rate Recovery | N/A | Recovery within 5min | Still < 50% after 10min |
| API Response Time | P95 < 200ms | P95 < 500ms temporarily | P95 > 1s consistently |
| Error Log Volume | Normal | < 2x normal baseline | > 3x normal baseline |

### Rollback Triggers:

Initiate immediate rollback procedure if any of the following occur:

1. **Authentication Failure Rate** exceeds 10% for 5 consecutive minutes
2. **Error Log Volume** exceeds 3x normal operational baseline
3. **User Complaints** about authentication issues reported via support channels
4. **Database Connectivity** failures persist beyond 2-minute window
5. **Service Health** checks consistently failing across multiple instances

**Rollback Procedure**:
```bash
# Restore previous .env.prod from backup
cp deploy/.env.prod.backup deploy/.env.prod
docker-compose -f deploy/docker-compose.prod.yml down
docker-compose -f deploy/docker-compose.prod.yml up -d
# Verify services restored to pre-rotation state
```

---

## 7. Automation Recommendations

Long-term improvements to streamline key rotation and reduce human error:

### Phase 1: Hashicorp Vault Integration (Q4 2026)

**Benefits**:
- Centralized secrets management with audit trail
- Automatic secret rotation with configurable schedules
- Dynamic credentials eliminating static secrets
- Fine-grained access control per service

**Implementation Steps**:
1. Deploy Hashicorp Vault cluster in high-availability mode
2. Configure AWS Secrets Manager or Azure Key Vault integration
3. Migrate current credentials into Vault
4. Update application configurations to fetch secrets dynamically

### Phase 2: Infrastructure as Code Automation (Q1 2027)

**Terraform Integration**:
- Define secrets as Terraform resources with auto-generation
- Implement rotation via Terraform plan/apply in CI/CD pipeline
- Use Terraform workspaces for environment isolation

**Example Terraform Resource**:
```hcl
resource "random_bytes" "jwt_secret" {
  length = 32
}

resource "aws_secretsmanager_secret" "jwt" {
  name = "production/jwt-secret"
}

resource "aws_secretsmanager_secret_version" "jwt_version" {
  secret_id     = aws_secretsmanager_secret.jwt.id
  secret_string = random_bytes.jwt_secret.base64
}
```

### Phase 3: Scheduled Automation (Q2 2027)

**GitHub Actions Cron Jobs**:
```yaml
name: Scheduled Key Rotation
on:
  schedule:
    - cron: '0 2 1 * *'  # First day of each month at 2 AM UTC
jobs:
  rotate-keys:
    runs-on: ubuntu-latest
    steps:
      - name: Rotate JWT Secret
        run: ./scripts/scheduled-rotation.sh jwt
      - name: Verify Rotation
        run: ./scripts/verify-rotation.sh
```

### Phase 4: Proactive Alerting (Ongoing)

**Slack Notifications**:
- 30 days before scheduled rotation due date
- 7 days before scheduled rotation due date
- 1 day before scheduled rotation due date
- Immediate alert on successful rotation completion
- Immediate alert on rotation failure

**Implementation**: Integrate with existing monitoring platform (Prometheus/Grafana) to trigger alerts based on calendar-based rotation schedule stored in configuration management database (CMDB).

---

## 8. Compliance Notes and Audit Requirements

### Documentation Requirements:

**Mandatory Audit Trail Entries**: Document ALL rotations with the following fields:

| Field | Description | Example |
|-------|-------------|---------|
| Date | ISO 8601 formatted rotation date | 2026-07-21T14:30:00Z |
| Rotated By | Full name and email of person performing rotation | john.doe@company.com |
| Key Type | Specific credential rotated | JWT_SECRET |
| Reason | Business justification for rotation | Quarterly rotation per policy |
| Procedure ID | Reference to specific procedure executed | PROC-JWT-001 |
| Verification Status | Result of post-rotation validation | Success/Failed/Partial |
| Rollback Required | Whether rollback was necessary | Yes/No |
| Incident ID | If rotation triggered by incident | INC-2026-001 or N/A |
| Duration | Total time from start to verification complete | 45 minutes |
| Issues Encountered | Any problems during rotation process | None / Minor cache delay |

**Audit Log Template**: Located at `docs/key_rotation_audit_log_template.csv` for structured tracking

### Credential Retention Policy:

1. **Old Credentials Secure Storage**: 
   - Retain expired credentials in secure vault (Hashicorp Vault or equivalent) for minimum 30 days post-rotation
   - Enable read-only access only for emergency rollback scenarios
   - Delete securely after 30-day retention period using cryptographic erasure

2. **Backup File Management**:
   - Maintain `.env.prod.old.*` backups for 90 days maximum
   - Encrypt all backup files using AES-256 before storage
   - Store in separate location from production environment
   - Rotate backup encryption key annually

3. **Log Retention**:
   - Authentication logs retained for minimum 1 year (SOC 2 requirement)
   - Audit trail entries retained indefinitely
   - Incident reports retained for 7 years

### Third-Party Audit Preparation:

**Annual Security Review Deliverables**:
- Complete rotation history for past 12 months
- Evidence of successful verification after each rotation
- List of emergency rotations with root cause analysis
- User impact metrics demonstrating minimal disruption
- Compliance mapping showing alignment with framework requirements (SOC 2, ISO 27001, GDPR)

**Recommended External Audit Frequency**: Annual penetration testing including credential rotation effectiveness validation

---

## 9. Training and Respons

### Personnel Requirements:

**Primary Owners** (trained on all procedures):
- Senior DevOps Engineers (minimum 2 individuals cross-trained)
- Security Team Lead
- Site Reliability Engineering Manager

**Secondary Contacts** (trained on emergency procedures only):
- On-call engineers (rotating weekly)
- Junior DevOps engineers (under supervision)
- Engineering managers (awareness level training)

### Training Schedule:

- **Quarterly drills**: Simulated emergency rotation in staging environment
- **Bi-annual full exercises**: Complete rotation cycle including verification
- **Annual certification**: All primary owners must demonstrate proficiency
- **New hire onboarding**: Include key rotation policy overview within first week

### Knowledge Transfer:

All procedure documentation must be reviewed and validated by at least two senior engineers before deployment to production. Cross-training records maintained in HR system with competency assessments tracked quarterly.

---

## 10. Policy Exceptions and Waivers

### Exception Process:

Any deviation from this policy requires formal approval:

1. **Exception Request Form** submitted to Security Committee
2. **Risk Assessment** documenting business justification and compensating controls
3. **Executive Approval** from CTO or VP of Engineering
4. **Time-Limited Authorization** (maximum 90 days)
5. **Documentation** of exception in security management system

### Approved Exception Scenarios:

- **Critical Bug Fix**: Emergency patch requiring bypass of standard rotation window
- **Vendor Lock-in**: Third-party service limiting rotation frequency capabilities
- **Regulatory Conflict**: Local regulations contradicting rotation requirements

All exceptions logged and reviewed monthly by Security Committee with recommendation for policy update if recurring pattern identified.

---

## 11. Related Documents and References

### Internal Documentation:

- `deploy/.env.prod.example` - Environment variable template
- `pkg/jwt/jwt.go` - JWT implementation details
- `api-gateway/main.go` - Gateway authentication configuration
- `docs/security-audit-report.md` - Previous security audit findings
- `incident-response-procedure.md` - Comprehensive incident management guide

### External Standards:

- **NIST SP 800-53**: Security and Privacy Controls for Information Systems
- **ISO/IEC 27001:2022**: Information Security Management
- **SOC 2 Type II**: Service Organization Control criteria
- **PCI DSS v4.0**: Payment Card Industry Data Security Standard (if applicable)

### Regulatory Requirements:

- **GDPR Article 32**: Security of processing (EU)
- **CCPA Section 1798.150**: California Consumer Privacy Act
- **HIPAA Security Rule** (if handling healthcare data)

---

## 12. Document History and Revision Log

| Version | Date | Author | Changes | Approved By |
|---------|------|--------|---------|-------------|
| 1.0 | 2026-07-21 | Security Team | Initial creation | CTO |
| | | | | |

**Next Review Date**: July 21, 2027  
**Policy Owner**: Chief Information Security Officer (CISO)  
**Distribution**: All engineering staff, security team, DevOps personnel

---

**END OF POLICY DOCUMENT**

For questions or clarifications regarding this policy, contact the Security Team at security@company.com or create an issue in the internal security documentation repository.
