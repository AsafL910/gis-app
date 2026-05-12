import json
import os
import re
from dataclasses import dataclass
from pathlib import Path


DATA_DIR = Path(os.environ.get("DATA_DIR", str(Path(__file__).resolve().parents[2] / "data"))).resolve()
WMTS_TILE_MATRIX_SET = "WebMercatorQuad"
WMTS_TILE_SIZE = 256


@dataclass(frozen=True)
class GeoPackageLayerConfig:
    identifier: str
    title: str
    relative_path: str


def resolve_data_path(relative_path: str) -> Path:
    path = (DATA_DIR / relative_path).resolve()
    if not str(path).startswith(str(DATA_DIR)):
        raise ValueError(f"Path {relative_path} is outside DATA_DIR")
    return path


def _make_identifier(value: str) -> str:
    slug = re.sub(r"[^a-zA-Z0-9_-]+", "-", value.strip().replace("\\", "/")).strip("-").lower()
    return slug or "layer"


def _parse_json_layer_entries(raw: str) -> list[dict[str, str]]:
    loaded = json.loads(raw)
    if not isinstance(loaded, list):
        raise ValueError("WMTS_GPKG_LAYERS must be a JSON list")

    entries: list[dict[str, str]] = []
    for item in loaded:
        if isinstance(item, str):
            entries.append({"path": item})
            continue
        if isinstance(item, dict) and isinstance(item.get("path"), str):
            entries.append(
                {
                    "path": item["path"],
                    "name": str(item.get("name") or "").strip(),
                    "title": str(item.get("title") or "").strip(),
                }
            )
            continue
        raise ValueError("WMTS_GPKG_LAYERS entries must be strings or objects with a path field")
    return entries


def _parse_delimited_layer_entries(raw: str) -> list[dict[str, str]]:
    separators = raw.replace(";", "\n").replace(",", "\n")
    entries: list[dict[str, str]] = []
    for part in separators.splitlines():
        path = part.strip()
        if path:
            entries.append({"path": path})
    return entries


def load_wmts_gpkg_layers() -> list[GeoPackageLayerConfig]:
    raw = os.environ.get("WMTS_GPKG_LAYERS", "").strip()
    fallback = os.environ.get("WMTS_GPKG_LIST", "").strip()

    if raw:
        entries = _parse_json_layer_entries(raw)
    elif fallback:
        entries = _parse_delimited_layer_entries(fallback)
    else:
        entries = [
            {"path": str(path.relative_to(DATA_DIR)).replace("\\", "/")}
            for path in sorted(DATA_DIR.rglob("*.gpkg"))
            if path.is_file()
        ]

    configs: list[GeoPackageLayerConfig] = []
    used_identifiers: set[str] = set()

    for entry in entries:
        relative_path = entry["path"].replace("\\", "/").lstrip("/")
        path = resolve_data_path(relative_path)
        if not path.exists() or not path.is_file():
            continue

        title = entry.get("title") or entry.get("name") or path.stem
        base_identifier = _make_identifier(entry.get("name") or path.stem)
        identifier = base_identifier
        suffix = 2
        while identifier in used_identifiers:
            identifier = f"{base_identifier}-{suffix}"
            suffix += 1
        used_identifiers.add(identifier)

        configs.append(
            GeoPackageLayerConfig(
                identifier=identifier,
                title=title,
                relative_path=relative_path,
            )
        )

    return configs
