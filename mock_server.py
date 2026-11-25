# Mock CoolBeans API. Run: python3 mock_server.py  (port 8000, data kept in memory)
import json
from http.server import BaseHTTPRequestHandler, HTTPServer

DATA = {
    "drinks": [
        {"id": "1", "name": "Espresso", "caffeine": 64, "calories": 5},
        {"id": "2", "name": "Americano", "caffeine": 154, "calories": 10},
        {"id": "3", "name": "Latte", "caffeine": 150, "calories": 190},
        {"id": "4", "name": "Cappuccino", "caffeine": 120, "calories": 130},
        {"id": "5", "name": "Flat White", "caffeine": 130, "calories": 170},
        {"id": "6", "name": "Mocha", "caffeine": 175, "calories": 290},
        {"id": "7", "name": "Cold Brew", "caffeine": 200, "calories": 15},
    ],
    "milks": [
        {"id": "1", "name": "Whole", "calories": 60},
        {"id": "2", "name": "Oat", "calories": 50},
        {"id": "3", "name": "Almond", "calories": 25},
    ],
    "syrups": [
        {"id": "1", "name": "Vanilla", "calories": 80},
        {"id": "2", "name": "Caramel", "calories": 90},
        {"id": "3", "name": "Hazelnut", "calories": 70},
    ],
}
servings = {}


class H(BaseHTTPRequestHandler):
    def reply(self, code, body=None):
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        if body is not None:
            self.wfile.write(json.dumps(body).encode())

    def do_GET(self):
        name = self.path.strip("/")
        self.reply(200, DATA[name]) if name in DATA else self.reply(404)

    def do_POST(self):
        s = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
        servings[s["id"]] = s
        print("logged", s["drink"], len(servings), "total")
        self.reply(201, s)

    def do_DELETE(self):
        servings.pop(self.path.rsplit("/", 1)[-1], None)
        print("deleted, left:", len(servings))
        self.reply(204)


HTTPServer(("", 8000), H).serve_forever()
