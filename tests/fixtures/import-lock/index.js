#!/usr/bin/env bun
if (!require("is-even")(4)) throw new Error("nested dependency failed");
if (!require("is-number")("3")) throw new Error("tarball dependency failed");
if (!require("odd-alias")(3)) throw new Error("registry alias failed");
if (require("react/package.json").version !== "19.0.0-rc.1" || typeof require("react").useState !== "function") throw new Error("prerelease failed");
console.log("imported lock works");
