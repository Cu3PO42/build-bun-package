# Bun serializes SCP-style paths as git+ssh://user@host:path. Git expects
# user@host:path instead. Preserve ordinary SSH URLs, including numeric ports.
url:
let
  bracketed = builtins.match "ssh://[^/]*].*" url != null;
  scp = builtins.match (if bracketed then "ssh://([^/]+]):(.*)" else "ssh://([^/:]+):(.*)") url;
  port = if scp == null then null else builtins.match "[0-9]+(/.*)?" (builtins.elemAt scp 1);
in
if scp != null && port == null then "${builtins.elemAt scp 0}:${builtins.elemAt scp 1}" else url
