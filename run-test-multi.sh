#!/bin/bash
# Test script: run dev:simple for frontend (depends on service-a + service-b)
# This is the actual reproduction scenario with 3 concurrent processes
set -e

LOGFILE="/tmp/nx-test-multi-output.log"
REPRO_DIR="/tmp/nx-investigation/repro"

cd "$REPRO_DIR"

echo "=== Starting NX frontend:dev:simple (depends on service-a + service-b) ==="
NX_DAEMON=false npx nx run frontend:dev:simple > "$LOGFILE" 2>&1 &
NX_PID=$!
echo "NX PID: $NX_PID"

# Wait for both services to start
echo "Waiting for services to start..."
BOTH_UP=false
for i in $(seq 1 45); do
  sleep 1
  PORT_3001=$(lsof -i :3001 2>/dev/null | grep -c LISTEN || true)
  PORT_3002=$(lsof -i :3002 2>/dev/null | grep -c LISTEN || true)

  if [ "$PORT_3001" -gt 0 ] && [ "$PORT_3002" -gt 0 ]; then
    echo "Both services are listening after ${i}s (service-a:3001, service-b:3002)"
    BOTH_UP=true
    break
  fi

  if ! kill -0 $NX_PID 2>/dev/null; then
    echo "NX process died prematurely!"
    cat "$LOGFILE"
    exit 1
  fi

  STATUS=""
  [ "$PORT_3001" -gt 0 ] && STATUS="service-a:UP" || STATUS="service-a:waiting"
  [ "$PORT_3002" -gt 0 ] && STATUS="$STATUS, service-b:UP" || STATUS="$STATUS, service-b:waiting"
  echo "  ${i}s - $STATUS"
done

if [ "$BOTH_UP" != "true" ]; then
  echo "ERROR: Services didn't start in time"
  cat "$LOGFILE"
  kill -9 $NX_PID 2>/dev/null
  pkill -9 -f "alchemy" 2>/dev/null
  exit 1
fi

# Let them stabilize a moment
sleep 2

echo ""
echo "=== All alchemy processes before SIGINT ==="
pgrep -af "alchemy" 2>/dev/null || echo "none"

echo ""
echo "=== All bun processes before SIGINT ==="
pgrep -af "bun.*watch.*alchemy" 2>/dev/null || echo "none"

echo ""
echo "=== Sending SIGINT to NX PID $NX_PID ==="
kill -INT $NX_PID

echo "Waiting for graceful shutdown (up to 15s)..."
for i in $(seq 1 15); do
  sleep 1
  if ! kill -0 $NX_PID 2>/dev/null; then
    echo "NX process exited after ${i}s"
    break
  fi
  echo "  still alive... ${i}s"
done

# Give extra time for child process cleanup
sleep 3

echo ""
echo "=== NX Output (last 40 lines) ==="
tail -40 "$LOGFILE"

echo ""
echo "=== Checking for orphaned alchemy processes ==="
ORPHANS=$(pgrep -af "alchemy" 2>/dev/null | grep -v "run-test" || true)
if [ -n "$ORPHANS" ]; then
  echo "FAIL: Orphaned alchemy processes found!"
  echo "$ORPHANS"
  pkill -9 -f "alchemy" 2>/dev/null
  exit 1
else
  echo "PASS: No orphaned alchemy processes"
fi

echo ""
echo "=== Checking for orphaned bun processes ==="
BUN_ORPHANS=$(pgrep -af "bun.*watch.*alchemy" 2>/dev/null || true)
if [ -n "$BUN_ORPHANS" ]; then
  echo "FAIL: Orphaned bun processes found!"
  echo "$BUN_ORPHANS"
  pkill -9 -f "bun.*watch.*alchemy" 2>/dev/null
  exit 1
else
  echo "PASS: No orphaned bun processes"
fi

echo ""
echo "=== Checking ports 3001 and 3002 ==="
PORT_CHECK=0
if lsof -i :3001 2>/dev/null | grep -q LISTEN; then
  echo "FAIL: Port 3001 still in use!"
  lsof -i :3001
  PORT_CHECK=1
else
  echo "PASS: Port 3001 is free"
fi
if lsof -i :3002 2>/dev/null | grep -q LISTEN; then
  echo "FAIL: Port 3002 still in use!"
  lsof -i :3002
  PORT_CHECK=1
else
  echo "PASS: Port 3002 is free"
fi

if [ "$PORT_CHECK" -eq 1 ]; then
  exit 1
fi

echo ""
echo "=== ALL TESTS PASSED ==="
echo "Multi-service graceful shutdown works correctly!"
echo "No orphaned processes, all ports freed."
