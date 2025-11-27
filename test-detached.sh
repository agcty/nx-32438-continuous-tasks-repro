#!/bin/bash
#
# Test if detached process spawning causes orphans
#

cd "$(dirname "$0")"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "=========================================="
echo "Detached Process Test"
echo "=========================================="
echo ""
echo "Theory: If doppler/bunx spawn children with 'detached: true',"
echo "children get their own process group and Ctrl+C won't reach them."
echo ""

# Clean
pkill -9 -f "node server.js" 2>/dev/null || true
sleep 1

echo "Starting with detached-wrapper.js..."
echo ""

cd apps/main-app

# Run the detached wrapper in background
node ../../detached-wrapper.js server.js &
WRAPPER_PID=$!

sleep 2

echo ""
echo "Process tree:"
echo "  PID    PPID   PGID   COMMAND"
ps -eo pid,ppid,pgid,command | grep -E "(detached-wrapper|node server)" | grep -v grep | sed 's/^/  /'

echo ""
echo "Key observation:"
echo "  - If PGID differs between wrapper and server, Ctrl+C won't reach server"
echo ""

WRAPPER_PGID=$(ps -o pgid= -p $WRAPPER_PID 2>/dev/null | tr -d ' ')
echo "Wrapper PGID: $WRAPPER_PGID"

# Find server's PGID
SERVER_PID=$(ps -eo pid,command | grep "node server.js" | grep -v grep | awk '{print $1}')
if [ -n "$SERVER_PID" ]; then
    SERVER_PGID=$(ps -o pgid= -p $SERVER_PID 2>/dev/null | tr -d ' ')
    echo "Server PGID:  $SERVER_PGID"

    if [ "$WRAPPER_PGID" != "$SERVER_PGID" ]; then
        echo ""
        echo -e "${YELLOW}⚠ DIFFERENT PROCESS GROUPS!${NC}"
        echo "This explains orphaned processes - Ctrl+C goes to wrapper's group only."
    else
        echo ""
        echo -e "${GREEN}Same process group - Ctrl+C would reach both${NC}"
    fi
fi

echo ""
echo "Sending SIGINT to wrapper's process group (like Ctrl+C)..."
kill -INT -$WRAPPER_PGID 2>/dev/null

sleep 2

cd ../..

ORPHANS=$(ps aux | grep "node server.js" | grep -v grep | wc -l | tr -d ' ')
if [ "$ORPHANS" -gt 0 ]; then
    echo ""
    echo -e "${RED}❌ ORPHAN DETECTED!${NC}"
    echo ""
    echo "  PID    PPID   PGID   COMMAND"
    ps -eo pid,ppid,pgid,command | grep "node server.js" | grep -v grep | sed 's/^/  /'
    echo ""
    echo "Note: PPID=1 confirms orphan (adopted by init)"
    echo ""
    echo "This confirms: detached spawning causes orphans on Ctrl+C"

    # Cleanup
    pkill -9 -f "node server.js" 2>/dev/null || true
else
    echo ""
    echo -e "${GREEN}✓ No orphans${NC}"
fi
