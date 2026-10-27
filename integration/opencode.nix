{
  lib,
  stdenv,
  buildBunPackage,
  darwin,
  fetchFromGitHub,
  installShellFiles,
  makeBinaryWrapper,
  models-dev,
  nodejs,
  nix-update-script,
  ripgrep,
  sysctl,
  versionCheckHook,
  wayland,
  writableTmpDirAsHomeHook,
}:
# Based on nixpkgs pkgs/by-name/op/opencode/package.nix (opencode 2.1.1).
# https://github.com/NixOS/nixpkgs/blob/3ec636362e1816bc2f0888fa0fa2c69f1bc9e504/pkgs/by-name/op/opencode/package.nix
# Keep the package phases aligned; buildBunPackage supplies the offline install.
buildBunPackage (finalAttrs: {
  pname = "opencode";
  version = "2.1.1";

  __structuredAttrs = true;
  strictDeps = true;

  src = fetchFromGitHub {
    owner = "anomalyco";
    repo = "opencode";
    tag = "v${finalAttrs.version}";
    hash = "sha256-CoujRYCvqFXDJ6bzMxinT8CSPyKiLSAzCINjVaZBm/Y=";
  };

  postPatch =
    # Relax Bun version check to be a warning instead of an error
    ''
      substituteInPlace packages/script/src/index.ts \
        --replace-fail \
        'throw new Error(`This script requires bun@''${expectedBunVersionRange}' \
        'console.warn(`Warning: This script requires bun@''${expectedBunVersionRange}'
    ''
    # Avoid requiring prettier just to format the schema JSON
    + ''
      substituteInPlace packages/cli/script/schema.ts \
        --replace-fail 'import { format } from "prettier"' 'const format = (s: string) => JSON.stringify(JSON.parse(s), null, 2)'
    ''
    # Bun 1.4.4 rejects the extra indentation in this upstream patch's context.
    + ''
      substituteInPlace patches/@silvia-odwyer%2Fphoton-node@0.3.4.patch \
        --replace-fail $'      ;\n  };\n  \n' $'     ;\n };\n \n'
    '';

  bunDepsHash = "sha256-UwD/nWCZFMLP1QFTzJcpyFNjVu6WQYceEnvB9ys9W6g=";
  makeCacheWritable = true;
  bunInstallFlags = [
    "--filter"
    "./"
    "--filter"
    "./packages/cli"
    "--filter"
    "./packages/desktop"
    "--filter"
    "./packages/app"
    "--no-progress"
  ];

  postBunInstall = ''
    bun --bun ./nix/scripts/canonicalize-node-modules.ts
    bun --bun ./nix/scripts/normalize-bun-binaries.ts
    patchShebangs packages/*/node_modules
  '';

  nativeBuildInputs = [
    installShellFiles
    makeBinaryWrapper
    nodejs
    writableTmpDirAsHomeHook
  ]
  ++ lib.optionals stdenv.hostPlatform.isDarwin [
    darwin.autoSignDarwinBinariesHook
  ];

  env = {
    MODELS_DEV_API_JSON = "${models-dev}/dist/_api.json";
    OPENCODE_DISABLE_MODELS_FETCH = true;
    OPENCODE_VERSION = finalAttrs.version;
    OPENCODE_CHANNEL = "latest";
    NODE_OPTIONS = "--max-old-space-size=4096";
  };

  buildPhase = ''
    runHook preBuild

    cd ./packages/cli
    bun --bun ./script/build.ts --single --skip-install
    bun --bun ./script/schema.ts cli.json
    bun --bun ../schema/script/config-schema.ts config.json

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    install -Dm755 dist/cli-*/bin/opencode $out/bin/opencode

    wrapArgs=(
      --set OPENCODE_DISABLE_AUTOUPDATE true
      --suffix PATH : ${lib.makeBinPath [ ripgrep ]}
    )
    ${lib.optionalString stdenv.hostPlatform.isDarwin ''
      wrapArgs+=(--prefix PATH : ${lib.makeBinPath [ sysctl ]})
    ''}
    ${lib.optionalString stdenv.hostPlatform.isLinux ''
      wrapArgs+=(--prefix LD_LIBRARY_PATH : ${
        lib.makeLibraryPath [
          stdenv.cc.cc
          wayland
        ]
      })
    ''}

    wrapProgramBinary $out/bin/opencode "''${wrapArgs[@]}"

    install -Dm644 cli.json $out/share/cli.json
    install -Dm644 config.json $out/share/config.json
    install -Dm644 ../web/public/theme.json $out/share/theme.json

    runHook postInstall
  '';

  postInstall = lib.optionalString (stdenv.buildPlatform.canExecute stdenv.hostPlatform) ''
    installShellCompletion --cmd opencode \
      --bash <($out/bin/opencode --completions bash) \
      --zsh <($out/bin/opencode --completions zsh) \
      --fish <($out/bin/opencode --completions fish)
  '';

  dontStrip = true;

  nativeInstallCheckInputs = [
    versionCheckHook
    writableTmpDirAsHomeHook
  ];
  doInstallCheck = true;
  versionCheckKeepEnvironment = [
    "HOME"
    "OPENCODE_DISABLE_MODELS_FETCH"
  ];
  versionCheckProgramArg = "--version";

  passthru = {
    jsonschema = {
      cli = "${finalAttrs.finalPackage}/share/cli.json";
      config = "${finalAttrs.finalPackage}/share/config.json";
      theme = "${finalAttrs.finalPackage}/share/theme.json";
    };
    updateScript = nix-update-script {
      extraArgs = [
        "--subpackage"
        "bunDeps"
      ];
    };
  };

  meta = {
    description = "AI coding agent built for the terminal";
    homepage = "https://github.com/anomalyco/opencode";
    changelog = "https://github.com/anomalyco/opencode/releases/tag/v${finalAttrs.version}";
    license = lib.licenses.mit;
    maintainers = with lib.maintainers; [
      delafthi
      DuskyElf
      graham33
      xiaoxiangmoe
    ];
    sourceProvenance = with lib.sourceTypes; [ fromSource ];
    platforms = [
      "aarch64-linux"
      "x86_64-linux"
      "aarch64-darwin"
    ];
    mainProgram = "opencode";
  };
})
