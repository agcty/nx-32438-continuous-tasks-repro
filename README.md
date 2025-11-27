# Nx Issue #32438: Orphaned Processes Reproduction

Minimal reproduction for orphaned child processes when stopping continuous tasks with Ctrl+C.

## Prerequisites

1. **Bun** - <https://bun.sh>
2. **Doppler CLI** - <https://docs.doppler.com/docs/install-cli> (free account required)

> **Note for maintainer:** Unfortunately, Doppler is required to reproduce this issue. The orphaned processes only occur with this specific process chain. Doppler has a free tier - you can create a project called `azav-cv` with a `dev` config (the config can be empty, we just need Doppler's process wrapping behavior).

## Reproduction Steps

```bash
# 1. Install dependencies
bun install

# 2. Run the frontend (which depends on service-a and service-b)
bun nx dev frontend

# 3. Wait for all 3 apps to start (you'll see "Server starting on port..." messages)

# 4. Press Ctrl+C to stop

# 5. Check for orphaned processes
./test.sh check
```

**Expected result:** 3 orphaned `bun --watch` processes still running (PPID=1, indicating they've been re-parented to init).

## Verify the Workaround

```bash
# Clean up first
./test.sh clean

# Run with our workaround
bun nx dev:safe frontend

# Press Ctrl+C

./test.sh check
```

**Expected result:** No orphaned processes.

## What's Happening

### Process Chain

```text
Nx → doppler → bunx → bun --watch → application
```

### The Problem

When Ctrl+C is pressed, each `bun --watch` process ends up in a **different process group**:

```text
PID    PPID   PGID   COMMAND
87641  87483  87450  bun --watch service-b/alchemy.run.ts
87617  87482  87452  bun --watch service-a/alchemy.run.ts
87643  87484  87455  bun --watch frontend/alchemy.run.ts
```

Note the **different PGID values** (87450, 87452, 87455). Ctrl+C sends SIGINT to the **foreground process group only**. The child processes in separate groups never receive the signal and become orphaned.

### Analysis: Why Cleanup May Not Be Working

We looked at Nx's source ([`packages/nx/src/executors/run-commands/running-tasks.ts`](https://github.com/nrwl/nx/blob/22.1.2/packages/nx/src/executors/run-commands/running-tasks.ts)) to understand what might be happening. We found two SIGINT handlers that could be relevant:

**Lines 520-523** (`RunningNodeProcess.addListeners`):

```typescript
process.on('SIGINT', () => {
  this.childProcess.kill('SIGTERM');  // Node's built-in kill
  process.exit(signalToCode('SIGINT'));
});
```

**Lines 702-705** (`registerProcessListener`):

```typescript
process.on('SIGINT', () => {
  runningTask.kill('SIGTERM');  // Calls tree-kill
  process.exit(signalToCode('SIGINT'));  // Exits without awaiting
});
```

We believe the issue might be that:

1. The first handler uses Node's built-in `kill()` rather than tree-kill, OR
2. The second handler calls tree-kill but doesn't await it before `process.exit()`

Our hypothesis for what happens when Ctrl+C is pressed:

1. SIGINT reaches Nx (it's in the foreground process group)
2. Nx signals direct children but may not wait for tree-kill to complete
3. Nx exits immediately with `process.exit()`
4. Grandchildren in different process groups never get signaled
5. Grandchildren become orphans (PPID=1)

```text
After Ctrl+C:
PID    PPID   PGID   COMMAND
87641  1      87450  bun --watch service-b/alchemy.run.ts  ← PPID=1 = orphaned
87617  1      87452  bun --watch service-a/alchemy.run.ts  ← PPID=1 = orphaned
87643  1      87455  bun --watch frontend/alchemy.run.ts   ← PPID=1 = orphaned
```

### Our Workaround

We wrap commands with a trap that forwards signals to the **process group**:

```javascript
function wrapWithTrap(command) {
  return `sh -c '${command} & PID=$!; trap "kill -TERM -$PID ..." EXIT TERM INT; wait $PID'`;
}
```

Key: `kill -TERM -$PID` (negative PID) sends signal to the **entire process group**, not just one process.

### Why This Is an Nx Issue

While the different PGIDs are created by the process chain (doppler/bunx), Nx is responsible for:

1. **Orchestrating continuous tasks** - Nx runs multiple dependent services
2. **Ensuring clean shutdown** - Users expect Ctrl+C to stop everything
3. **This is a common pattern** - Secret managers (Doppler, Vault, aws-vault) and runtime wrappers (bunx, npx) are standard in modern dev environments

The workaround we use (trap + process group signaling) could be built into Nx's continuous task handling.

## Diagnostic Commands

```bash
# Check for orphaned processes (shows PPID=1)
./test.sh check

# Show full process tree while running (run in another terminal)
./test.sh tree

# Clean up orphaned processes
./test.sh clean
```

## Project Structure

```text
apps/
├── frontend/        # React Router app (depends on service-a, service-b)
├── service-a/       # Simple alchemy app
└── service-b/       # Simple alchemy app

plugins/
└── nx-repro-plugin/ # Creates dev targets from alchemy.run.ts files
```

## Environment

- Nx: 22.1.2
- Bun: 1.3.2
- Alchemy: 0.78.0
- macOS
