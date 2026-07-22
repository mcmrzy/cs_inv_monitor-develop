# Key Rotation System - Deployment & Installation Guide

## Quick Start: First Time Setup (15 minutes)

This guide will help you deploy the Production Security Key Rotation infrastructure to your production environment.

### Prerequisites Checklist

Before beginning deployment, ensure you have:

- [ ] SSH access to production server with sudo privileges
- [ ] Docker Compose installed and configured
- [ ] OpenSSL installed (for bash script users): `openssl version`
- [ ] PowerShell 7+ installed (for Windows-native users): `pwsh --version`
- [ ] Git Bash or WSL available (if using bash scripts on Windows)
- [ ] Backup of current `deploy/.env.prod` file
- [ ] Team members identified for rotation operations

---

## Step 1: Deploy Documentation Files

Documentation is already in place from the main deliverables. Verify all files exist:

```bash
# From project root directory
ls -la KEY_ROTATION_POLICY.md
ls -la QUICK_REFERENCE_KEY_ROTATION.md
ls -la docs/key_rotation_audit_log_template.csv
ls -la docs/KEY_ROTATION_SCHEDULING.md
```

**Expected output**: All files should exist

If any files are missing, re-run the initial document creation process.

---

## Step 2: Deploy Automation Scripts

### Option A: Bash Script Deployment (Recommended for Linux/WSL)

```bash
# Navigate to scripts directory
cd deploy/scripts

# Make script executable
chmod +x rapid-key-rotation.sh

# Verify permissions
ls -l rapid-key-rotation.sh
# Should show: -rwxr-xr-x ...

# Test script syntax
bash -n rapid-key-rotation.sh
# No output means syntax is valid
```

### Option B: PowerShell Script Deployment (Windows-native)

```powershell
# Navigate to scripts directory
cd deploy\scripts

# Verify script exists
Test-Path rapid-key-rotation.ps1

# Check PowerShell version (should be 7.0+)
$PSVersionTable.PSVersion
# If older, upgrade via Chocolatey: choco install powershell

# Test script execution policy
Get-ExecutionPolicy -List
# Set to RemoteSigned if blocked: Set-ExecutionPolicy RemoteSigned -Scope CurrentUser
```

### Option C: Dual Deployment (Hybrid Environment)

For organizations running both Linux and Windows systems, deploy both versions:

```bash
# Both scripts can coexist safely
cd deploy/scripts
chmod +x rapid-key-rotation.sh
# PowerShell .ps1 files auto-detect execution policy
```

---

## Step 3: Create Supporting Directories

```bash
# Create backup storage location
mkdir -p deploy/.backups

# Create log directory
mkdir -p logs

# Set appropriate permissions
chmod 700 deploy/.backups  # Only owner can read/write
chmod 700 logs             # Restrict log access

# Verify directory structure
tree deploy/.backups logs
```

### Directory Structure Expectations

```
project-root/
├── deploy/
│   ├── .backups/              # Secure storage for credential backups
│   │   └── .env.prod.pre_rotation.YYYYMMDD_HHMMSS
│   ├── configs/
│   ├── scripts/
│   │   ├── rapid-key-rotation.sh   # Bash version
│   │   └── rapid-key-rotation.ps1  # PowerShell version
│   └── .env.prod                # Current production credentials
├── docs/
│   ├── key_rotation_audit_log_template.csv  # Compliance tracking
│   └── KEY_ROTATION_SCHEDULING.md         # Automation guide
├── KEY_ROTATION_POLICY.md
├── QUICK_REFERENCE_KEY_ROTATION.md
└── logs/                          # Rotation operation logs
    └── emergency_rotation_YYYYMMDD_HHMMSS.log
```

---

## Step 4: Initialize Audit Log

```bash
# Create header row in audit log CSV
echo "Date,Rotated By,Key Type,Reason,Procedure ID,Verification Status,Rollback Required,Incident ID,Duration Minutes,Issues Encountered,Approved By" > docs/key_rotation_audit_log_template.csv

# Add sample entry (replace with actual data after first rotation)
cat >> docs/key_rotation_audit_log_template.csv << EOF
$(date -u +%Y-%m-%dT%H:%M:%SZ),setup-system,SYSTEM,Audit initialization,SYS-INIT-001,Success,No,N/A,0,None,System,Security Team
EOF

# Verify audit log format
head -5 docs/key_rotation_audit_log_template.csv
```

**Importance**: The audit log must exist before any rotation operations begin for compliance purposes.

---

## Step 5: Test Script Execution (SAFETY FIRST!)

### Critical: Always test in staging first!

#### Test Scenario 1: Dry Run (No Actual Changes)

Create a test environment file:

```bash
# Copy .env.prod to test location (DO NOT modify original yet)
cp deploy/.env.dev.deployed deploy/test_env.tmp || echo "# Test file" > deploy/test_env.tmp

# Modify test file to contain placeholder values
sed -i 's/^JWT_SECRET=.*/JWT_SECRET=test_placeholder_jwt_secret_12345678901234567890/' deploy/test_env.tmp
sed -i 's/^EMAIL_PASSWORD=.*/EMAIL_PASSWORD=test_placeholder_email_pwd_1234567890/' deploy/test_env.tmp
sed -i 's/^REDIS_PASSWORD=.*/REDIS_PASSWORD=test_placeholder_redis_pwd_1234567890/' deploy/test_env.tmp

# Execute script against test environment
cd deploy/scripts
./rapid-key-rotation.sh jwt --test-mode --env-file=../test_env.tmp
```

**Expected behavior**: 
- Backup created successfully
- Secret generated correctly
- Error messages indicating "no actual changes made"
- Clean exit without modifying real credentials

#### Test Scenario 2: Full End-to-End (Staging Environment)

Deploy to your **staging/pre-production** environment first:

```bash
# Target staging environment instead of production
export ENV_FILE_STAGING="deploy/.env.staging"

# Run script against staging
cd deploy/scripts
./rapid-key-rotation.sh redis --target=staging

# Verify staging services restart properly
docker-compose -f deploy/docker-compose.staging.yml ps

# Test authentication with new credentials
curl -X POST https://staging.your-domain.com/api/v1/test-auth -d '{"username": "test"}'
```

**Success criteria**:
- [ ] Staging services remain operational post-rotation
- [ ] Authentication flow works with new credentials
- [ ] No errors in service logs
- [ ] Audit log entry created correctly

---

## Step 6: Configure Automated Backups

### Manual Backup Schedule (First Month)

Execute daily backups during initial deployment phase:

```bash
#!/bin/bash
# File: deploy/scripts/daily-env-backup.sh

BACKUP_DATE=$(date +%Y%m%d)
BACKUP_DIR="deploy/.backups/$BACKUP_DATE"

mkdir -p "$BACKUP_DIR"

# Create timestamped backup
cp deploy/.env.prod "$BACKUP_DIR/.env.prod.$(date +%H%M%S)"

# Keep only last 7 days of backups
find deploy/.backups -maxdepth 1 -type d -mtime +7 -exec rm -rf {} \;

# Log completion
echo "$(date): Daily backup completed - $BACKUP_DIR" >> logs/backup_log.txt
```

Make executable and add to crontab:

```bash
chmod +x deploy/scripts/daily-env-backup.sh

# Add to crontab for daily execution at 2 AM
(crontab -l 2>/dev/null; echo "0 2 * * * /path/to/cs_inv_monitor/deploy/scripts/daily-env-backup.sh") | crontab -
```

---

## Step 7: Integration Testing

### Test 1: Emergency Rotation Workflow

Simulate a security incident requiring immediate rotation:

```bash
# Simulate leak discovery scenario
echo "Incident: Suspected JWT secret exposed in application logs"

# Execute emergency rotation
cd deploy/scripts
./rapid-key-rotation.sh all

# Verify all services affected
services=(inv-api-server api-gateway redis)
for service in "${services[@]}"; do
    docker-compose -f deploy/docker-compose.prod.yml ps | grep $service
done

# Monitor error rates
watch -n 5 'docker logs inv-api-server --tail 10 | grep -c "error"'
```

### Test 2: Rollback Procedure Verification

Practice restoring from backup:

```bash
# Get latest backup filename
LATEST_BACKUP=$(ls -t deploy/.backups/*.pre_rotation.* | head -1)

# Execute rollback
cp "$LATEST_BACKUP" deploy/.env.prod

# Restart affected services
docker-compose -f deploy/docker-compose.prod.yml restart inv-api-server api-gateway

# Verify services restored to previous state
curl -sf https://your-domain.com/api/v1/health
```

### Test 3: User Experience Impact Assessment

Measure real-world impact of rotation:

```bash
# Before rotation baseline metrics
PRE_LOGIN_SUCCESS=$(curl -s https://your-domain.com/api/v1/metrics | jq '.auth.login_success_rate')
PRE_API_LATENCY_P95=$(curl -s https://your-domain.com/api/v1/metrics | jq '.api.p95_latency_ms')

# Execute scheduled rotation (quarterly JWT rotation example)
./deploy/scripts/rapid-key-rotation.sh jwt

# Track metrics for 15 minutes post-rotation
for i in {1..15}; do
    sleep 60
    POST_LOGIN_SUCCESS=$(curl -s https://your-domain.com/api/v1/metrics | jq '.auth.login_success_rate')
    POST_API_LATENCY_P95=$(curl -s https://your-domain.com/api/v1/metrics | jq '.api.p95_latency_ms')
    
    echo "Minute $i: Login Success: $POST_LOGIN_SUCCESS%, API P95 Latency: ${POST_API_LATENCY_P95}ms"
done
```

**Acceptable thresholds**:
- Login success rate remains ≥ 98%
- API P95 latency increases < 50% temporarily
- Services fully recovered within 10 minutes

---

## Step 8: Team Training

### Role-Based Training Matrix

| Role | Required Reading | Hands-On Practice | Certification Required |
|------|------------------|-------------------|------------------------|
| Security Engineer | Policy, Quick Reference | Emergency rotation | Yes |
| DevOps Engineer | All documentation | Scheduled rotations | Yes |
| On-Call Engineer | Quick Reference, Scheduling | Emergency rotation simulation | Awareness level |
| Engineering Manager | Policy, Deliverables Summary | None required | N/A |
| Compliance Officer | Policy, Audit procedures | None required | N/A |

### Training Materials Checklist

- [ ] Conduct live demo of rotation procedure
- [ ] Provide each engineer personal copy of quick reference
- [ ] Distribute escalation contact list
- [ ] Share historical audit log entries as examples
- [ ] Create practice lab environment for hands-on sessions

### Hands-On Lab Exercise

Designate a training session:

```bash
# Create isolated training environment
docker-compose -f deploy/docker-compose.test.yml up -d

# Populate with test data
cd deploy/scripts
./rapid-key-rotation.sh jwt --training-mode

# Have trainees execute full rotation cycle
# Instructor monitors and provides feedback

# Debrief session discussing lessons learned
```

---

## Step 9: Enable Monitoring and Alerting

### Prometheus Metrics Integration

Add scrape configuration to `prometheus.yml`:

```yaml
# File: deploy/prometheus/prometheus.yml
global:
  scrape_interval: 15s

scrape_configs:
  - job_name: 'key-rotation-compliance'
    static_configs:
      - targets: ['localhost:9090']
    
    metrics_path: '/metrics'
    params:
      metric: ['key_rotation_last_timestamp', 'key_rotation_compliance_status']
```

Create alerting rules in `prometheus_alerts.yml`:

```yaml
# File: deploy/prometheus/prometheus_alerts.yml
groups:
  - name: key-rotation-alerts
    interval: 5m
    rules:
      - alert: JWTSecretOverdue
        expr: (time() - jwt_last_rotation_timestamp) / 86400 > 89
        for: 1h
        labels:
          severity: warning
        annotations:
          summary: "JWT secret rotation overdue: {{ $value }} days"
          
      - alert: RedisPasswordNotRotated
        expr: (time() - redis_last_rotation_timestamp) / 86400 > 89
        for: 1h
        labels:
          severity: critical
        annotations:
          summary: "Redis password rotation critically overdue: {{ $value }} days"
```

### Grafana Dashboard Provisioning

Automatically provision dashboard from existing JSON template:

```yaml
# File: deploy/grafana/provisioning/dashboards/key_rotation.yaml
apiVersion: 1

providers:
  - name: 'Key Rotation Compliance'
    orgId: 1
    folder: 'Security'
    type: file
    disableDeletion: false
    updateIntervalSeconds: 30
    options:
      path: /etc/grafana/dashboards/key_rotation.json
```

---

## Step 10: Production Validation

Before declaring system "production-ready", verify all components:

### Pre-Launch Checklist

- [ ] All documentation files present and accessible
- [ ] Scripts executable by authorized personnel only
- [ ] Backup directories secured with proper permissions
- [ ] Audit log initialized with correct headers
- [ ] Monitoring dashboards displaying real-time data
- [ ] Alert channels configured (Slack, email, SMS)
- [ ] Escalation matrix documented and distributed
- [ ] Team trained on all procedures
- [ ] Rollback procedures tested and validated
- [ ] Emergency contact information current

### Go/No-Go Decision Criteria

Proceed to production use ONLY if:

✅ 100% of checklist items completed  
✅ Staging environment testing successful  
✅ At least one dry-run executed  
✅ Two engineers certified on procedures  
✅ Management approval obtained  

If any items incomplete, delay production deployment until resolved.

---

## Step 11: Ongoing Maintenance

### Weekly Tasks (Automated)

```bash
#!/bin/bash
# Weekly compliance check script
# Place in cron: 0 6 * * 6

CHECK_STATUS="PASS"

# Check JWT age
JWT_AGE=$(awk -F',' '/JWT_SECRET/ {print int(($$0 - '"$(date +%s)"') / 86400)}' docs/key_rotation_audit_log_template.csv | tail -1)

if [ $JWT_AGE -gt 60 ]; then
    echo "WARNING: JWT secret approaching 90-day limit ($JWT_AGE days old)" >> logs/compliance_check.txt
    
    if [ $JWT_AGE -gt 85 ]; then
        CHECK_STATUS="FAIL"
        send_slack_alert "🚨 Critical: JWT rotation due in less than 5 days!"
    fi
fi

# Append weekly status to log
echo "$(date -u +%Y-%m-%dT%H:%M:%SZ): Weekly compliance check - $CHECK_STATUS" >> logs/weekly_reports.txt
```

### Monthly Tasks

1. Review audit log for gaps in documentation
2. Update contact information in scheduling guide
3. Verify backup integrity (sample restoration test)
4. Refresh monitoring dashboards
5. Report metrics to management team

### Quarterly Tasks

1. Execute actual scheduled rotation following policy
2. Conduct full-team drill exercise
3. Review and update policies based on lessons learned
4. Re-certify engineers on procedures
5. Prepare quarterly compliance report

---

## Troubleshooting Common Issues

### Issue: Script Execution Denied (Permission Denied)

**Solution**:
```bash
# Grant execute permissions
chmod +x deploy/scripts/rapid-key-rotation.sh

# Or run with explicit interpreter
bash deploy/scripts/rapid-key-rotation.sh jwt
```

### Issue: OpenSSL Not Found

**Solution**:
```bash
# Install OpenSSL on Ubuntu/Debian
sudo apt-get update && sudo apt-get install openssl

# On CentOS/RHEL
sudo yum install openssl

# On macOS with Homebrew
brew install openssl
```

### Issue: Docker Compose Not Recognized

**Solution**:
```bash
# Try alternative command (Docker Compose V2)
docker compose version

# Or install standalone
curl -LO https://github.com/docker/compose/releases/download/v2.20.0/docker-compose-$(uname -s)-$(uname -m)
sudo chmod +x docker-compose-$(uname -s)-$(uname -m)
sudo mv docker-compose-$(uname -s)-$(uname -m) /usr/local/bin/docker-compose
```

### Issue: Backup Creation Fails

**Solution**:
```bash
# Ensure backup directory exists with proper permissions
mkdir -p deploy/.backups
chmod 700 deploy/.backups

# Check disk space
df -h deploy/.backups

# Verify write permissions
touch deploy/.backups/.permission_test && rm deploy/.backups/.permission_test
```

---

## Next Steps After Deployment

Now that your key rotation system is deployed:

1. **Schedule First Rotation**: Mark calendar for next quarterly rotation date
2. **Create Jira Tickets**: Auto-schedule recurring tasks for rotation owners
3. **Configure Slack Alerts**: Set up automated notifications 30/7/1 days before due dates
4. **Document Current State**: Fill in audit log with baseline rotation history
5. **Conduct Mock Drill**: Practice emergency rotation procedures
6. **Celebrate Success!** 🎉

---

## Support Resources

- **Implementation Questions**: Open issue in this repository or contact security-team@company.com
- **Emergency Assistance**: Activate incident response playbook, call +1-XXX-XXX-XXXX
- **Training Requests**: Email security-training@company.com for scheduled sessions
- **Documentation Updates**: Submit PR against this guide with suggested improvements

---

## Document Metadata

**Created**: July 21, 2026  
**Author**: Security Operations Team  
**Review Cycle**: Quarterly  
**Next Review**: October 21, 2026  
**Distribution**: Engineering leadership, DevOps team, Security personnel

---

**Deployment Complete! Your organization now has enterprise-grade security key rotation capabilities.** 🔐

Remember: Security is continuous improvement. Regular testing, training, and updating will keep your system resilient against emerging threats.
