"""Small authenticated registry; never logs request headers or credentials."""
import base64
import gzip
import hashlib
import http.server
import io
import json
import os
from pathlib import Path
import tarfile


def archive():
    buffer = io.BytesIO()
    with tarfile.open(fileobj=buffer, mode="w", format=tarfile.USTAR_FORMAT) as tar:
        for name, data in {
            "package/package.json": b'{"name":"@private/example","version":"1.0.0","main":"index.js"}',
            "package/index.js": b'module.exports = "authenticated";\n',
        }.items():
            entry = tarfile.TarInfo(name)
            entry.size = len(data)
            entry.mode = 0o644
            tar.addfile(entry, io.BytesIO(data))
    compressed = io.BytesIO()
    with gzip.GzipFile(fileobj=compressed, mode="wb", filename="", mtime=0) as stream:
        stream.write(buffer.getvalue())
    return compressed.getvalue()


if __name__ == "__main__":
    tarball = archive()
    state = Path(os.environ["REGISTRY_STATE"])
    state.mkdir()

    class Handler(http.server.BaseHTTPRequestHandler):
        def log_message(self, *_args):
            pass

        def do_GET(self):
            if self.headers.get("Authorization") != "Bearer " + os.environ["NIX_BUN_TEST_TOKEN"]:
                self.send_error(401)
                return
            (state / "authenticated").touch()
            if self.path.endswith(".tgz"):
                data = tarball
            else:
                data = json.dumps({
                    "name": "@private/example",
                    "dist-tags": {"latest": "1.0.0"},
                    "versions": {"1.0.0": {
                        "name": "@private/example", "version": "1.0.0",
                        "dist": {
                            "tarball": f"http://127.0.0.1:{self.server.server_port}/example.tgz",
                            "integrity": "sha512-" + base64.b64encode(hashlib.sha512(tarball).digest()).decode(),
                        },
                    }},
                }).encode()
            self.send_response(200)
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)

    server = http.server.HTTPServer(("127.0.0.1", 0), Handler)
    (state / "port").write_text(str(server.server_port))
    server.serve_forever()
