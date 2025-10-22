# Nx Continuous Tasks Bug Reproduction

This is a minimal reproduction of [Nx issue #32438](https://github.com/nrwl/nx/issues/32438) where continuous tasks with dependencies don't stop when the parent task is terminated.

## Key Finding

**The bug occurs when commands use wrapper scripts that spawn child processes!**

- ✅ Works: Direct commands like `node server.js`
- ❌ Fails: Wrapped commands like `wrapper.sh server.js` which spawns `node server.js` as a child

This explains why real-world setups using `doppler`, `bun`, or other wrappers experience this issue, while simple commands work fine.

## Setup

```bash
bun install
```

## Reproduce the Issue

1. Start the main app:

   ```bash
   bun nx dev main-app
   ```

2. Verify all services started (check logs for all 3 servers):

   - You should see `[service-a] Server starting on port 3001`
   - You should see `[service-b] Server starting on port 3002`
   - You should see `[main-app] Server starting on port 3000`

3. Open another terminal and check processes:

   ```bash
   ps aux | grep "node server.js"
   ```

   You should see 3 node processes (one for each service).

4. Stop Nx with Ctrl+C or press 'q' in the TUI

5. Check processes again:

   ```bash
   ps aux | grep "node server.js"
   ```

   **Expected:** No processes running  
   **Actual:** All 3 node processes still running (orphaned)

6. Manually kill orphaned processes:
   ```bash
   pkill -f "node server.js"
   ```

## Expected Behavior

When stopping `nx dev main-app`, all dependent continuous tasks (service-a:dev and service-b:dev) should also terminate, and their graceful shutdown handlers should execute.

## Actual Behavior

- Only the Nx orchestration process stops
- All 3 server processes remain running as orphaned processes
- Graceful shutdown handlers never execute
- Processes must be manually killed

## Environment

- Nx: 22.0.0-rc.0
- Node.js: Required (v18+)
- OS: Any Unix-like system (Linux, macOS)
- Package Manager: Bun 1.3.0

## How It Works

- `main-app` depends on both `service-a` and `service-b`
- All three use `wrapper.sh` which spawns `node server.js` as a child process
- This creates a process chain: `Nx → wrapper.sh → node server.js`
- Each server has graceful shutdown handlers for SIGINT/SIGTERM
- When you stop Nx, the termination signal reaches `wrapper.sh` but **not** the `node` child
- The `node` processes become orphaned and continue running

### Why It Happens

When Nx sends SIGTERM/SIGINT to stop tasks:
```
Nx → wrapper.sh (receives signal, exits)
      └─ node server.js (orphaned, keeps running!)
```

The wrapper process exits, but it doesn't propagate the signal to its children. This is the root cause of the bug.

## Workaround

The `trap` technique propagates signals to all child processes:

```bash
sh -c 'trap "kill 0" EXIT; node server.js'
```

This creates a process group and ensures all children receive the termination signal when the parent exits.

## Automated Test

Run the automated test script to verify the bug:

```bash
./test-bug.sh
```

This script will:

1. Clean up any existing processes
2. Start Nx with main-app
3. Verify all 3 services started
4. Stop Nx
5. Check if processes remain running
6. Report the results

Expected output if bug exists:

```
=========================================
❌ BUG REPRODUCED
   3 orphaned processes still running
=========================================
```

## Manual Verification

You can also verify manually:

```bash
# Start the services
bun nx dev main-app &
NX_PID=$!

# Wait for them to start
sleep 2

# Check initial state
echo "=== Processes before stopping ==="
ps aux | grep "node server.js" | grep -v grep | wc -l

# Stop Nx
kill $NX_PID
sleep 1

# Check final state
echo "=== Processes after stopping ==="
ps aux | grep "node server.js" | grep -v grep | wc -l

# Cleanup
pkill -f "node server.js"
```

Expected output if bug exists:

```
=== Processes before stopping ===
3
=== Processes after stopping ===
3  # <-- Should be 0 but is 3
```
