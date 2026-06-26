#!/bin/bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}Stopping EatDa Load Test Environment...${NC}"

PROJECT_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$PROJECT_ROOT/load-test"

# Stop services
docker-compose -f docker-compose.load-test.yml down

echo -e "${GREEN}✓ All services stopped${NC}"

# Ask if user wants to remove volumes
read -p "Do you want to remove all data (volumes)? This will delete the database and mock data. (y/N) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    docker-compose -f docker-compose.load-test.yml down -v
    echo -e "${GREEN}✓ All volumes removed${NC}"
fi

echo -e "${GREEN}Environment cleanup completed${NC}"
