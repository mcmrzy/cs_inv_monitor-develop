#!/bin/bash

# ============================================================
# cs_inv_monitor - Production Deployment Script
# Target: jiuxiaoyw.online (Ubuntu)
# Usage: ./deploy-prod.sh [--clean] [--rebuild] [--help]
# ============================================================

set -e

# ---------- Configuration ----------
COMPOSE_FILE="docker-compose.prod.yml"
ENV_FILE=".env.prod"
GIT_REPO="https://your-git-repo/cs_inv_monitor.git"
BRANCH="main"

# ---------- Colors ----------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[INFO]${NC}  $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC}  $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step()  { echo -e "${BLUE}[STEP]${NC}  $1"; }

# ---------- Parse Arguments ----------
CLEAN=false
REBUILD=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --clean)   CLEAN=true; shift;;
        --rebuild) REBUILD=true; shift;;
        --help|-h)
            echo "Usage: $0 [options]"
            echo "  --clean    Stop and remove all containers before deploy"
            echo "  --rebuild  Force rebuild all images"
            echo "  --help     Show this help"
            exit 0
            ;;
        *) log_error "Unknown option: $1"; exit 1;;
    esac
done

# ============================================================
# Step 1: Check Prerequisites
# ============================================================
log_step "Checking prerequisites..."

check_command() {
    if ! command -v "$1" &>/dev/null; then
        log_error "$1 is not installed. Please install it first."
        exit 1
    fi
    log_info "$1 is installed: $(command -v "$1")"
}

check_command docker
check_command git

if docker compose version &>/dev/null; then
    log_info "docker compose is available"
elif docker-compose version &>/dev/null; then
    log_info "docker-compose is available"
    alias docker-compose="docker compose"
else
    log_error "Neither 'docker compose' nor 'docker-compose' found."
    exit 1
fi

# ============================================================
# Step 2: Git Clone / Pull
# ============================================================
log_step "Fetching latest code..."

if [ -d ".git" ]; then
    log_info "Pulling latest changes..."
    git stash --include-untracked 2>/dev/null || true
    git pull origin "$BRANCH" || log_warn "Git pull failed, continuing with current code"
else
    log_info "Cloning repository..."
    git clone -b "$BRANCH" "$GIT_REPO" .
fi

# ============================================================
# Step 3: Prepare Environment Variables
# ============================================================
log_step "Preparing environment variables..."

cd "$(dirname "$0")"

if [ ! -f "$ENV_FILE" ]; then
    log_warn ".env.prod not found, creating from template..."
    cat > "$ENV_FILE" <<'ENV_TEMPLATE'
# Change these values before deploying!
DB_PASSWORD=CHANGE_ME_STRONG_PASSWORD
JWT_SECRET=CHANGE_ME_GENERATE_WITH_OPENSSL
INTERNAL_KEY=CHANGE_ME_INTERNAL_SECRET
EMAIL_PASS=CHANGE_ME_EMAIL_AUTH_CODE
ENV_TEMPLATE
    log_error "Please edit $ENV_FILE with real values and re-run."
    exit 1
fi

# Warn about placeholder values
if grep -q "CHANGE_ME" "$ENV_FILE"; then
    log_warn "Found CHANGE_ME placeholders in $ENV_FILE!"
    log_warn "Please replace them with real values before deploying."
    read -p "Continue anyway? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Aborted."
        exit 0
    fi
fi

# ============================================================
# Step 4: Clean (optional)
# ============================================================
if [ "$CLEAN" = true ]; then
    log_step "Cleaning up old containers..."
    docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" down --remove-orphans
    log_info "Old containers removed."
fi

# ============================================================
# Step 5: Build and Start Services
# ============================================================
log_step "Building and starting services..."

BUILD_ARGS=""
if [ "$REBUILD" = true ]; then
    BUILD_ARGS="--build"
fi

docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" up -d $BUILD_ARGS

log_info "Services started."

# ============================================================
# Step 6: Database Migration
# ============================================================
log_step "Waiting for PostgreSQL to be ready..."

MAX_WAIT=60
WAITED=0
while ! docker exec inv-postgres pg_isready -U postgres -d inv_mqtt &>/dev/null; do
    if [ $WAITED -ge $MAX_WAIT ]; then
        log_error "PostgreSQL is not ready after ${MAX_WAIT}s"
        docker logs inv-postgres --tail 20
        exit 1
    fi
    sleep 2
    WAITED=$((WAITED + 2))
done

log_info "PostgreSQL is ready."

# Run migration if the schema hasn't been applied yet
log_info "Checking if migration is needed..."
MIGRATION_CHECK=$(docker exec inv-postgres psql -U postgres -d inv_mqtt -t -c \
    "SELECT COUNT(*) FROM information_schema.tables WHERE table_name='devices';" 2>/dev/null || echo "0")

if [ "$(echo $MIGRATION_CHECK | tr -d ' ')" = "0" ]; then
    log_info "Running database initialization..."
    docker exec -i inv-postgres psql -U postgres -d inv_mqtt < ../database/schema.sql
    log_info "Schema initialized."
else
    log_info "Database schema already exists, skipping migration."
fi

# ============================================================
# Step 7: Health Checks
# ============================================================
log_step "Running health checks..."

check_service() {
    local name=$1
    local port=$2
    local health_path=${3:-"/health"}

    echo -n "  Checking ${name} (port ${port})... "
    local retries=10
    local delay=3

    for i in $(seq 1 $retries); do
        if curl -sf "http://localhost:${port}${health_path}" &>/dev/null; then
            echo -e "${GREEN}OK${NC}"
            return 0
        fi
        sleep $delay
    done

    echo -e "${RED}FAILED${NC}"
    log_warn "Service ${name} health check failed (port ${port})"
    return 1
}

FAILED=0

check_service "inv-api-server"    "18080" || FAILED=$((FAILED + 1))
check_service "inv-device-server" "8081"  || FAILED=$((FAILED + 1))
check_service "api-gateway"       "8080"  || FAILED=$((FAILED + 1))
check_service "inv-admin-frontend" "3000" "" || FAILED=$((FAILED + 1))

# Check PostgreSQL and Redis
echo -n "  Checking postgres (port 5432)... "
if docker exec inv-postgres pg_isready -U postgres &>/dev/null; then
    echo -e "${GREEN}OK${NC}"
else
    echo -e "${RED}FAILED${NC}"
    FAILED=$((FAILED + 1))
fi

echo -n "  Checking redis (port 6379)... "
if docker exec inv-redis redis-cli ping &>/dev/null; then
    echo -e "${GREEN}OK${NC}"
else
    echo -e "${RED}FAILED${NC}"
    FAILED=$((FAILED + 1))
fi

# ============================================================
# Step 8: Print Status
# ============================================================
echo ""
echo "============================================================"
log_info "Deployment Summary"
echo "============================================================"
echo ""
docker compose -f "$COMPOSE_FILE" --env-file "$ENV_FILE" ps

echo ""
echo "============================================================"
echo " Service Access Points"
echo "============================================================"
echo "  API Gateway:      http://jiuxiaoyw.online:8080"
echo "  API Server:       http://jiuxiaoyw.online:18080"
echo "  Device Server:    http://jiuxiaoyw.online:8081"
echo "  Admin Frontend:   http://jiuxiaoyw.online:3000"
echo "  PostgreSQL:       localhost:5432"
echo "  Redis:            localhost:6379"
echo ""

if [ $FAILED -gt 0 ]; then
    log_warn "${FAILED} service(s) failed health checks."
    log_warn "Run 'docker compose -f $COMPOSE_FILE logs' for details."
    exit 1
else
    log_info "All services are healthy!"
    log_info "Deployment complete!"
fi
