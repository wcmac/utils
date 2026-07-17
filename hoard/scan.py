"""Walk a directory tree, extract SD metadata from images, and index into SQLite."""

from __future__ import annotations

import sys
import time
from pathlib import Path

from PIL import Image

from hoard import db
from hoard.parse import parse_parameters

IMAGE_EXTENSIONS = {".png", ".jpg", ".jpeg"}


def find_images(root: Path):
    for path in root.rglob("*"):
        if path.is_file() and path.suffix.lower() in IMAGE_EXTENSIONS:
            yield path


def extract_parameters_text(path: Path) -> str | None:
    """Read the raw SD parameters blob from a PNG tEXt chunk or JPEG EXIF UserComment."""
    with Image.open(path) as im:
        if path.suffix.lower() == ".png":
            text = im.info.get("parameters")
            if text is None:
                # Pillow only parses PNG chunks before IDAT during Image.open()
                # alone. Some tools write "parameters" after IDAT, which only
                # shows up once the image is fully decoded via im.load() — a
                # ~10x more expensive call, so only pay for it as a fallback
                # when the (much more common) fast path finds nothing.
                im.load()
                text = im.info.get("parameters")
            return text

        exif = im.getexif()
        raw = exif.get(0x9286)  # UserComment
        if not raw:
            return None
        if isinstance(raw, bytes):
            # EXIF UserComment is prefixed with an 8-byte character-code header.
            raw = raw[8:] if len(raw) > 8 else raw
            for enc in ("utf-16-be", "utf-16-le", "utf-8", "ascii"):
                try:
                    return raw.decode(enc).strip("\x00").strip()
                except (UnicodeDecodeError, UnicodeError):
                    continue
            return None
        return str(raw)


def scan_directory(root: str, rescan: bool = False, progress: bool = True) -> dict:
    root_path = Path(root).expanduser().resolve()
    conn = db.connect()

    indexed = 0
    skipped = 0
    failed = 0
    empty_prompt = 0
    seen_paths = set()

    paths = list(find_images(root_path))
    total = len(paths)
    is_tty = sys.stderr.isatty()
    last_report = 0.0

    for i, path in enumerate(paths, 1):
        path_str = str(path)
        seen_paths.add(path_str)
        stat = path.stat()

        if not rescan:
            existing = db.get_indexed_file(conn, path_str)
            if existing and existing["mtime"] == stat.st_mtime and existing["size"] == stat.st_size:
                skipped += 1
                continue

        try:
            with Image.open(path) as im:
                width, height = im.size

            params_text = extract_parameters_text(path)
            parsed = parse_parameters(params_text) if params_text else {
                "positive_prompt": "",
                "negative_prompt": "",
                "params": {},
                "raw": "",
            }
            p = parsed["params"]

            record = {
                "path": path_str,
                "filename": path.name,
                "mtime": stat.st_mtime,
                "size": stat.st_size,
                "width": width,
                "height": height,
                "positive_prompt": parsed["positive_prompt"],
                "negative_prompt": parsed["negative_prompt"],
                "model": p.get("Model"),
                "sampler": p.get("Sampler"),
                "seed": p.get("Seed"),
                "steps": int(p["Steps"]) if p.get("Steps", "").isdigit() else None,
                "cfg_scale": _to_float(p.get("CFG scale")),
                "raw_params": parsed["raw"],
                "indexed_at": time.time(),
            }
            db.upsert_image(conn, record)
            indexed += 1
            if not record["positive_prompt"] and not record["negative_prompt"]:
                empty_prompt += 1
        except Exception:
            failed += 1

        if progress and total:
            now = time.monotonic()
            if now - last_report >= 0.5 or i == total:
                last_report = now
                msg = f"Scanning: {i}/{total} ({indexed} indexed, {skipped} unchanged, {failed} failed)"
                end = "\n" if (not is_tty or i == total) else ""
                print(f"\r{msg}" if is_tty else msg, end=end, file=sys.stderr, flush=True)

    removed = db.delete_missing_under(conn, str(root_path), seen_paths)
    conn.commit()
    conn.close()

    db.set_last_scanned_dir(str(root_path))

    return {
        "indexed": indexed,
        "skipped": skipped,
        "failed": failed,
        "removed": removed,
        "empty_prompt": empty_prompt,
    }


def _to_float(value):
    if value is None:
        return None
    try:
        return float(value)
    except ValueError:
        return None
