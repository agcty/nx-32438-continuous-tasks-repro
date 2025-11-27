/**
 * Nx plugin that mimics our production nx-alchemy-plugin
 *
 * Production setup:
 *   - Looks for alchemy.run.ts files
 *   - Wraps commands with doppler (secrets) and bunx
 *   - Command: doppler run -- bunx alchemy dev --app ${appName}
 *
 * This repro provides multiple targets to test different scenarios:
 *   - dev: Simple wrapper.sh (baseline, may not trigger issue)
 *   - dev:real: Real alchemy command (bunx alchemy dev) - NO workaround
 *   - dev:safe: Real alchemy with wrapWithTrap workaround
 */

const { existsSync, readFileSync } = require("fs");
const { dirname, join } = require("path");
const { createNodesFromFiles } = require("@nx/devkit");

/**
 * Production workaround: wrapWithTrap
 *
 * We use this in production because Nx's tree-kill doesn't reliably
 * terminate all child processes. This wrapper forwards signals to
 * the process GROUP (note the minus sign in kill -TERM -$PID).
 */
function wrapWithTrap(command) {
  const escaped = command.replace(/'/g, "'\\''");
  return `sh -c '${escaped} & PID=$!; trap "kill -TERM -$PID 2>/dev/null; for i in 1 2 3 4 5; do sleep 1; kill -0 $PID 2>/dev/null || exit 0; done; kill -9 -$PID 2>/dev/null" EXIT TERM INT; wait $PID'`;
}

/**
 * Extract app name from alchemy.run.ts
 * Matches: alchemy("app-name") or alchemy('app-name')
 */
function extractAppName(filePath, fallback) {
  try {
    const content = readFileSync(filePath, "utf-8");
    const match = content.match(/alchemy\s*\(\s*["']([^"']+)["']/);
    return match?.[1] || fallback;
  } catch {
    return fallback;
  }
}

async function createNodesInternal(configFilePath, _options, context) {
  const projectRoot = dirname(configFilePath);
  const alchemyFile = join(context.workspaceRoot, configFilePath);
  const appName = extractAppName(alchemyFile, projectRoot.split("/").pop());

  // Simple wrapper (baseline test)
  const simpleCommand = "../../wrapper.sh server.js";

  // Real alchemy command (like production)
  // bunx alchemy dev --adopt --app ${appName}
  const alchemyCommand = `bunx alchemy dev --adopt --app ${appName}`;

  // With Doppler (full production chain)
  // doppler run --project azav-cv --config dev -- bunx alchemy dev --adopt --app ${appName}
  const dopplerAlchemyCommand = `doppler run --project azav-cv --config \${DOPPLER_CONFIG:-dev} -- bunx alchemy dev --adopt --app ${appName}`;

  const targets = {
    // DEV: Simple wrapper - baseline test
    dev: {
      executor: "nx:run-commands",
      options: {
        command: simpleCommand,
        cwd: "{projectRoot}",
      },
      cache: false,
      continuous: true,
    },
    // DEV:REAL: Real alchemy command WITHOUT workaround
    // This should trigger orphaned processes on Ctrl+C
    "dev:real": {
      executor: "nx:run-commands",
      options: {
        command: alchemyCommand,
        cwd: "{projectRoot}",
      },
      cache: false,
      continuous: true,
    },
    // DEV:SAFE: Real alchemy WITH wrapWithTrap workaround
    // This should clean up properly
    "dev:safe": {
      executor: "nx:run-commands",
      options: {
        command: wrapWithTrap(alchemyCommand),
        cwd: "{projectRoot}",
      },
      cache: false,
      continuous: true,
    },
    // DEV:DOPPLER: Full production chain with Doppler
    // doppler → bunx → bun --watch → application
    "dev:doppler": {
      executor: "nx:run-commands",
      options: {
        command: dopplerAlchemyCommand,
        cwd: "{projectRoot}",
      },
      cache: false,
      continuous: true,
    },
    // DEV:DOPPLER:SAFE: Doppler + wrapWithTrap workaround
    "dev:doppler:safe": {
      executor: "nx:run-commands",
      options: {
        command: wrapWithTrap(dopplerAlchemyCommand),
        cwd: "{projectRoot}",
      },
      cache: false,
      continuous: true,
    },
  };

  // main-app depends on services (simple wrapper test)
  if (appName === "main-app") {
    targets.dev.dependsOn = ["service-a:dev", "service-b:dev"];
    targets["dev:real"].dependsOn = ["service-a:dev:real", "service-b:dev:real"];
    targets["dev:safe"].dependsOn = ["service-a:dev:safe", "service-b:dev:safe"];
    targets["dev:doppler"].dependsOn = ["service-a:dev:doppler", "service-b:dev:doppler"];
    targets["dev:doppler:safe"].dependsOn = ["service-a:dev:doppler:safe", "service-b:dev:doppler:safe"];
  }

  // frontend depends on service-a and service-b (simulates frontend → database/infra)
  // This is the most realistic test case - multiple continuous tasks with dependencies
  if (appName === "frontend") {
    targets["dev:real"].dependsOn = ["service-a:dev:real", "service-b:dev:real"];
    targets["dev:safe"].dependsOn = ["service-a:dev:safe", "service-b:dev:safe"];
    targets["dev:doppler"].dependsOn = ["service-a:dev:doppler", "service-b:dev:doppler"];
    targets["dev:doppler:safe"].dependsOn = ["service-a:dev:doppler:safe", "service-b:dev:doppler:safe"];
  }

  return {
    projects: {
      [projectRoot]: {
        root: projectRoot,
        targets,
      },
    },
  };
}

module.exports = {
  name: "nx-repro-plugin",
  createNodesV2: [
    "**/alchemy.run.ts",
    async (configFiles, options, context) => {
      return await createNodesFromFiles(
        (configFile, opts, ctx) => createNodesInternal(configFile, opts, ctx),
        configFiles,
        options,
        context
      );
    },
  ],
};
