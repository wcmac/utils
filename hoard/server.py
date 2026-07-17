"""Local web server for browsing/searching the hoard index. Binds to localhost only."""

from pathlib import Path

from flask import Flask, jsonify, request, send_file, abort

from hoard import db
from hoard.thumbs import ensure_thumb

STATIC_DIR = Path(__file__).parent / "static"

app = Flask(__name__, static_folder=None)


def _row_to_summary(row) -> dict:
    return {
        "id": row["id"],
        "path": row["path"],
        "positive_prompt": row["positive_prompt"],
        "negative_prompt": row["negative_prompt"],
    }


def _row_to_detail(row) -> dict:
    d = _row_to_summary(row)
    d.update({
        "width": row["width"],
        "height": row["height"],
        "model": row["model"],
        "sampler": row["sampler"],
        "seed": row["seed"],
        "steps": row["steps"],
        "cfg_scale": row["cfg_scale"],
        "raw_params": row["raw_params"],
    })
    return d


@app.get("/")
def index():
    return send_file(STATIC_DIR / "index.html")


@app.get("/app.js")
def app_js():
    return send_file(STATIC_DIR / "app.js")


@app.get("/style.css")
def style_css():
    return send_file(STATIC_DIR / "style.css")


@app.get("/api/search")
def api_search():
    query = request.args.get("q", "")
    offset = int(request.args.get("offset", 0))
    conn = db.connect()
    rows = db.search(conn, query, limit=60, offset=offset)
    conn.close()
    return jsonify([_row_to_summary(r) for r in rows])


@app.get("/api/image/<int:image_id>")
def api_image(image_id):
    conn = db.connect()
    row = db.get_image(conn, image_id)
    conn.close()
    if row is None:
        abort(404)
    return jsonify(_row_to_detail(row))


@app.get("/thumb/<int:image_id>")
def thumb(image_id):
    conn = db.connect()
    row = db.get_image(conn, image_id)
    conn.close()
    if row is None:
        abort(404)
    path = Path(row["path"])
    if not path.exists():
        abort(404)
    return send_file(ensure_thumb(str(path)))


@app.get("/full/<int:image_id>")
def full(image_id):
    conn = db.connect()
    row = db.get_image(conn, image_id)
    conn.close()
    if row is None:
        abort(404)
    path = Path(row["path"])
    if not path.exists():
        abort(404)
    return send_file(path)


def run(port: int = 8420):
    app.run(host="127.0.0.1", port=port, debug=False)
