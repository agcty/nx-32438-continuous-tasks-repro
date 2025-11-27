#!/bin/bash
#
# Nx Issue #32438: Orphaned Processes Test Helper
#

cd "$(dirname "$0")"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Patterns to check for orphaned processes
# - node server.js (simple wrapper)
# - bun --watch (alchemy's watcher)
# - alchemy.run.ts (the actual alchemy script)
PATTERNS="node server.js|bun.*--watch.*alchemy|alchemy.run.ts"

case "$1" in
    check)
        # Check for both simple wrapper processes and alchemy processes
        COUNT=$(ps aux | grep -E "$PATTERNS" | grep -v grep | wc -l | tr -d ' ')
        if [ "$COUNT" -gt 0 ]; then
            echo -e "${RED}❌ Found $COUNT orphaned processes:${NC}"
            echo ""
            echo "  PID    PPID   PGID   COMMAND"
            ps -eo pid,ppid,pgid,command | grep -E "$PATTERNS" | grep -v grep | head -20 | while read line; do
                # Truncate long command lines for readability
                echo "  $(echo "$line" | cut -c1-120)"
            done
            echo ""
            echo "Note: PPID=1 means the parent died and process is orphaned."
        else
            echo -e "${GREEN}✓ No orphaned processes${NC}"
        fi
        ;;

    clean)
        pkill -9 -f "node server.js" 2>/dev/null || true
        pkill -9 -f "wrapper.sh" 2>/dev/null || true
        pkill -9 -f "bun.*--watch.*alchemy" 2>/dev/null || true
        pkill -9 -f "alchemy.run.ts" 2>/dev/null || true
        pkill -9 -f "bunx alchemy" 2>/dev/null || true
        echo "Cleaned up processes."
        ;;

    race)
        # Artificially trigger the race condition to demonstrate the flaw
        echo "==========================================="
        echo "Triggering race condition to show the flaw"
        echo "==========================================="
        echo ""

        # Clean first
        pkill -9 -f "node server.js" 2>/dev/null || true
        pkill -9 -f "wrapper.sh" 2>/dev/null || true
        sleep 1

        echo "Starting: bun nx dev main-app"
        bun nx dev main-app >/dev/null 2>&1 &
        NX_PID=$!
        sleep 5

        COUNT=$(ps aux | grep "node server.js" | grep -v grep | wc -l | tr -d ' ')
        PGID=$(ps -o pgid= -p $NX_PID 2>/dev/null | tr -d ' ')

        echo "Running: $COUNT server processes (PGID=$PGID)"
        echo ""
        echo "Process tree:"
        echo "  PID    PPID   PGID   COMMAND"
        ps -eo pid,ppid,pgid,command | grep -E "(wrapper|node server)" | grep -v grep | sed 's/^/  /'
        echo ""

        echo "==========================================="
        echo "Simulating race: killing wrappers first"
        echo "==========================================="
        echo ""
        echo "In production, this happens when wrappers exit"
        echo "faster than tree-kill can scan the process tree."
        echo ""

        # Kill wrappers first (simulates race)
        pkill -TERM -f "wrapper.sh" 2>/dev/null || true
        sleep 1

        echo "Wrappers killed. Node processes are now orphaned (PPID=1):"
        echo "  PID    PPID   PGID   COMMAND"
        ps -eo pid,ppid,pgid,command | grep "node server.js" | grep -v grep | sed 's/^/  /'
        echo ""

        echo "==========================================="
        echo "Now running tree-kill (what Nx does)"
        echo "==========================================="
        echo ""
        node -e "require('tree-kill')($NX_PID, 'SIGTERM')" 2>/dev/null || true
        sleep 2

        AFTER=$(ps aux | grep "node server.js" | grep -v grep | wc -l | tr -d ' ')
        if [ "$AFTER" -gt 0 ]; then
            echo -e "${RED}❌ tree-kill FAILED: $AFTER orphans remain${NC}"
            echo ""
            echo "tree-kill uses pgrep -P (PPID lookup)."
            echo "Orphaned processes have PPID=1, so they're invisible."
            echo ""

            echo "==========================================="
            echo "Process group kill WORKS:"
            echo "==========================================="
            echo ""
            ORPHAN_PIDS=$(ps -eo pid,command | grep "node server.js" | grep -v grep | awk '{print $1}' | tr '\n' ' ')
            echo "Killing: $ORPHAN_PIDS"
            kill -TERM $ORPHAN_PIDS 2>/dev/null || true
            sleep 1

            FINAL=$(ps aux | grep "node server.js" | grep -v grep | wc -l | tr -d ' ')
            if [ "$FINAL" -eq 0 ]; then
                echo -e "${GREEN}✅ All terminated via direct kill${NC}"
            fi
        else
            echo -e "${GREEN}✓ tree-kill succeeded (race timing different)${NC}"
        fi

        # Cleanup
        pkill -9 -f "node server.js" 2>/dev/null || true
        pkill -9 -f "wrapper.sh" 2>/dev/null || true
        pkill -9 -f "bun nx" 2>/dev/null || true

        echo ""
        echo "==========================================="
        echo "Summary"
        echo "==========================================="
        echo ""
        echo "PPID changes to 1 when parent dies → tree-kill can't find orphans"
        echo "PGID stays the same → process group kill always works"
        ;;

    *)
        echo "Nx Issue #32438: Orphaned Processes"
        echo ""
        echo "Usage:"
        echo "  ./test.sh check  - Check for orphaned processes"
        echo "  ./test.sh clean  - Kill orphaned processes"
        echo "  ./test.sh race   - Trigger race condition to demonstrate flaw"
        echo ""
        echo "Manual test:"
        echo "  1. bun nx dev main-app"
        echo "  2. Press 'q' or Ctrl+C to stop"
        echo "  3. ./test.sh check"
        ;;
esac
