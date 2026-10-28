{
  lib,
  stdenv,
  buildBunPackage,
  fetchFromGitHub,
  makeBinaryWrapper,
  tailwindcss_4,
  typescript_7,
  assimp,
  calibre,
  dasel,
  ffmpeg-headless,
  graphicsmagick,
  imagemagick,
  inkscape,
  libheif,
  libjxl,
  libreoffice,
  libva,
  pandoc,
  perl5Packages,
  potrace,
  python3,
  resvg,
  texliveBasic,
  vips,
  vtracer,
}:

# Based on nixpkgs pkgs/by-name/co/convertx/package.nix.
# Exercises a compiled TypeScript service with external runtime tools.
buildBunPackage (finalAttrs: {
  pname = "convertx";
  version = "0.19.0";
  __structuredAttrs = true;

  src = fetchFromGitHub {
    owner = "C4illin";
    repo = "ConvertX";
    tag = "v${finalAttrs.version}";
    hash = "sha256-7BaQSLl/LeXYOxpCIp0p+ucOsFkiI2JtGq9cm6iDNpM=";
  };

  bunDepsHash = {
    "aarch64-linux" = "sha256-/w1GZJ+VTWGgiUtuJbZ17NXp9c8cH7cKtv8ALgDsaZ4=";
    "x86_64-linux" = "sha256-8HB0IVRQOTp9ZJsjDbrMLuv7TkwdLUMz95psUb0lm/o=";
  }.${stdenv.hostPlatform.system};
  bunFetchFlags = [
    "--os=linux"
    "--cpu=${stdenv.hostPlatform.node.arch}"
    "--libc=glibc"
  ];
  bunInstallFlags = [ "--no-progress" ];

  postPatch = ''
    substituteInPlace tsconfig.json \
      --replace-fail '"downlevelIteration": true,' ""
  '';

  nativeBuildInputs = [
    makeBinaryWrapper
    tailwindcss_4
    typescript_7
  ];

  buildPhase = ''
    runHook preBuild

    tailwindcss -i ./src/main.css -o ./public/generated.css
    tsc
    substituteInPlace ./dist/src/index.js \
      --replace-fail 'assets: "public"' "assets: \"$out/share/convertx/dist/public\""

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p $out/bin $out/share/convertx $out/lib
    cp -R ./dist $out/share/convertx
    cp -R ./public $out/share/convertx/dist
    cp -R ./node_modules $out/lib/node_modules
    cp package.json $out/lib/package.json
    ln -s $out/lib/node_modules $out/node_modules

    makeBinaryWrapper ${lib.getExe finalAttrs.bun} $out/bin/convertx \
      --add-flags "run --prefer-offline --no-install $out/share/convertx/dist/src/index.js" \
      --set NODE_ENV production \
      --suffix PATH : ${
        lib.makeBinPath [
          assimp
          calibre
          dasel
          ffmpeg-headless
          graphicsmagick
          imagemagick
          inkscape
          libheif
          libjxl
          libreoffice
          libva
          pandoc
          perl5Packages.EmailOutlookMessage
          (python3.withPackages (ps: [ ps.markitdown ] ++ ps.markitdown.optional-dependencies.all))
          resvg
          (texliveBasic.withPackages (ps: [
            ps.dvisvgm
            ps.latex
            ps.latexmk
            ps.unicode-math
            ps.xcolor
            ps.xetex
          ]))
          vips
          vtracer
        ]
      }

    runHook postInstall
  '';

  meta = {
    description = "Self-hosted online file converter";
    homepage = "https://github.com/C4illin/ConvertX";
    license = lib.licenses.agpl3Only;
    mainProgram = "convertx";
    platforms = [
      "aarch64-linux"
      "x86_64-linux"
    ];
  };
})
