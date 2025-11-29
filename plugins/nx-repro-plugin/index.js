/**
 * Nx plugin that creates dev targets for alchemy.run.ts files
 *
 * This reproduces the production setup:
 *   doppler run -- bunx alchemy dev --app ${appName}
 *
 * Which creates this process chain:
 *   Nx → doppler → bunx → bun --watch → application
 */

const { readFileSync } = require("fs");
const { dirname, join } = require("path");
const { createNodesFromFiles } = require("@nx/devkit");

/**
 * Workaround for Nx issue #32438
 *
 * Wraps command to forward signals to the process GROUP.
 * Key: kill -TERM -$PID (negative) sends to entire process group.
 */
function wrapWithTrap(command) {
  const escaped = command.replace(/'/g, "'\\''");
  return `sh -c '${escaped} & PID=$!; trap "kill -TERM -$PID 2>/dev/null; for i in 1 2 3 4 5; do sleep 1; kill -0 $PID 2>/dev/null || exit 0; done; kill -9 -$PID 2>/dev/null" EXIT TERM INT; wait $PID'`;
}

/**
 * Extract app name from alchemy.run.ts
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

  // Production command chain: doppler → bunx → bun --watch
  const command = `doppler run --project nx-repro --config \${DOPPLER_CONFIG:-dev} -- bunx alchemy dev --adopt --app ${appName}`;

  // Simple command without doppler - for testing cleanup issue
  const simpleCommand = `bunx alchemy dev --adopt --app ${appName}`;

  const targets = {
    // DEV: Full production setup with doppler
    dev: {
      executor: "nx:run-commands",
      options: {
        command: command,
        cwd: "{projectRoot}",
      },
      cache: false,
      continuous: true,
    },
    // DEV:SIMPLE: Without doppler - easier to test cleanup issue
    "dev:simple": {
      executor: "nx:run-commands",
      options: {
        command: simpleCommand,
        cwd: "{projectRoot}",
      },
      cache: false,
      continuous: true,
    },
    // DEV:SAFE: With wrapWithTrap workaround - no orphans
    "dev:safe": {
      executor: "nx:run-commands",
      options: {
        command: wrapWithTrap(command),
        cwd: "{projectRoot}",
      },
      cache: false,
      continuous: true,
    },
  };

  // frontend depends on database, service-a, and service-b
  // This mirrors production: nx dev frontend → starts all dependencies
  if (appName === "frontend") {
    targets.dev.dependsOn = ["database:dev", "service-a:dev", "service-b:dev"];
    targets["dev:simple"].dependsOn = ["database:dev:simple", "service-a:dev:simple", "service-b:dev:simple"];
    targets["dev:safe"].dependsOn = ["database:dev:safe", "service-a:dev:safe", "service-b:dev:safe"];
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
