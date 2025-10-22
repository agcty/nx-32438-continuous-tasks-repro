const http = require('http');

const PORT = 3001;
const NAME = 'service-a';

const server = http.createServer((req, res) => {
  console.log(`[${NAME}] Received request`);
  res.writeHead(200, { 'Content-Type': 'text/plain' });
  res.end(`Hello from ${NAME}\n`);
});

server.listen(PORT, () => {
  console.log(`[${NAME}] Server starting on port ${PORT}`);
});

// Graceful shutdown handler
process.on('SIGINT', () => {
  console.log(`[${NAME}] Received SIGINT, shutting down gracefully...`);
  server.close(() => {
    console.log(`[${NAME}] Server shut down`);
    process.exit(0);
  });
});

process.on('SIGTERM', () => {
  console.log(`[${NAME}] Received SIGTERM, shutting down gracefully...`);
  server.close(() => {
    console.log(`[${NAME}] Server shut down`);
    process.exit(0);
  });
});

// Keep process alive
setInterval(() => {
  // Just keep the process running
}, 1000);

