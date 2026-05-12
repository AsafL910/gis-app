from pathlib import Path
from urllib.parse import quote

from fastapi import HTTPException

from src.config import DATA_DIR, WMTS_TILE_MATRIX_SET, resolve_data_path
from src.services.wmts import WMTS_MATRIX_SET, list_wmts_layers


def get_available_cogs() -> list[str]:
    paths = [
        *DATA_DIR.rglob("*.tif"),
        *DATA_DIR.rglob("*.tiff"),
        *DATA_DIR.rglob("*.vrt"),
    ]
    return sorted(
        str(path.resolve().relative_to(DATA_DIR.resolve())).replace("\\", "/")
        for path in paths
        if path.is_file()
    )


def get_tif_url(relative_path: str) -> str:
    path = resolve_data_path(relative_path)
    if not path.exists():
        raise HTTPException(status_code=404, detail=f"File {relative_path} not found")
    # TiTiler/Rasterio on Windows handles direct filesystem paths more reliably
    # than file:/// URLs with drive letters and spaces.
    return str(path)


def list_layers_payload() -> dict:
    raster_layers = [
        {
            "name": Path(cog_name).name,
            "path": cog_name,
            "url": get_tif_url(cog_name),
            "provider": "cog",
            "tile_url": f"/cog/tiles/{WMTS_TILE_MATRIX_SET}/{{z}}/{{x}}/{{y}}.png?url={quote(get_tif_url(cog_name), safe='')}",
            "source_modes": ["proxy", "direct"],
        }
        for cog_name in get_available_cogs()
    ]

    wmts_layers = [
        {
            "name": layer.title,
            "path": layer.relative_path,
            "url": str(resolve_data_path(layer.relative_path)),
            "provider": "wmts",
            "identifier": layer.identifier,
            "tile_url": f"/wmts/{quote(layer.identifier, safe='')}/{WMTS_MATRIX_SET}/{{z}}/{{y}}/{{x}}.png",
            "capabilities_url": "/wmts/1.0.0/WMTSCapabilities.xml",
            "demo_url": "/wmts/demo",
            "source_modes": ["proxy"],
            "bounds": {
                "epsg4326": layer.bounds_4326,
            },
        }
        for layer in list_wmts_layers()
    ]

    return {"layers": [*raster_layers, *wmts_layers]}
