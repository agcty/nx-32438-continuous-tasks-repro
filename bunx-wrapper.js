#!/usr/bin/env node
/**
 * A JavaScript wrapper that simulates how bunx/doppler might spawn processes.
 *
 * This tests whether Node.js child_process creates different process groups.
 */

const { spawn } = require('child_process');
const path = require('path');

const serverPath = process.argv[2] || 'server.js';
const fullPath = path.resolve(process.cwd(), serverPath);

console.log(`[bunx-wrapper] Starting: node ${fullPath}`);
console.log(`[bunx-wrapper] My PID: ${process.pid}, PGID: ${process.getgid ? process.getgid() : 'N/A'}`);

// Spawn child process - this is how bunx/bun might do it
const child = spawn('node', [fullPath], {
  stdio: 'inherit',
  // Try different options that might affect process groups:
  // detached: false,  // Default - child is in same process group
  // detached: true,   // Child gets its own process group
});

console.log(`[bunx-wrapper] Child PID: ${child.pid}`);

// Forward signals to child
process.on('SIGINT', () => {
  console.log(`[bunx-wrapper] Received SIGINT, forwarding to child...`);
  child.kill('SIGINT');
});

process.on('SIGTERM', () => {
  console.log(`[bunx-wrapper] Received SIGTERM, forwarding to child...`);
  child.kill('SIGTERM');
});

child.on('exit', (code) => {
  console.log(`[bunx-wrapper] Child exited with code ${code}`);
  process.exit(code || 0);
});
