#!/bin/bash
#
# Deep Wrapper - Simulates doppler → bunx → bun behavior
#
# The production chain:
#   doppler run -- bunx alchemy dev
#     → bunx spawns: bun /path/to/alchemy dev
#       → alchemy spawns: bun --watch alchemy.run.ts
#         → application runs
#
# Each layer might:
#   1. Create a new process group (setsid)
#   2. Not forward signals properly
#   3. Exit before children, leaving orphans
#

# Simulate doppler (layer 1)
# Doppler wraps commands to inject secrets
# It might not forward signals to children properly

exec_doppler() {
    # Simulating: doppler run -- <command>
    # Doppler might background the child and wait
    "$@" &
    local pid=$!
    wait $pid
}

# Simulate bunx (layer 2)
# bunx (bun's npx) spawns a new bun process
# It creates another layer of indirection

exec_bunx() {
    # Simulating: bunx <package> <args>
    # bunx spawns bun with the package
    "$@" &
    local pid=$!
    wait $pid
}

# This script chains them together
# doppler → bunx → actual command

if [ "$1" = "--depth" ]; then
    DEPTH=$2
    shift 2
    ACTUAL_CMD="$@"

    case $DEPTH in
        1)
            # Just one wrapper (like current repro)
            $ACTUAL_CMD &
            wait $!
            ;;
        2)
            # Two layers (doppler → command)
            exec_doppler $ACTUAL_CMD
            ;;
        3)
            # Three layers (doppler → bunx → command)
            exec_doppler bash -c "$(declare -f exec_bunx); exec_bunx $ACTUAL_CMD"
            ;;
        *)
            # Default: simple background
            $ACTUAL_CMD &
            wait $!
            ;;
    esac
else
    # Default behavior: match current wrapper.sh
    # But use exec to not create extra process
    node "$@" &
    wait $!
fi
