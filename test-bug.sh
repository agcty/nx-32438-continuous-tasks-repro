#!/bin/bash

# Test script to verify the Nx continuous tasks bug
# This script demonstrates that processes don't terminate when Nx stops

set -e

echo "========================================="
echo "Nx Continuous Tasks Bug Test"
echo "========================================="
echo ""

# Cleanup any existing processes
echo "1. Cleaning up any existing processes..."
pkill -f "node server.js" 2>/dev/null || true
sleep 1

# Start the services
echo "2. Starting Nx with main-app..."
bun nx dev main-app > /tmp/nx-output.log 2>&1 &
NX_PID=$!

# Wait for services to start
echo "3. Waiting for services to start..."
sleep 3

# Check initial state
echo "4. Checking processes before stopping..."
INITIAL_COUNT=$(ps aux | grep "node server.js" | grep -v grep | wc -l | tr -d ' ')
echo "   Found $INITIAL_COUNT processes (expected: 3)"

if [ "$INITIAL_COUNT" -ne 3 ]; then
    echo "   ERROR: Expected 3 processes but found $INITIAL_COUNT"
    echo "   Check /tmp/nx-output.log for details"
    kill $NX_PID 2>/dev/null || true
    pkill -f "node server.js" 2>/dev/null || true
    exit 1
fi

# Show the processes
echo ""
echo "   Active processes:"
ps aux | grep "node server.js" | grep -v grep

# Stop Nx
echo ""
echo "5. Stopping Nx (PID: $NX_PID)..."
kill $NX_PID 2>/dev/null || true
sleep 2

# Check final state
echo "6. Checking processes after stopping..."
FINAL_COUNT=$(ps aux | grep "node server.js" | grep -v grep | wc -l | tr -d ' ')
echo "   Found $FINAL_COUNT processes (expected: 0)"

echo ""
echo "========================================="
if [ "$FINAL_COUNT" -eq 0 ]; then
    echo "✅ BUG NOT REPRODUCED"
    echo "   All processes terminated correctly"
else
    echo "❌ BUG REPRODUCED"
    echo "   $FINAL_COUNT orphaned processes still running"
    echo ""
    echo "   Orphaned processes:"
    ps aux | grep "node server.js" | grep -v grep
fi
echo "========================================="

# Cleanup
echo ""
echo "7. Cleaning up orphaned processes..."
pkill -f "node server.js" 2>/dev/null || true
sleep 1

echo ""
echo "Done!"

