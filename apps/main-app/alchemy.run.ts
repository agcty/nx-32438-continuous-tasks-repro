/**
 * Alchemy configuration for main-app
 *
 * This mimics the production setup:
 * - alchemy() initializes the app
 * - A simple HTTP server runs during dev mode
 * - Cleanup handlers ensure graceful shutdown
 */
import alchemy from "alchemy";
import { FileSystemStateStore } from "alchemy/state";
import http from "node:http";

const PORT = 3000;
const NAME = "main-app";

const app = await alchemy(NAME, {
  stateStore: (scope) => new FileSystemStateStore(scope),
});

// Create a simple HTTP server (like a React Router dev server would)
const server = http.createServer((req, res) => {
  console.log(`[${NAME}] Received request`);
  res.writeHead(200, { "Content-Type": "text/plain" });
  res.end(`Hello from ${NAME}\n`);
});

server.listen(PORT, () => {
  console.log(`[${NAME}] Server starting on port ${PORT}`);
});

// Register cleanup handler - this is what alchemy calls on shutdown
app.onCleanup(async () => {
  console.log(`[${NAME}] Cleanup handler called, closing server...`);
  await new Promise<void>((resolve, reject) => {
    server.close((err) => {
      if (err) reject(err);
      else resolve();
    });
  });
  console.log(`[${NAME}] Server closed`);
});

await app.finalize();
