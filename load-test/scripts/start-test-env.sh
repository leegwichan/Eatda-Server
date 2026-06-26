#!/bin/bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}EatDa Load Test Environment Setup${NC}"
echo -e "${GREEN}========================================${NC}"

# Check if Docker is running
if ! docker info > /dev/null 2>&1; then
    echo -e "${RED}Error: Docker is not running. Please start Docker and try again.${NC}"
    exit 1
fi

# Check if docker-compose is installed
if ! command -v docker-compose &> /dev/null; then
    echo -e "${RED}Error: docker-compose is not installed.${NC}"
    exit 1
fi

# Build the application
echo -e "\n${YELLOW}Step 1: Building application...${NC}"
PROJECT_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$PROJECT_ROOT"
./gradlew clean build -x test
echo -e "${GREEN}✓ Build completed${NC}"

# Start services
echo -e "\n${YELLOW}Step 2: Starting Docker services...${NC}"
cd "$PROJECT_ROOT/load-test"
docker-compose -f "$PROJECT_ROOT/load-test/docker-compose.load-test.yml" up -d

# Wait for services to be healthy
echo -e "\n${YELLOW}Step 3: Waiting for services to be ready...${NC}"

# Wait for MySQL
echo -n "Waiting for MySQL..."
timeout=60
while [ $timeout -gt 0 ]; do
    if docker-compose -f "$PROJECT_ROOT/load-test/docker-compose.load-test.yml" exec -T mysql mysqladmin ping -h localhost -uroot -prootpassword &> /dev/null; then
        echo -e " ${GREEN}✓${NC}"
        break
    fi
    echo -n "."
    sleep 2
    timeout=$((timeout - 2))
done

if [ $timeout -le 0 ]; then
    echo -e " ${RED}✗ Timeout${NC}"
    exit 1
fi

# Wait for LocalStack
echo -n "Waiting for LocalStack..."
timeout=60
while [ $timeout -gt 0 ]; do
    if curl -s http://localhost:4566/_localstack/health | grep -q "running"; then
        echo -e " ${GREEN}✓${NC}"
        break
    fi
    echo -n "."
    sleep 2
    timeout=$((timeout - 2))
done

if [ $timeout -le 0 ]; then
    echo -e " ${RED}✗ Timeout${NC}"
    exit 1
fi

# Wait for Application
echo -n "Waiting for Application..."
timeout=120
while [ $timeout -gt 0 ]; do
    if curl -s http://localhost:8080/actuator/health | grep -q "UP"; then
        echo -e " ${GREEN}✓${NC}"
        break
    fi
    echo -n "."
    sleep 3
    timeout=$((timeout - 3))
done

if [ $timeout -le 0 ]; then
    echo -e " ${RED}✗ Timeout${NC}"
    echo -e "${YELLOW}Checking application logs:${NC}"
    docker-compose -f "$PROJECT_ROOT/load-test/docker-compose.load-test.yml" logs --tail=50 app
    exit 1
fi

# Check data
echo -e "\n${YELLOW}Step 4: Verifying Mock Data...${NC}"
member_count=$(docker-compose -f "$PROJECT_ROOT/load-test/docker-compose.load-test.yml" exec -T mysql mysql -ueatda -peatda123 -Nse "SELECT COUNT(*) FROM eatda.member;" 2>/dev/null || echo "0")
store_count=$(docker-compose -f "$PROJECT_ROOT/load-test/docker-compose.load-test.yml" exec -T mysql mysql -ueatda -peatda123 -Nse "SELECT COUNT(*) FROM eatda.store;" 2>/dev/null || echo "0")
cheer_count=$(docker-compose -f "$PROJECT_ROOT/load-test/docker-compose.load-test.yml" exec -T mysql mysql -ueatda -peatda123 -Nse "SELECT COUNT(*) FROM eatda.cheer;" 2>/dev/null || echo "0")

echo "  Members: $member_count"
echo "  Stores: $store_count"
echo "  Cheers: $cheer_count"

if [ "$member_count" -lt 100 ] || [ "$store_count" -lt 100 ]; then
    echo -e "${YELLOW}Warning: Mock data may not be fully loaded yet. Please wait...${NC}"
fi

# Summary
echo -e "\n${GREEN}========================================${NC}"
echo -e "${GREEN}Environment is ready!${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "\nAccess URLs:"
echo -e "  Application: ${GREEN}http://localhost:8080${NC}"
echo -e "  Swagger UI:  ${GREEN}http://localhost:8080/docs/swagger${NC}"
echo -e "  Grafana:     ${GREEN}http://localhost:3000${NC} (admin/admin)"
echo -e "  Prometheus:  ${GREEN}http://localhost:9090${NC}"
echo -e "  Pinpoint:    ${GREEN}http://localhost:8081${NC}"

echo -e "\nTo run load tests:"
echo -e "  ${YELLOW}docker-compose -f "$PROJECT_ROOT/load-test/docker-compose.load-test.yml" run --rm k6 run /scripts/test-scenario.js${NC}"

echo -e "\nTo view logs:"
echo -e "  ${YELLOW}docker-compose -f "$PROJECT_ROOT/load-test/docker-compose.load-test.yml" logs -f app${NC}"

echo -e "\nTo stop all services:"
echo -e "  ${YELLOW}docker-compose -f "$PROJECT_ROOT/load-test/docker-compose.load-test.yml" down${NC}"
