"""SQLite storage for hoard: schema, connection, and FTS5 search."""

from __future__ import annotations

import re
import sqlite3
from pathlib import Path

DB_PATH = Path.home() / ".local" / "share" / "hoard" / "index.db"

SCHEMA = """
CREATE TABLE IF NOT EXISTS images (
    id INTEGER PRIMARY KEY,
    path TEXT UNIQUE NOT NULL,
    mtime REAL NOT NULL,
    size INTEGER NOT NULL,
    width INTEGER,
    height INTEGER,
    positive_prompt TEXT,
    negative_prompt TEXT,
    model TEXT,
    sampler TEXT,
    seed TEXT,
    steps INTEGER,
    cfg_scale REAL,
    raw_params TEXT,
    indexed_at REAL NOT NULL
);

CREATE VIRTUAL TABLE IF NOT EXISTS images_fts USING fts5(
    positive_prompt, negative_prompt, content=images, content_rowid=id
);

CREATE TRIGGER IF NOT EXISTS images_ai AFTER INSERT ON images BEGIN
    INSERT INTO images_fts(rowid, positive_prompt, negative_prompt)
    VALUES (new.id, new.positive_prompt, new.negative_prompt);
END;

CREATE TRIGGER IF NOT EXISTS images_ad AFTER DELETE ON images BEGIN
    INSERT INTO images_fts(images_fts, rowid, positive_prompt, negative_prompt)
    VALUES ('delete', old.id, old.positive_prompt, old.negative_prompt);
END;

CREATE TRIGGER IF NOT EXISTS images_au AFTER UPDATE ON images BEGIN
    INSERT INTO images_fts(images_fts, rowid, positive_prompt, negative_prompt)
    VALUES ('delete', old.id, old.positive_prompt, old.negative_prompt);
    INSERT INTO images_fts(rowid, positive_prompt, negative_prompt)
    VALUES (new.id, new.positive_prompt, new.negative_prompt);
END;
"""


def connect() -> sqlite3.Connection:
    DB_PATH.parent.mkdir(parents=True, exist_ok=True)
    DB_PATH.parent.chmod(0o700)
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    conn.executescript(SCHEMA)
    return conn


def get_indexed_file(conn: sqlite3.Connection, path: str) -> sqlite3.Row | None:
    return conn.execute(
        "SELECT mtime, size FROM images WHERE path = ?", (path,)
    ).fetchone()


def upsert_image(conn: sqlite3.Connection, record: dict) -> None:
    conn.execute(
        """
        INSERT INTO images (
            path, mtime, size, width, height,
            positive_prompt, negative_prompt,
            model, sampler, seed, steps, cfg_scale,
            raw_params, indexed_at
        ) VALUES (
            :path, :mtime, :size, :width, :height,
            :positive_prompt, :negative_prompt,
            :model, :sampler, :seed, :steps, :cfg_scale,
            :raw_params, :indexed_at
        )
        ON CONFLICT(path) DO UPDATE SET
            mtime=excluded.mtime, size=excluded.size,
            width=excluded.width, height=excluded.height,
            positive_prompt=excluded.positive_prompt,
            negative_prompt=excluded.negative_prompt,
            model=excluded.model, sampler=excluded.sampler,
            seed=excluded.seed, steps=excluded.steps, cfg_scale=excluded.cfg_scale,
            raw_params=excluded.raw_params, indexed_at=excluded.indexed_at
        """,
        record,
    )


def delete_missing_under(conn: sqlite3.Connection, root: str, existing_paths: set[str]) -> int:
    """Remove DB rows for files under `root` that are no longer present on disk."""
    rows = conn.execute(
        "SELECT id, path FROM images WHERE path LIKE ? ESCAPE '\\'",
        (_like_prefix(root),),
    ).fetchall()
    stale_ids = [row["id"] for row in rows if row["path"] not in existing_paths]
    if stale_ids:
        conn.executemany("DELETE FROM images WHERE id = ?", [(i,) for i in stale_ids])
    return len(stale_ids)


def _like_prefix(root: str) -> str:
    escaped = root.replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_")
    return escaped.rstrip("/") + "/%"


_TERM_RE = re.compile(r'[^,]+')


def build_fts_query(query: str) -> str | None:
    """
    Convert a comma-separated keyword query like "baz, foo" into an FTS5
    query string like '"baz" AND "foo"' (order-independent AND match).
    Returns None for an empty/whitespace-only query.
    """
    terms = [t.strip() for t in _TERM_RE.findall(query)]
    terms = [t for t in terms if t]
    if not terms:
        return None
    escaped = [t.replace('"', '""') for t in terms]
    return " AND ".join(f'"{t}"' for t in escaped)


def search(conn: sqlite3.Connection, query: str, limit: int = 60, offset: int = 0) -> list[sqlite3.Row]:
    fts_query = build_fts_query(query)
    if fts_query is None:
        return conn.execute(
            "SELECT * FROM images ORDER BY mtime DESC LIMIT ? OFFSET ?",
            (limit, offset),
        ).fetchall()
    return conn.execute(
        """
        SELECT images.* FROM images_fts
        JOIN images ON images.id = images_fts.rowid
        WHERE images_fts MATCH ?
        ORDER BY images.mtime DESC
        LIMIT ? OFFSET ?
        """,
        (fts_query, limit, offset),
    ).fetchall()


def count_matches(conn: sqlite3.Connection, query: str) -> int:
    fts_query = build_fts_query(query)
    if fts_query is None:
        return conn.execute("SELECT COUNT(*) FROM images").fetchone()[0]
    return conn.execute(
        "SELECT COUNT(*) FROM images_fts WHERE images_fts MATCH ?",
        (fts_query,),
    ).fetchone()[0]


def get_image(conn: sqlite3.Connection, image_id: int) -> sqlite3.Row | None:
    return conn.execute("SELECT * FROM images WHERE id = ?", (image_id,)).fetchone()
