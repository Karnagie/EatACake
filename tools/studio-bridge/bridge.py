"""Studio <-> agent bridge.

GET  /<name>   -> serves scratchpad/push/<name> (source push INTO Studio)
POST /report   -> writes the body to scratchpad/reports/<ts>.txt  (readout OUT)

Studio's HttpService is allowed to hit localhost, so this beats OCR'ing the
Output window: the command bar POSTs a structured report and I read the file.
"""
import os, sys, time
from http.server import BaseHTTPRequestHandler, HTTPServer

ROOT = os.path.dirname(os.path.abspath(__file__))
PUSH = os.path.join(ROOT, "push")
REPORTS = os.path.join(ROOT, "reports")
os.makedirs(PUSH, exist_ok=True)
os.makedirs(REPORTS, exist_ok=True)


class H(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def _send(self, code, body=b"", ctype="text/plain"):
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        if body:
            self.wfile.write(body)

    def do_GET(self):
        name = self.path.lstrip("/").split("?")[0]
        path = os.path.join(PUSH, os.path.basename(name))
        if not name or not os.path.isfile(path):
            return self._send(404, b"no such push file")
        with open(path, "rb") as f:
            self._send(200, f.read())

    def do_POST(self):
        n = int(self.headers.get("Content-Length") or 0)
        body = self.rfile.read(n)
        name = os.path.basename(self.path.lstrip("/")) or "report"
        out = os.path.join(REPORTS, f"{name}.txt")
        with open(out, "wb") as f:
            f.write(body)
        print(f"[{time.strftime('%H:%M:%S')}] {len(body)}B -> reports/{name}.txt", flush=True)
        self._send(200, b"ok")


if __name__ == "__main__":
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8732
    print(f"bridge on http://localhost:{port}  (push={PUSH}, reports={REPORTS})", flush=True)
    HTTPServer(("127.0.0.1", port), H).serve_forever()
