#!/usr/bin/env bun
if (require("first")() !== 42 || require("second")() !== 42) throw new Error("Git dependency failed");
console.log("git sources work");
