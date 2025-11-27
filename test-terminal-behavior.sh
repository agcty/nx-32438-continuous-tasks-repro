#!/bin/bash
#
# Test terminal behavior with Ctrl+C
# This helps diagnose WHY orphans might occur
#

cd "$(dirname "$0")"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "=========================================="
echo "Terminal Signal Behavior Diagnostic"
echo "=========================================="
echo ""

# Clean up first
pkill -9 -f "node server.js" 2>/dev/null || true
sleep 1

echo "Starting: bun nx dev main-app"
echo "Process hierarchy will be shown after 5 seconds..."
echo ""

# Start nx in background so we can inspect it
bun nx dev main-app &
NX_PID=$!

sleep 5

echo ""
echo "=========================================="
echo "Process Tree (before Ctrl+C)"
echo "=========================================="
echo ""
echo "  PID    PPID   PGID   SID    COMMAND"
echo "  ----   ----   ----   ----   -------"

# Show the process tree with PGID and SID
ps -eo pid,ppid,pgid,sess,command | grep -E "(bun|node|wrapper)" | grep -v grep | while read line; do
    echo "  $line"
done

echo ""
echo "Legend:"
echo "  - PGID = Process Group ID (Ctrl+C sends signal to all processes with same PGID)"
echo "  - SID  = Session ID"
echo ""

NX_PGID=$(ps -o pgid= -p $NX_PID 2>/dev/null | tr -d ' ')
echo "Nx process PGID: $NX_PGID"
echo ""

# Count processes in the same PGID
SAME_PGID_COUNT=$(ps -eo pgid,command | grep "^[[:space:]]*$NX_PGID" | wc -l | tr -d ' ')
echo "Processes in same process group: $SAME_PGID_COUNT"
echo ""

echo "=========================================="
echo "Signal Delivery Test"
echo "=========================================="
echo ""
echo "Sending SIGINT to process group -$NX_PGID (simulates Ctrl+C)..."
echo ""

# Send SIGINT to the process group (like Ctrl+C does)
kill -INT -$NX_PGID 2>/dev/null

sleep 3

echo ""
echo "=========================================="
echo "Process Tree (after SIGINT to group)"
echo "=========================================="
echo ""

REMAINING=$(ps aux | grep -E "(node server|wrapper)" | grep -v grep | wc -l | tr -d ' ')

if [ "$REMAINING" -gt 0 ]; then
    echo -e "${RED}Found $REMAINING orphaned processes:${NC}"
    echo ""
    echo "  PID    PPID   PGID   COMMAND"
    ps -eo pid,ppid,pgid,command | grep -E "(node server|wrapper)" | grep -v grep | sed 's/^/  /'
    echo ""
    echo "Note: PPID=1 means process was orphaned (parent died)"
    echo ""
    echo "Cleaning up..."
    pkill -9 -f "node server.js" 2>/dev/null || true
else
    echo -e "${GREEN}✓ All processes terminated correctly${NC}"
fi

echo ""
echo "=========================================="
echo "Analysis"
echo "=========================================="
echo ""

if [ "$REMAINING" -gt 0 ]; then
    echo "DIAGNOSIS: Orphans occurred even with process group signal!"
    echo ""
    echo "This means the issue is NOT just about tree-kill."
    echo "Possible causes:"
    echo "  1. Child processes in different process groups"
    echo "  2. Signal handlers in intermediate processes (wrapper/bun)"
    echo "  3. Race condition in process startup"
else
    echo "Process group signal worked correctly."
    echo ""
    echo "If you see orphans with Ctrl+C in your terminal, the issue might be:"
    echo "  1. Your terminal doesn't send SIGINT to the process group"
    echo "  2. Nx creates processes in separate process groups"
    echo "  3. Some intermediate process changes the PGID"
fi
