// Nix fetches and verifies the archives; Bun owns extraction and cache naming.
import { readFileSync } from "node:fs";

type Entry = {
  id: string;
  key: string;
  kind: "npm" | "tarball";
  packageName: string;
  path: string;
};

const entries: Entry[] = JSON.parse(readFileSync(process.argv[2], "utf8"));
const archives = new Map(entries.map((entry) => [`/${entry.id}`, entry.path]));
const lock = Bun.JSONC.parse(readFileSync("bun.lock", "utf8"));
const server = Bun.serve({
  hostname: "127.0.0.1",
  port: 0,
  fetch(request) {
    const path = archives.get(new URL(request.url).pathname);
    return path
      ? new Response(Bun.file(path))
      : new Response("Unknown tarball", { status: 404 });
  },
});

let child: ReturnType<typeof Bun.spawn> | undefined;
const stop = () => child?.kill();
process.on("SIGINT", stop);
process.on("SIGTERM", stop);
try {
  for (const entry of entries) {
    const url = `http://127.0.0.1:${server.port}/${entry.id}`;
    if (entry.kind === "npm") {
      lock.packages[entry.key][1] = url;
    } else {
      // Tarball cache names are based on integrity, so replacing the URL does
      // not change the cache used by the original lockfile's offline install.
      lock.packages[entry.key][0] = `${entry.packageName}@${url}`;
    }
  }
  await Bun.write("bun.lock", JSON.stringify(lock));
  // Async spawn keeps the server's event loop available to serve archives.
  child = Bun.spawn([
    process.execPath, "pm", "fetch", "--frozen-lockfile",
    "--os", "*", "--cpu", "*", "--libc", "*",
  ], { stdout: "inherit", stderr: "inherit" });
  const status = await child.exited;
  if (status !== 0) throw new Error(`importBunLock: cache population failed (${status})`);
} finally {
  child?.kill();
  server.stop(true);
  process.off("SIGINT", stop);
  process.off("SIGTERM", stop);
}
