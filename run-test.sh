#!/bin/bash
# Test script: run dev:simple for service-a, send SIGINT, check for orphans
set -e

LOGFILE="/tmp/nx-test-output.log"
REPRO_DIR="/tmp/nx-investigation/repro"

cd "$REPRO_DIR"

echo "=== Starting NX service-a:dev:simple ==="
NX_DAEMON=false npx nx run service-a:dev:simple > "$LOGFILE" 2>&1 &
NX_PID=$!
echo "NX PID: $NX_PID"

# Wait for server to start
echo "Waiting for server to start..."
for i in $(seq 1 30); do
  sleep 1
  if lsof -i :3001 2>/dev/null | grep -q LISTEN; then
    echo "Server is listening on port 3001 after ${i}s"
    break
  fi
  if ! kill -0 $NX_PID 2>/dev/null; then
    echo "NX process died prematurely!"
    cat "$LOGFILE"
    exit 1
  fi
  echo "  waiting... ${i}s"
done

# Check if it's actually running
if ! lsof -i :3001 2>/dev/null | grep -q LISTEN; then
  echo "ERROR: Server never started on port 3001"
  cat "$LOGFILE"
  exit 1
fi

echo ""
echo "=== Process tree before SIGINT ==="
ps -o pid,ppid,pgid,command -p $(pgrep -f "alchemy.*service-a" 2>/dev/null | tr '\n' ',')$NX_PID 2>/dev/null || true

echo ""
echo "=== Sending SIGINT to NX PID $NX_PID ==="
kill -INT $NX_PID

echo "Waiting for graceful shutdown (up to 10s)..."
for i in $(seq 1 10); do
  sleep 1
  if ! kill -0 $NX_PID 2>/dev/null; then
    echo "NX process exited after ${i}s"
    break
  fi
  echo "  still alive... ${i}s"
done

# Extra wait for any stragglers
sleep 2

echo ""
echo "=== NX Output ==="
cat "$LOGFILE"

echo ""
echo "=== Checking for orphaned processes ==="
ORPHANS=$(pgrep -af "alchemy.*service-a" 2>/dev/null || true)
if [ -n "$ORPHANS" ]; then
  echo "FAIL: Orphaned processes found!"
  echo "$ORPHANS"
  # Clean up
  pkill -9 -f "alchemy.*service-a" 2>/dev/null
  exit 1
else
  echo "PASS: No orphaned processes"
fi

echo ""
echo "=== Checking port 3001 ==="
if lsof -i :3001 2>/dev/null | grep -q LISTEN; then
  echo "FAIL: Port 3001 still in use!"
  lsof -i :3001
  exit 1
else
  echo "PASS: Port 3001 is free"
fi

echo ""
echo "=== TEST PASSED ==="
