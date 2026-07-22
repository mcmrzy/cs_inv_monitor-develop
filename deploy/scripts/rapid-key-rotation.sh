#!/bin/bash

#===============================================================================
# EMERGENCY KEY ROTATION SCRIPT
#===============================================================================
# Purpose: Rapid rotation of all security-critical credentials in emergency
#          scenarios requiring sub-hour response time.
#
# Usage:   ./rapid-key-rotation.sh <key_type>
#          key_type options: jwt | smtp | redis | all
#
# Example: ./rapid-key-rotation.sh jwt    # Rotate only JWT secret
#          ./rapid-key-rotation.sh all    # Rotate ALL secrets (emergency)
#
# Prerequisites:
#   - Script must have execute permissions: chmod +x rapid-key-rotation.sh
#   - Must be run from project root directory (where deploy/ exists)
#   - SSH access with sudo privileges to production server
#   - Backup of current .env.prod file recommended
#
# Safety Features:
#   - Automatic backup before any changes
#   - Transactional updates (backup created before modification)
#   - Comprehensive logging for audit trail
#   - Verification steps after service restart
#
# Author: Security Team
# Version: 1.0
# Last Updated: 2026-07-21
#===============================================================================

set -euo pipefail  # Exit on error, undefined vars, and pipe failures

#-------------------------------------------------------------------------------
# Configuration Variables
#-------------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
ENV_FILE="${PROJECT_ROOT}/deploy/.env.prod"
BACKUP_DIR="${PROJECT_ROOT}/deploy/.backups"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOG_FILE="${PROJECT_ROOT}/logs/emergency_rotation_${TIMESTAMP}.log"

# Colors for terminal output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

#-------------------------------------------------------------------------------#
# Utility Functions                                                           #
#-------------------------------------------------------------------------------

log_info() {
    echo -e "${GREEN}[INFO]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

# Generate cryptographically secure random secret
generate_secret() {
    openssl rand -base64 32 | tr -d '=+/' | head -c 32
}

# Create backup of current environment file
create_backup() {
    local filename=$(basename "$1")
    log_info "Creating backup of $filename..."
    
    mkdir -p "$BACKUP_DIR"
    
    if [ -f "$1" ]; then
        cp "$1" "${BACKUP_DIR}/${filename}.pre_rotation.${TIMESTAMP}"
        log_info "Backup created: ${BACKUP_DIR}/${filename}.pre_rotation.${TIMESTAMP}"
        
        # Also keep immediate backup in deploy directory for quick rollback
        cp "$1" "${PROJECT_ROOT}/deploy/${filename}.old.${TIMESTAMP}"
        log_info "Quick rollback backup created: ${PROJECT_ROOT}/deploy/${filename}.old.${TIMESTAMP}"
    else
        log_error "File not found: $1"
        return 1
    fi
}

# Update environment variable safely using sed
update_env_var() {
    local var_name="$1"
    local new_value="$2"
    local env_file="$3"
    
    # Check if variable exists, if not append it
    if grep -q "^${var_name}=" "$env_file"; then
        sed -i "s/^${var_name}=.*$/${var_name}=${new_value}/" "$env_file"
    else
        echo "${var_name}=${new_value}" >> "$env_file"
    fi
    
    log_info "Updated $var_name in $env_file"
}

# Verify file integrity after update
verify_env_update() {
    local var_name="$1"
    local env_file="$2"
    
    if grep -q "^${var_name}=" "$env_file"; then
        local value=$(grep "^${var_name}=" "$env_file" | cut -d'=' -f2-)
        # Mask sensitive values in logs
        local masked_value=$(echo "$value" | sed 's/./*/g')
        log_info "$var_name updated successfully (value masked: ${masked_value:0:4}****)"
        return 0
    else
        log_error "$var_name not found in $env_file"
        return 1
    fi
}

# Restart Docker services gracefully
restart_services() {
    local services="$1"
    
    log_info "Restarting services: $services"
    
    # Check if docker-compose command exists
    if command -v docker-compose &> /dev/null; then
        docker-compose -f "${PROJECT_ROOT}/deploy/docker-compose.prod.yml" restart $services
    elif docker compose version &> /dev/null; then
        docker compose -f "${PROJECT_ROOT}/deploy/docker-compose.prod.yml" restart $services
    else
        log_error "docker-compose or 'docker compose' not found"
        return 1
    fi
    
    log_info "Services restarted. Waiting 30 seconds for stabilization..."
    sleep 30
}

# Verify service health after restart
verify_services_healthy() {
    local timeout=120
    local elapsed=0
    
    log_info "Verifying service health (timeout: ${timeout}s)..."
    
    while [ $elapsed -lt $timeout ]; do
        local healthy_count=0
        local total_count=0
        
        # Check inv-api-server health
        if curl -sf http://localhost:8080/api/v1/health > /dev/null 2>&1; then
            ((healthy_count++))
            log_info "inv-api-server is healthy"
        fi
        
        # Check api-gateway health
        if curl -sf http://localhost:8081/api/v1/health > /dev/null 2>&1; then
            ((healthy_count++))
            log_info "api-gateway is healthy"
        fi
        
        total_count=2
        
        if [ $healthy_count -eq $total_count ]; then
            log_info "All services healthy!"
            return 0
        fi
        
        ((elapsed+=10))
        log_info "Waiting for services... (${elapsed}s / ${timeout}s)"
        sleep 10
    done
    
    log_error "Service verification timed out after ${timeout} seconds"
    return 1
}

#-------------------------------------------------------------------------------
# Rotation Functions                                                            #
#-------------------------------------------------------------------------------

rotate_jwt_secret() {
    log_info "=== Starting JWT Secret Rotation ==="
    
    # Generate new secret
    local new_secret=$(generate_secret)
    log_info "Generated new JWT secret (length: ${#new_secret} characters)"
    
    # Update .env.prod
    update_env_var "JWT_SECRET" "$new_secret" "$ENV_FILE"
    
    # Verify update
    verify_env_update "JWT_SECRET" "$ENV_FILE" || exit 1
    
    # Restart services
    restart_services "inv-api-server api-gateway"
    
    log_info "JWT secret rotation completed successfully"
}

rotate_smtp_credentials() {
    log_info "=== Starting SMTP Credential Rotation ==="
    
    # Generate new email password
    local new_password=$(generate_secret)
    log_info "Generated new SMTP password (length: ${#new_password} characters)"
    
    # Update EMAIL_PASSWORD
    update_env_var "EMAIL_PASSWORD" "$new_password" "$ENV_FILE"
    
    # If EMAIL_USERNAME needs updating (optional)
    if [ -n "${ROTATE_EMAIL_USERNAME:-}" ]; then
        local new_username="email_user_${TIMESTAMP}"
        update_env_var "EMAIL_USERNAME" "$new_username" "$ENV_FILE"
        log_info "Updated EMAIL_USERNAME to $new_username"
    fi
    
    # Verify updates
    verify_env_update "EMAIL_PASSWORD" "$ENV_FILE" || exit 1
    
    # Note: Email tests should be done manually after rotation
    log_warn "Email delivery test REQUIRED after rotation:"
    log_warn "  curl -X POST https://your-domain.com/api/v1/test-email -d '{\"to\": \"admin@example.com\"}'"
    
    log_info "SMTP credential rotation completed"
}

rotate_redis_password() {
    log_info "=== Starting Redis Password Rotation ==="
    
    # Generate new password
    local new_password=$(generate_secret)
    log_info "Generated new Redis password (length: ${#new_password} characters)"
    
    # Update REDIS_PASSWORD
    update_env_var "REDIS_PASSWORD" "$new_password" "$ENV_FILE"
    
    # Also update redis-specific config if it exists
    if [ -f "${PROJECT_ROOT}/deploy/configs/redis.conf" ]; then
        log_warn "Manual Redis configuration update may be required:"
        log_warn "  Edit ${PROJECT_ROOT}/deploy/configs/redis.conf"
        log_warn "  Add 'requirepass ${new_password}' to Redis configuration"
    fi
    
    # Verify update
    verify_env_update "REDIS_PASSWORD" "$ENV_FILE" || exit 1
    
    # Warn about cache invalidation
    log_warn "Cache will be invalidated during next service restart"
    log_warn "API response times may increase temporarily during cache warm-up"
    
    log_info "Redis password rotation completed"
}

rotate_all_secrets() {
    log_info "=== EMERGENCY ROTATION: ALL SECRETS ==="
    log_warn "This will rotate JWT_SECRET, EMAIL_PASSWORD, and REDIS_PASSWORD simultaneously"
    
    # Confirm with user
    read -p "Continue with emergency rotation? (yes/no): " confirm
    if [ "$confirm" != "yes" ]; then
        log_info "Rotation cancelled by user"
        return 1
    fi
    
    # Execute all rotations
    rotate_jwt_secret
    rotate_smtp_credentials
    rotate_redis_password
    
    # Restart all affected services
    restart_services "inv-api-server api-gateway redis"
    
    log_info "ALL secrets rotated successfully"
    log_warn "WARNING: All active sessions will be terminated"
    log_warn "Plan user communication strategy immediately"
}

#-------------------------------------------------------------------------------
# Main Script Flow                                                              #
#-------------------------------------------------------------------------------

main() {
    local key_type="${1:-all}"
    
    # Validate input
    if [[ ! "$key_type" =~ ^(jwt|smtp|redis|all)$ ]]; then
        echo "Error: Invalid key type '$key_type'"
        echo "Usage: $0 <jwt|smtp|redis|all>"
        exit 1
    fi
    
    # Ensure log directory exists
    mkdir -p "$(dirname "$LOG_FILE")"
    
    # Log script execution start
    log_info "Emergency key rotation script started"
    log_info "Target key type: $key_type"
    log_info "Environment file: $ENV_FILE"
    
    # Validate environment file exists
    if [ ! -f "$ENV_FILE" ]; then
        log_error "Environment file not found: $ENV_FILE"
        log_info "Make sure you're running this script from the project root directory"
        exit 1
    fi
    
    # Create backup first
    create_backup "$ENV_FILE" || exit 1
    
    echo ""
    log_info "Starting rotation procedure..."
    echo ""
    
    # Execute requested rotation
    case $key_type in
        jwt)
            rotate_jwt_secret
            ;;
        smtp)
            rotate_smtp_credentials
            ;;
        redis)
            rotate_redis_password
            ;;
        all)
            rotate_all_secrets
            ;;
    esac
    
    echo ""
    log_info "=============================================="
    log_info "ROTATION COMPLETE"
    log_info "=============================================="
    echo ""
    
    # Post-rotation checklist
    cat << EOF
Next Steps:
1. ✓ Verify all services are healthy (check container status)
2. ✓ Test authentication flow end-to-end
3. ✓ Monitor error rates for the next 15 minutes
4. ✓ Send notification to users (if required)
5. ✓ Document rotation in audit log: docs/key_rotation_audit_log_template.csv
6. ✓ Archive old secrets securely for 30 days

Logs saved to: $LOG_FILE
Backups saved to: $BACKUP_DIR

EOF
    
    # Final verification
    if [ "$key_type" = "jwt" ] || [ "$key_type" = "all" ]; then
        log_info "Running final authentication verification..."
        if verify_services_healthy; then
            log_info "All systems operational"
        else
            log_warn "Some services may need manual intervention"
            log_info "Check logs: tail -f $(docker ps --format '{{.Names}}' | xargs -I {} docker logs {} --tail 50)"
        fi
    fi
    
    log_info "Script execution completed at $(date)"
}

# Execute main function
main "$@"
