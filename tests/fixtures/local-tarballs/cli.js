#!/usr/bin/env bun
for (const name of ["first", "second", "third", "directory"]) {
  if (require(name)() !== 42) throw new Error(`${name} failed`);
}
if (require("local-tarballs/package.json").name !== "local-tarballs") throw new Error("self-reference failed");
console.log("local tarballs work");
