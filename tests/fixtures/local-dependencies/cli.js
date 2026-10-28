const assert = require("node:assert/strict");

assert.equal(require("first"), 42);
assert.equal(require("local"), "linked");
console.log("local dependencies work");
