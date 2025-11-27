#!/bin/bash
#
# Simulates wrapper tools like doppler, bunx, or shell scripts.
#
# When this wrapper receives SIGTERM:
# 1. Bash's default behavior is to exit immediately
# 2. The child node process becomes orphaned (PPID → 1)
# 3. tree-kill can't find orphaned processes
#

node "$@" &
wait $!
