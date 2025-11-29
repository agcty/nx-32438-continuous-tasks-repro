# Nx Issue #32438: Orphaned Processes & Cleanup Handler Issue

Minimal reproduction for two related issues:

1. **Original issue:** Orphaned child processes when stopping continuous tasks
2. **New issue (PR #33655):** Cleanup handlers never run because processes are killed too aggressively

## Quick Test: Cleanup Handler Issue (No Doppler Required)

This demonstrates that `onCleanup()` handlers never run with the new `killProcessTree`:

```bash
# 1. Install dependencies
bun install

# 2. Make sure no containers are running
./test.sh clean

# 3. Run nx dev (like in production)
bunx nx dev:simple frontend

# 4. Wait for all services to start (database, services, frontend)

# 5. Press Ctrl+C to stop

# 6. Check if cleanup ran
./test.sh check
```

**Expected:** Docker container stops (cleanup handler ran)
**Actual:** Docker container still running (cleanup handler never called)

This mirrors production where `nx dev frontend` starts all dependencies including the database.

The `apps/database/alchemy.run.ts` registers a cleanup handler:

```typescript
app.onCleanup(async () => {
  console.log("Cleanup handler called, stopping Docker...");
  execSync("docker compose down");  // <-- This never runs!
});
```

With the new `killProcessTree` in PR #33655, processes are terminated immediately without receiving SIGTERM, so cleanup handlers never execute.

---

## Prerequisites (for full orphan repro)

1. **Bun** - <https://bun.sh>
2. **Docker** - for the cleanup handler test
3. **Doppler CLI** - <https://docs.doppler.com/docs/install-cli> (only for orphan process test)

## Orphan Process Reproduction Steps

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
├── database/        # Docker postgres with cleanup handler (demonstrates cleanup issue)
├── frontend/        # React Router app (depends on service-a, service-b)
├── service-a/       # Simple alchemy app
└── service-b/       # Simple alchemy app

plugins/
└── nx-repro-plugin/ # Creates dev targets from alchemy.run.ts files
```

## Targets

- `dev` - Full production setup with doppler
- `dev:simple` - Without doppler (easier to test cleanup issue)
- `dev:safe` - With trap workaround (processes clean up properly)

## Environment

- Nx: 0.0.0-pr-33655-040845c (PR version with killProcessTree fix)
- Bun: 1.3.2
- Alchemy: 0.78.0
- macOS

## The Issue

PR #33655 introduces `killProcessTree` which:

1. Fixes orphaned processes by killing the entire process tree
2. But kills too aggressively - doesn't send SIGTERM first
3. Cleanup handlers (via `signal-exit`) never run

**Suggested fix:** Implement SIGTERM → wait(timeout) → SIGKILL pattern like systemd/Docker/Kubernetes.
