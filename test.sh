#!/bin/bash
#
# Helper script to test the cleanup handler issue
#

cd "$(dirname "$0")"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BOLD='\033[1m'
NC='\033[0m'

case "$1" in
    check)
        echo -e "${BOLD}Checking for orphaned processes...${NC}"
        COUNT=$(ps aux | grep -E "bun.*--watch.*alchemy" | grep -v grep | wc -l | tr -d ' ')
        if [ "$COUNT" -gt 0 ]; then
            echo -e "${RED}Found $COUNT orphaned bun processes${NC}"
            ps aux | grep -E "bun.*--watch.*alchemy" | grep -v grep
        else
            echo -e "${GREEN}No orphaned bun processes${NC}"
        fi

        echo ""
        echo -e "${BOLD}Checking for orphaned Docker containers...${NC}"
        if docker ps --format '{{.Names}}' | grep -q "nx-repro-postgres"; then
            echo -e "${RED}Docker container 'nx-repro-postgres' is still running!${NC}"
            echo -e "${YELLOW}This means onCleanup() was never called.${NC}"
            docker ps --filter "name=nx-repro-postgres"
        else
            echo -e "${GREEN}No orphaned Docker containers${NC}"
        fi
        ;;

    clean)
        echo "Cleaning up..."
        pkill -9 -f "bun.*--watch.*alchemy" 2>/dev/null || true
        pkill -9 -f "bunx alchemy" 2>/dev/null || true
        docker compose -f apps/database/docker-compose.yml down 2>/dev/null || true
        echo -e "${GREEN}Cleaned up${NC}"
        ;;

    *)
        echo "Usage: ./test.sh <command>"
        echo ""
        echo "Commands:"
        echo "  check  - Check for orphaned processes and Docker containers"
        echo "  clean  - Kill orphaned processes and stop Docker containers"
        echo ""
        echo "Test the cleanup handler issue:"
        echo "  1. ./test.sh clean"
        echo "  2. bunx nx dev:simple frontend"
        echo "  3. Wait for all services to start"
        echo "  4. Press Ctrl+C"
        echo "  5. ./test.sh check"
        echo ""
        echo "Expected: Docker container stops (cleanup ran)"
        echo "Actual:   Docker container still running (cleanup never called)"
        ;;
esac
