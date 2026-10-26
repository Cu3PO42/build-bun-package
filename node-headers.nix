{ fetchzip }:
let
  version = "26.3.0";
in
fetchzip {
  name = "node-headers-${version}";
  inherit version;
  url = "https://nodejs.org/download/release/v${version}/node-v${version}-headers.tar.gz";
  hash = "sha256-O1niKQrWkstIzSsSog2uD+Q6+FpOphNFF/McTE7bfk0=";
}
