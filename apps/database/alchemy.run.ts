/**
 * Database app - demonstrates cleanup handler issue with Docker
 *
 * EXPECTED: When Nx stops, onCleanup runs → docker compose down → container stops
 * ACTUAL (PR #33655): Process killed immediately → onCleanup never runs → container keeps running
 */
import { execSync } from "node:child_process";
import { dirname, join } from "node:path";
import { writeFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import alchemy from "alchemy";
import { FileSystemStateStore } from "alchemy/state";

const __dirname = dirname(fileURLToPath(import.meta.url));
const NAME = "database";

const app = await alchemy(NAME, {
  stateStore: (scope) => new FileSystemStateStore(scope),
});

// Start Docker postgres
console.log(`[${NAME}] Starting Docker postgres...`);
execSync("docker compose up -d", { cwd: __dirname, stdio: "inherit" });
console.log(`[${NAME}] Docker postgres started`);

// Wait for postgres to be ready
console.log(`[${NAME}] Waiting for postgres to be ready...`);
for (let i = 0; i < 30; i++) {
  try {
    execSync("docker compose exec -T postgres pg_isready -U postgres", {
      cwd: __dirname,
      stdio: "pipe",
    });
    console.log(`[${NAME}] Postgres is ready!`);
    break;
  } catch {
    await new Promise((r) => setTimeout(r, 500));
  }
}

// Register cleanup - THIS SHOULD RUN BUT DOESN'T WITH PR #33655
const cleanupMarker = join(__dirname, ".cleanup-ran");
app.onCleanup(async () => {
  console.log(`[${NAME}] Cleanup handler called, writing marker file...`);
  writeFileSync(cleanupMarker, `Cleanup ran at ${new Date().toISOString()}\n`);
  console.log(`[${NAME}] Cleanup handler called, stopping Docker...`);
  try {
    execSync("docker compose down", { cwd: __dirname, stdio: "inherit" });
    console.log(`[${NAME}] Docker stopped`);
  } catch (error) {
    console.error(`[${NAME}] Failed to stop Docker:`, error);
  }
});

await app.finalize();
