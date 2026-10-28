import { mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { isDeepStrictEqual } from "node:util";

const parser = join(import.meta.dir, "../pkgs/build-support/import-bun-lock/jsonc.nix");
const temporary = mkdtempSync(join(tmpdir(), "nix-bun-jsonc-"));
let seed = 314159;
const random = (n: number) => {
  seed = (Math.imul(seed, 1664525) + 1013904223) >>> 0;
  return seed % n;
};
const strings = [
  "https://example.com/a//b", "/*not a comment*/", "\\\"//still a string",
  "trailing backslash\\", "},]", "a\nb\rc\td", "雪", "", "\\\\\"/*text*/",
];
const space = () => [" ", "\n", "/* quotes \" and //\n stars ** **/", "// comment /* \"\r\n", "/***/"][random(5)];
function value(depth = 0): unknown {
  switch (random(depth < 3 ? 6 : 4)) {
    case 0: return null;
    case 1: return Boolean(random(2));
    case 2: return random(100000) - 50000;
    case 3: return strings[random(strings.length)];
    case 4: return Array.from({ length: random(5) }, () => value(depth + 1));
    default: return Object.fromEntries(Array.from({ length: random(5) }, (_, i) => [`k${i}`, value(depth + 1)]));
  }
}
function jsonc(input: unknown): string {
  if (input && typeof input === "object") {
    const array = Array.isArray(input);
    const entries = array ? input.map(jsonc) : Object.entries(input).map(([key, value]) => JSON.stringify(key) + space() + ":" + space() + jsonc(value));
    return (array ? "[" : "{") + space() + entries.join(space() + "," + space())
      + (entries.length && random(2) ? space() + "," : "") + space() + (array ? "]" : "}");
  }
  return JSON.stringify(input);
}
function nix(expression: string) {
  return Bun.spawnSync(["nix", "eval", "--impure", "--json", "--option", "allow-import-from-derivation", "false", "--expr", expression]);
}
try {
  const inputs = Array.from({ length: 1000 }, () => space() + jsonc(value()) + space());
  inputs.push(
    '{"url":"https://example.com/*hi*/",/* x */"array":[1,2,],}',
    '/* a ***/ [true, // CR line ending\r false,]',
    '[1/*do not join*/ , 2]',
    '/* a /* nonnested */ {"x":1}',
    '"\\\"/*not a comment*/"',
    '"' + "a".repeat(10000) + '"',
    "/*" + "a".repeat(10000) + "*/true",
    readFileSync(join(import.meta.dir, "fixtures/basic/bun.lock"), "utf8"),
    readFileSync(join(import.meta.dir, "fixtures/workspace/bun.lock"), "utf8"),
  );
  const expected = inputs.map(input => Bun.JSONC.parse(input));
  const file = join(temporary, "valid.json");
  writeFileSync(file, JSON.stringify(inputs));
  const result = nix(`map (input: (import ${JSON.stringify(parser)}) input) (builtins.fromJSON (builtins.readFile ${JSON.stringify(file)}))`);
  if (result.exitCode !== 0) throw new Error(result.stderr.toString());
  if (!isDeepStrictEqual(JSON.parse(result.stdout.toString()), expected)) throw new Error("Nix/Bun parsing mismatch");

  const invalid = [
    "[, ]", "{,}", "[1,,]", '["x",,]', '{"a":,}',
    "[1/*x*/2]", "[tru/*x*/e]", '["a"/*x*/"b"]',
    "/* unterminated", "/*x*/ /* unterminated", '"unterminated // comment',
    '"unterminated /*comment*/', '"raw\nnewline"', '"bad\\qescape"',
    "[1] /* nested /* not actually nested */ */", "// no value", "",
  ];
  for (const input of invalid) {
    let accepted = false;
    try { Bun.JSONC.parse(input); accepted = true; } catch {}
    if (accepted) throw new Error(`Invalid test is accepted by Bun: ${JSON.stringify(input)}`);
    const file = join(temporary, "invalid.jsonc");
    writeFileSync(file, input);
    const result = nix(`(import ${JSON.stringify(parser)}) (builtins.readFile ${JSON.stringify(file)})`);
    if (result.exitCode === 0) throw new Error(`Invalid JSONC accepted: ${JSON.stringify(input)}`);
  }
  console.log(`Passed: ${inputs.length} valid inputs match Bun.JSONC.parse; ${invalid.length} malformed inputs rejected; IFD disabled.`);
} finally {
  rmSync(temporary, { recursive: true, force: true });
}
