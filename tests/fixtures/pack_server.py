"""Serveur HTTP local des tests du client de données (tests/test_pack_downloader.gd) : fichiers statiques avec
requêtes Range (reprise), journal des requêtes, et préfixes de simulation :
  /cut/<chemin>   première requête sans Range coupée à mi-fichier (coupure réseau)
  /slow/<chemin>  envoi lent (64 ko toutes les 50 ms) pour tester l'annulation
Usage : python3 pack_server.py <racine> <port>"""
import http.server, os, sys, threading, time
ROOT, PORT = sys.argv[1], int(sys.argv[2])
CUT_DONE = set(); LOCK = threading.Lock()


class H(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *a): pass

    def do_GET(self):
        path = self.path.split("?")[0]; cut = slow = False
        if path.startswith("/cut/"): cut, path = True, path[4:]
        if path.startswith("/slow/"): slow, path = True, path[5:]
        rng = self.headers.get("Range", "")
        with LOCK, open(os.path.join(ROOT, "_log.txt"), "a") as log: log.write(f"{self.path} {rng}\n")
        f = os.path.normpath(os.path.join(ROOT, path.lstrip("/")))
        if not f.startswith(os.path.abspath(ROOT)) or not os.path.isfile(f):
            self.send_response(404); self.send_header("Content-Length", "0"); self.end_headers(); return
        data = open(f, "rb").read(); start = 0
        if rng.startswith("bytes="):
            start = int(rng[6:].split("-")[0] or 0)
            if start >= len(data):
                self.send_response(416); self.send_header("Content-Length", "0"); self.end_headers(); return
            self.send_response(206); self.send_header("Content-Range", f"bytes {start}-{len(data) - 1}/{len(data)}")
        else: self.send_response(200)
        body = data[start:]
        self.send_header("Content-Length", str(len(body))); self.send_header("Accept-Ranges", "bytes"); self.end_headers()
        if cut and not rng:
            with LOCK: first = f not in CUT_DONE; CUT_DONE.add(f)
            if first:
                self.wfile.write(body[:len(body) // 2]); self.wfile.flush(); self.close_connection = True
                self.connection.shutdown(2); return
        if slow:
            for i in range(0, len(body), 65536):
                try: self.wfile.write(body[i:i + 65536]); self.wfile.flush()
                except OSError: return
                time.sleep(0.05)
            return
        self.wfile.write(body)


http.server.ThreadingHTTPServer(("127.0.0.1", PORT), H).serve_forever()
