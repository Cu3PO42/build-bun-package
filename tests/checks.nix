{ pkgs, example }:
let
  checked = example.overrideAttrs (_: {
    bunDeps = example.bunDeps;
    checkPhase = null;
    postPatch = ''
      cat > dependency.test.js <<'JS'
      import { test, expect } from "bun:test";
      import { existsSync } from "node:fs";
      test("checks run with development dependencies and standard hooks", () => {
        expect(existsSync("pre-check-ran")).toBe(true);
        expect(require("is-odd")(3)).toBe(true);
        expect(require("esbuild").version).toBe("0.25.0");
      });
      JS
    '';
    preCheck = "touch pre-check-ran";
    postCheck = "touch post-check-ran";
    postInstallCheck = "test -f post-check-ran";
  });
in
{
  check-hook = checked;

  check-failure = pkgs.testers.testBuildFailure' {
    drv = checked.overrideAttrs (old: {
      postPatch = old.postPatch + ''
        cat > failure.test.js <<'JS'
        import { test } from "bun:test";
        test("failure propagates", () => { throw new Error("BUN_CHECK_MUST_FAIL"); });
        JS
      '';
    });
    expectedBuilderLogEntries = [ "BUN_CHECK_MUST_FAIL" ];
  };

  check-script-flags = checked.overrideAttrs (_: {
    __structuredAttrs = true;
    bunCheckScript = "verify";
    bunCheckFlags = [
      "argument with spaces"
      "literal *"
    ];
    bunFlags = [ "--no-env-file" ];
    postPatch = ''
      bun -e '
        const fs = require("fs");
        const p = JSON.parse(fs.readFileSync("package.json", "utf8"));
        p.scripts.verify = "bun ./verify.js";
        fs.writeFileSync("package.json", JSON.stringify(p));
      '
      cat > verify.js <<'JS'
      import { existsSync } from "node:fs";
      if (!existsSync("pre-check-ran")) throw new Error("missing preCheck");
      if (JSON.stringify(process.argv.slice(2)) !== JSON.stringify(["argument with spaces", "literal *"])) {
        throw new Error(JSON.stringify(process.argv));
      }
      JS
    '';
  });

  standalone-workspace-check =
    pkgs.runCommand "bun-standalone-workspace-check"
      {
        nativeBuildInputs = [ pkgs.bunHooks.bunCheckHook ];
      }
      ''
        mkdir -p project/apps/cli
        cat > project/apps/cli/location.test.js <<'JS'
        import { test, expect } from "bun:test";
        test("selected workspace", () => expect(process.cwd().endsWith("/project/apps/cli")).toBe(true));
        JS
        bunRoot=project
        bunWorkspace=apps/cli
        previous=$PWD
        bunCheckHook
        test "$PWD" = "$previous"
        touch "$out"
      '';

  check-disabled = checked.overrideAttrs (_: {
    dontBunCheck = true;
    postPatch = ''
      echo 'throw new Error("disabled checks must not run")' > disabled.test.js
    '';
    preCheck = "";
    postCheck = "";
    postInstallCheck = "test ! -f post-check-ran";
  });
}
