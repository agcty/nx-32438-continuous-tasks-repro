#!/bin/bash
# This wrapper script simulates the nested process spawning
# that causes the bug (similar to doppler → bun → node chain)

# Don't use exec - we want this wrapper to stay alive as a parent process
# This creates the process chain: wrapper.sh → node server.js
node "$@"

