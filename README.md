# Nx Continuous Tasks - Orphaned Processes

**Minimal reproduction for [Nx issue #32438](https://github.com/nrwl/nx/issues/32438)**

## Quick Reproduction

```bash
# Setup
bun install

# Run multiple dependent continuous tasks
bun nx dev:doppler frontend

# Wait for all 3 servers to start, then press Ctrl+C

# Check for orphaned processes
./test.sh check

# Expected: 3 orphaned "bun --watch" processes
# Clean up:
./test.sh clean
```

## What This Reproduces

When running **multiple dependent continuous tasks** with `bunx alchemy dev` (which uses `bun --watch`), pressing Ctrl+C leaves orphaned child processes.

**Process chain:**
```
Nx → doppler → bunx → bun --watch → application
```

**Why it happens:**

Each `bun --watch` process ends up in a **different process group (PGID)**:

```
PID    PPID   PGID   COMMAND
87641  87483  87450  bun --watch service-b/alchemy.run.ts
87617  87482  87452  bun --watch service-a/alchemy.run.ts
87643  87484  87455  bun --watch frontend/alchemy.run.ts
```

When Ctrl+C sends SIGINT to the foreground process group, only the parent Nx process receives it. The child processes in separate groups are never signaled and become orphaned.

## Available Targets

| Target | Command | Triggers Orphans? |
|--------|---------|-------------------|
| `dev:doppler` | `doppler → bunx alchemy` | **YES** (with dependencies) |
| `dev:real` | `bunx alchemy dev` | Maybe (with dependencies) |
| `dev:doppler:safe` | With `wrapWithTrap` workaround | No |
| `dev:safe` | With `wrapWithTrap` workaround | No |

## Our Workaround

We wrap commands with signal forwarding to the **process group**:

```typescript
function wrapWithTrap(command: string): string {
  return `sh -c '${command} & PID=$!; trap "kill -TERM -$PID ..." EXIT TERM INT; wait $PID'`
}
```

Key: `kill -TERM -$PID` (negative PID) sends signal to the **entire process group**.

Test it:
```bash
bun nx dev:doppler:safe frontend
# Press Ctrl+C
./test.sh check  # Should show: ✓ No orphaned processes
```

## Project Structure

```
apps/
├── frontend/           # React Router app (alchemy + vite + workerd)
│   └── alchemy.run.ts
├── service-a/          # Simple alchemy app (HTTP server)
│   └── alchemy.run.ts
└── service-b/          # Simple alchemy app (HTTP server)
    └── alchemy.run.ts

plugins/
└── nx-repro-plugin/    # Infers targets from alchemy.run.ts files
```

## Dependencies

When running `nx dev:doppler frontend`, Nx starts:
1. `service-a:dev:doppler`
2. `service-b:dev:doppler`
3. `frontend:dev:doppler` (depends on above)

This multi-task scenario is required to trigger the orphan issue.

## Environment

- Nx: 22.1.2
- Bun: 1.3.2
- Alchemy: 0.78.0
- macOS (tested on Darwin)

## Root Cause Analysis

The issue is that child processes created by `bunx` / `bun --watch` end up in different process groups than the parent Nx process. Possible causes:

1. `bun` may spawn children with `detached: true` or use `setsid`
2. The multiple layers of indirection (doppler → bunx → bun) compound the issue
3. Nx's `tree-kill` uses PPID-based lookup which fails when process groups differ

**Suggested fix:** Use process group signals (`kill -TERM -$PGID`) instead of `tree-kill`'s PPID-based approach for continuous tasks.
