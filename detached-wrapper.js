#!/usr/bin/env node
/**
 * A wrapper that spawns child in DETACHED mode.
 *
 * When detached: true, the child gets its own process group (PGID = child PID).
 * This means Ctrl+C (which sends to foreground process group) won't reach it!
 *
 * This might be what's happening with doppler/bunx.
 */

const { spawn } = require('child_process');
const path = require('path');

const serverPath = process.argv[2] || 'server.js';
const fullPath = path.resolve(process.cwd(), serverPath);

console.log(`[detached-wrapper] Starting: node ${fullPath}`);
console.log(`[detached-wrapper] My PID: ${process.pid}`);

// Spawn child process in DETACHED mode - child gets its own process group
const child = spawn('node', [fullPath], {
  stdio: 'inherit',
  detached: true,  // THIS IS THE KEY - creates new process group
});

// Prevent the child from keeping parent alive
// child.unref();  // Uncomment to let parent exit without waiting

console.log(`[detached-wrapper] Child PID: ${child.pid} (in its own process group)`);

// NOTE: Without explicit signal forwarding, the child will be orphaned on Ctrl+C
// Because:
// 1. Ctrl+C sends SIGINT to foreground process group (this process)
// 2. Child is in different process group, doesn't receive signal
// 3. Parent exits, child becomes orphan (PPID -> 1)

// Uncomment below to fix with manual forwarding:
/*
process.on('SIGINT', () => {
  console.log(`[detached-wrapper] Forwarding SIGINT to child process group...`);
  process.kill(-child.pid, 'SIGINT');  // Note: -pid sends to process group
});

process.on('SIGTERM', () => {
  console.log(`[detached-wrapper] Forwarding SIGTERM to child process group...`);
  process.kill(-child.pid, 'SIGTERM');
});
*/

child.on('exit', (code) => {
  console.log(`[detached-wrapper] Child exited with code ${code}`);
  process.exit(code || 0);
});
