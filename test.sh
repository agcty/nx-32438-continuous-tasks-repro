#!/bin/bash
#
# Helper script to check for and clean up orphaned processes
#

cd "$(dirname "$0")"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BOLD='\033[1m'
NC='\033[0m'

case "$1" in
    check)
        COUNT=$(ps aux | grep -E "bun.*--watch.*alchemy" | grep -v grep | wc -l | tr -d ' ')
        if [ "$COUNT" -gt 0 ]; then
            echo -e "${RED}${BOLD}Found $COUNT orphaned processes:${NC}"
            echo ""
            echo -e "  ${BOLD}PID    PPID   PGID   COMMAND${NC}"
            ps -eo pid,ppid,pgid,command | grep -E "bun.*--watch.*alchemy" | grep -v grep | head -10 | while read pid ppid pgid cmd; do
                if [ "$ppid" = "1" ]; then
                    echo -e "  ${RED}$pid  $ppid     $pgid   $(echo "$cmd" | cut -c1-60)${NC}  ${YELLOW}← PPID=1 (orphaned!)${NC}"
                else
                    echo "  $pid  $ppid   $pgid   $(echo "$cmd" | cut -c1-60)"
                fi
            done
            echo ""

            # Check if PGIDs are different (the key indicator)
            PGIDS=$(ps -eo pgid,command | grep -E "bun.*--watch.*alchemy" | grep -v grep | awk '{print $1}' | sort -u | wc -l | tr -d ' ')
            if [ "$PGIDS" -gt 1 ]; then
                echo -e "${YELLOW}Note: Processes are in $PGIDS different process groups (PGIDs).${NC}"
                echo -e "${YELLOW}This is why Ctrl+C didn't reach them - it only signals the foreground group.${NC}"
                echo ""
            fi

            echo "Run './test.sh clean' to kill them."
        else
            echo -e "${GREEN}No orphaned processes${NC}"
        fi
        ;;

    tree)
        echo -e "${BOLD}Process tree for alchemy/bun processes:${NC}"
        echo ""
        # Show the full process tree including nx, doppler, bunx, bun
        echo -e "  ${BOLD}PID    PPID   PGID   COMMAND${NC}"
        ps -eo pid,ppid,pgid,command | grep -E "(nx|doppler|bunx|bun.*alchemy)" | grep -v grep | while read pid ppid pgid cmd; do
            echo "  $pid  $ppid   $pgid   $(echo "$cmd" | cut -c1-70)"
        done
        echo ""
        echo -e "${YELLOW}Look for different PGID values - these processes won't receive Ctrl+C${NC}"
        ;;

    clean)
        pkill -9 -f "bun.*--watch.*alchemy" 2>/dev/null || true
        pkill -9 -f "bunx alchemy" 2>/dev/null || true
        echo "Cleaned up."
        ;;

    *)
        echo "Usage: ./test.sh <command>"
        echo ""
        echo "Commands:"
        echo "  check  - Check for orphaned 'bun --watch' processes (run after Ctrl+C)"
        echo "  tree   - Show process tree while running (run in another terminal)"
        echo "  clean  - Kill all orphaned processes"
        ;;
esac
