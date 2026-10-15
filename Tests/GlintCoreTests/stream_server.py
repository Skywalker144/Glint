import http.server
import json
import time

class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def do_POST(self):
        body = json.loads(self.rfile.read(int(self.headers['Content-Length'])))
        mode = body['model']
        self.send_response(401 if mode == 'unauthorized' else 200)
        self.send_header('Content-Type', 'text/event-stream')
        self.end_headers()
        if mode == 'unauthorized':
            self.wfile.write(b'{"error":{"message":"invalid key"}}')
            return
        if mode == 'empty':
            return
        try:
            for part in ['你', '好', ' 🌍']:
                payload = 'data: ' + json.dumps({'choices': [{'delta': {'content': part}}]}, ensure_ascii=False) + '\r\n\r\n'
                for byte in payload.encode():
                    self.wfile.write(bytes([byte]))
                    self.wfile.flush()
                time.sleep(0.5 if mode == 'slow' else 0.02)
            self.wfile.write(b'data: [DONE]\n\n')
        except (BrokenPipeError, ConnectionResetError):
            pass

server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), Handler)
print(server.server_port, flush=True)
server.serve_forever()
