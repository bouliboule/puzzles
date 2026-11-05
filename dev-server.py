#!/usr/bin/env python3
"""Local dev server for web/ with caching disabled."""
import http.server, functools, sys

class H(http.server.SimpleHTTPRequestHandler):
    extensions_map = {**http.server.SimpleHTTPRequestHandler.extensions_map,
                      '.wasm': 'application/wasm', '.js': 'text/javascript',
                      '.webmanifest': 'application/manifest+json'}
    def end_headers(self):
        self.send_header('Cache-Control', 'no-store')
        super().end_headers()

port = int(sys.argv[1]) if len(sys.argv) > 1 else 8642
http.server.ThreadingHTTPServer(('', port), functools.partial(H, directory='web')).serve_forever()
