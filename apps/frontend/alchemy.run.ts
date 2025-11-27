import alchemy from "alchemy";
import { ReactRouter } from "alchemy/cloudflare";
import { FileSystemStateStore } from "alchemy/state";

const app = await alchemy("frontend", {
  stateStore: (scope) => new FileSystemStateStore(scope),
});

export const worker = await ReactRouter("website");

console.log({
  url: worker.url,
});

await app.finalize();
