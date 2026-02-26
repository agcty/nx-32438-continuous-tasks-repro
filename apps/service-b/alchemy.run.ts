/**
 * Alchemy configuration for service-b
 */
import alchemy from "alchemy";
import { FileSystemStateStore } from "alchemy/state";
import http from "node:http";

const PORT = 3002;
const NAME = "service-b";

const app = await alchemy(NAME, {
  stateStore: (scope) => new FileSystemStateStore(scope),
});

const server = http.createServer((req, res) => {
  console.log(`[${NAME}] Received request`);
  res.writeHead(200, { "Content-Type": "text/plain" });
  res.end(`Hello from ${NAME}\n`);
});

server.listen(PORT, () => {
  console.log(`[${NAME}] Server starting on port ${PORT}`);
});

app.onCleanup(async () => {
  const fs = await import("node:fs");
  const timestamp = new Date().toISOString();
  fs.writeFileSync(`/tmp/nx-investigation/repro/cleanup-${NAME}.log`, `${timestamp} - ${NAME} cleanup handler ran\n`, { flag: "a" });
  console.log(`[${NAME}] Cleanup handler called, closing server...`);
  await new Promise<void>((resolve, reject) => {
    server.close((err) => {
      if (err) reject(err);
      else resolve();
    });
  });
  fs.writeFileSync(`/tmp/nx-investigation/repro/cleanup-${NAME}.log`, `${timestamp} - ${NAME} server closed\n`, { flag: "a" });
  console.log(`[${NAME}] Server closed`);
});

await app.finalize();
