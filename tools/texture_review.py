"""Local texture review page for tools/add_map.py.

Serves every PNG the converter wrote for one map in a browser grid (50 per page). Clicking a texture marks it
rejected, which means add_map will not upload it and MapImport leaves that material flat-coloured. State is
saved to a JSON file, so the page can be reopened after a crash. Only 127.0.0.1 is bound.
"""
import json
import os
import threading
import webbrowser
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import unquote, urlparse

PAGE_SIZE = 50


def _page(names, rejected, url):
    payload = json.dumps({"names": names, "rejected": sorted(rejected), "pageSize": PAGE_SIZE}).replace("</", "<\\/")
    return """<!doctype html>
<html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Texture review</title>
<style>
:root{color-scheme:dark}
*{box-sizing:border-box}
body{margin:0;background:#191b1e;color:#dcdcdc;font:14px Arimo,Segoe UI,Arial,sans-serif}
header{position:sticky;top:0;z-index:2;display:flex;align-items:center;gap:14px;padding:10px 16px;
background:#37393d;border-bottom:1px solid #1e1f22}
h1{font-size:16px;margin:0;font-weight:600;color:#fff}
#count{color:#9fa3aa}
button{border:1px solid #1e1f22;border-radius:3px;background:#37393d;color:#dcdcdc;padding:6px 12px;
font:14px Arimo,Segoe UI,Arial,sans-serif;cursor:pointer}
button:hover{background:#4a4c52}
button.primary{background:#2387ed}button.primary:hover{background:#4f9ded}
main{display:grid;grid-template-columns:repeat(auto-fill,minmax(150px,1fr));gap:10px;padding:14px}
.card{background:#44464b;border:1px solid #1e1f22;border-radius:4px;overflow:hidden;cursor:pointer;
user-select:none;position:relative}
.card img{display:block;width:100%;height:120px;object-fit:contain;background:#2b2d31;image-rendering:auto}
.card .name{padding:6px;font-size:12px;color:#c9cbd0;word-break:break-all;line-height:1.25}
.card.rejected{outline:3px solid #c0392b}
.card.rejected img{opacity:.28;filter:grayscale(1)}
.card.rejected:after{content:"REJECTED";position:absolute;left:6px;top:6px;background:#c0392b;color:#fff;
font-size:11px;font-weight:700;padding:3px 6px;border-radius:2px}
footer{display:flex;gap:8px;justify-content:center;padding:0 14px 22px}
.hint{color:#9fa3aa;padding:0 16px 18px;max-width:900px;line-height:1.5}
</style></head><body>
<header><h1>Texture review</h1><span id="count"></span>
<button id="prev">Prev</button><span id="page"></span><button id="next">Next</button>
<span style="flex:1"></span><button id="done" class="primary">Done</button></header>
<main id="grid"></main>
<footer><button id="prev2">Prev</button><button id="next2">Next</button></footer>
<p class="hint">Click a texture to reject it. Rejected textures are not uploaded and stay flat-coloured in game.
Click again to undo. Review every page, then press Done.</p>
<script>
const DATA = __PAYLOAD__;
const names = DATA.names, rejected = new Set(DATA.rejected), size = DATA.pageSize;
let page = 0;
const grid = document.getElementById('grid');
function send(name, rejectedNow) {
  fetch('/reject', {method:'POST', headers:{'Content-Type':'application/json'},
    body: JSON.stringify({name, rejected: rejectedNow})});
}
function render() {
  grid.innerHTML = '';
  const pages = Math.max(1, Math.ceil(names.length / size));
  page = Math.max(0, Math.min(page, pages - 1));
  const slice = names.slice(page * size, page * size + size);
  for (const name of slice) {
    const card = document.createElement('div');
    card.className = 'card' + (rejected.has(name) ? ' rejected' : '');
    const img = document.createElement('img');
    img.loading = 'lazy'; img.src = '__URL__/tex/' + encodeURIComponent(name); img.alt = name;
    const label = document.createElement('div');
    label.className = 'name'; label.textContent = name;
    card.append(img, label);
    card.onclick = () => {
      if (rejected.has(name)) rejected.delete(name); else rejected.add(name);
      send(name, rejected.has(name));
      render();
    };
    grid.append(card);
  }
  document.getElementById('page').textContent = (page + 1) + ' / ' + pages;
  document.getElementById('count').textContent = names.length + ' textures, ' + rejected.size + ' rejected';
}
function step(delta) { page += delta; render(); }
document.getElementById('prev').onclick = () => step(-1);
document.getElementById('prev2').onclick = () => step(-1);
document.getElementById('next').onclick = () => step(1);
document.getElementById('next2').onclick = () => step(1);
document.getElementById('done').onclick = () => {
  fetch('/done', {method:'POST'}).then(() => {
    document.body.innerHTML = '<p style="padding:24px;font:16px Arimo,sans-serif">Saved. You can close this tab.</p>';
  });
};
render();
</script></body></html>""".replace("__PAYLOAD__", payload).replace("__URL__", url)


def review(png_dir, names, reject_path, open_browser=True, port=8767):
    """Show the review page. Returns the set of rejected names. Ctrl+C saves what was clicked so far."""
    allowed = {n for n in names if n.lower().endswith(".png") and os.path.exists(os.path.join(png_dir, n))}
    rejected = set()
    if os.path.exists(reject_path):
        try:
            raw = json.load(open(reject_path))
            rejected = set(raw.keys() if isinstance(raw, dict) else raw) & allowed
        except (ValueError, OSError):
            pass
    if not allowed:
        return rejected

    done = threading.Event()

    class Handler(BaseHTTPRequestHandler):
        def log_message(self, fmt, *args):
            pass

        def _send(self, code, body, content_type="application/json"):
            data = body if isinstance(body, bytes) else body.encode("utf-8")
            self.send_response(code)
            self.send_header("Content-Type", content_type)
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)

        def do_GET(self):
            path = urlparse(self.path).path
            if path == "/":
                html = _page(sorted(allowed), rejected, "http://127.0.0.1:%d" % self.server.server_port)
                self._send(200, html, "text/html; charset=utf-8")
            elif path.startswith("/tex/"):
                name = unquote(path[len("/tex/"):])
                if name not in allowed:
                    self._send(404, b"not found")
                    return
                try:
                    with open(os.path.join(png_dir, name), "rb") as fh:
                        self._send(200, fh.read(), "image/png")
                except OSError:
                    self._send(404, b"not found")
            elif path == "/state":
                self._send(200, json.dumps({"rejected": sorted(rejected)}))
            else:
                self._send(404, b"not found")

        def do_POST(self):
            if self.path == "/done":
                self._send(200, b'{"ok":true}')
                done.set()
                return
            if self.path != "/reject":
                self._send(404, b"not found")
                return
            length = int(self.headers.get("Content-Length", "0"))
            try:
                payload = json.loads(self.rfile.read(length) or b"{}")
                name = payload.get("name")
                if name not in allowed:
                    self._send(400, b'{"ok":false}')
                    return
                if payload.get("rejected"):
                    rejected.add(name)
                else:
                    rejected.discard(name)
                json.dump(sorted(rejected), open(reject_path, "w"), indent=0)
                self._send(200, b'{"ok":true}')
            except (ValueError, OSError):
                self._send(400, b'{"ok":false}')

    server = None
    chosen = port
    for candidate in range(port, port + 20):
        try:
            server = ThreadingHTTPServer(("127.0.0.1", candidate), Handler)
            chosen = candidate
            break
        except OSError:
            continue
    if server is None:
        raise OSError("no free local port for the texture review page")
    server.daemon_threads = True
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    url = "http://127.0.0.1:%d/" % chosen
    print("Texture review: %s  (%d images, 50 per page)" % (url, len(allowed)))
    print("Click a texture to reject it, then press Done in the page.")
    if open_browser:
        webbrowser.open(url)
    try:
        done.wait()
    except KeyboardInterrupt:
        print("Review interrupted; keeping the clicks made so far.")
    finally:
        server.shutdown()
        server.server_close()
        json.dump(sorted(rejected), open(reject_path, "w"), indent=0)
    return rejected
