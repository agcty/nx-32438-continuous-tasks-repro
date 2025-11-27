#!/bin/bash
#
# Natural Race Condition Test
#
# This script helps identify WHY orphans might occur with Ctrl+C.
# The hypothesis: Process groups are different when running interactively.
#

cd "$(dirname "$0")"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "=========================================="
echo "Natural Race Condition Test"
echo "=========================================="
echo ""

# Clean first
pkill -9 -f "node server.js" 2>/dev/null || true
pkill -9 -f "wrapper.sh" 2>/dev/null || true
sleep 1

case "$1" in
    background)
        # Run in background and send signal to process group
        echo "Mode: BACKGROUND (simulates non-terminal usage)"
        echo ""
        echo "Starting Nx in background..."

        bun nx dev main-app &
        NX_PID=$!

        sleep 5

        echo ""
        echo "Process groups:"
        echo "  PID    PPID   PGID   COMMAND"
        ps -eo pid,ppid,pgid,command | grep -E "(node server|wrapper)" | grep -v grep | sed 's/^/  /'

        NX_PGID=$(ps -o pgid= -p $NX_PID 2>/dev/null | tr -d ' ')
        echo ""
        echo "Sending SIGINT to process group -$NX_PGID..."
        kill -INT -$NX_PGID 2>/dev/null

        sleep 3

        ORPHANS=$(ps aux | grep "node server.js" | grep -v grep | wc -l | tr -d ' ')
        if [ "$ORPHANS" -gt 0 ]; then
            echo -e "${RED}❌ $ORPHANS orphans remain!${NC}"
            ps -eo pid,ppid,pgid,command | grep "node server.js" | grep -v grep | sed 's/^/  /'
        else
            echo -e "${GREEN}✓ No orphans${NC}"
        fi
        ;;

    foreground)
        # Run in foreground - user must press Ctrl+C
        echo "Mode: FOREGROUND (simulates terminal usage)"
        echo ""
        echo -e "${YELLOW}Instructions:${NC}"
        echo "  1. Wait for servers to start"
        echo "  2. Press Ctrl+C when you see all 3 servers running"
        echo "  3. Watch the output for shutdown messages"
        echo ""
        echo "Then run: ./test-natural-race.sh check"
        echo ""
        echo "Starting Nx..."
        echo "=========================================="

        bun nx dev main-app

        # This will only run after Ctrl+C
        echo ""
        echo "=========================================="
        echo "Nx exited. Checking for orphans..."
        sleep 2

        ORPHANS=$(ps aux | grep "node server.js" | grep -v grep | wc -l | tr -d ' ')
        if [ "$ORPHANS" -gt 0 ]; then
            echo -e "${RED}❌ $ORPHANS orphans remain!${NC}"
            echo ""
            echo "  PID    PPID   PGID   COMMAND"
            ps -eo pid,ppid,pgid,command | grep "node server.js" | grep -v grep | sed 's/^/  /'
        else
            echo -e "${GREEN}✓ No orphans${NC}"
        fi
        ;;

    check)
        ORPHANS=$(ps aux | grep "node server.js" | grep -v grep | wc -l | tr -d ' ')
        if [ "$ORPHANS" -gt 0 ]; then
            echo -e "${RED}❌ $ORPHANS orphans found:${NC}"
            echo ""
            echo "  PID    PPID   PGID   COMMAND"
            ps -eo pid,ppid,pgid,command | grep "node server.js" | grep -v grep | sed 's/^/  /'
        else
            echo -e "${GREEN}✓ No orphans${NC}"
        fi
        ;;

    clean)
        pkill -9 -f "node server.js" 2>/dev/null || true
        pkill -9 -f "wrapper.sh" 2>/dev/null || true
        echo "Cleaned."
        ;;

    tui)
        # Run with TUI and quit with 'q'
        echo "Mode: TUI (press 'q' to quit)"
        echo ""
        echo -e "${YELLOW}Instructions:${NC}"
        echo "  1. Wait for servers to start"
        echo "  2. Press 'q' when you see all 3 servers"
        echo "  3. Check for orphans afterward"
        echo ""
        echo "Starting Nx with TUI..."
        echo "=========================================="

        NX_TUI=true bun nx dev main-app

        echo ""
        echo "=========================================="
        echo "Nx exited. Checking for orphans..."
        sleep 2

        ORPHANS=$(ps aux | grep "node server.js" | grep -v grep | wc -l | tr -d ' ')
        if [ "$ORPHANS" -gt 0 ]; then
            echo -e "${RED}❌ $ORPHANS orphans remain!${NC}"
            echo ""
            echo "  PID    PPID   PGID   COMMAND"
            ps -eo pid,ppid,pgid,command | grep "node server.js" | grep -v grep | sed 's/^/  /'
        else
            echo -e "${GREEN}✓ No orphans${NC}"
        fi
        ;;

    *)
        echo "Usage: $0 <mode>"
        echo ""
        echo "Modes:"
        echo "  foreground  - Run Nx interactively (press Ctrl+C to stop)"
        echo "  background  - Run Nx in background (auto-sends SIGINT)"
        echo "  tui         - Run Nx with TUI (press 'q' to stop)"
        echo "  check       - Check for orphaned processes"
        echo "  clean       - Kill all orphaned processes"
        echo ""
        echo "Example workflow:"
        echo "  ./test-natural-race.sh foreground"
        echo "  # Press Ctrl+C when ready"
        echo "  ./test-natural-race.sh check"
        ;;
esac
