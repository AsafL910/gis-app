from pathlib import Path

from fastapi import HTTPException

from src.config import DATA_DIR


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
    path = (DATA_DIR / relative_path).resolve()
    if not str(path).startswith(str(DATA_DIR.resolve())) or not path.exists():
        raise HTTPException(status_code=404, detail=f"File {relative_path} not found")
    return "file:///" + str(path).replace("\\", "/")


def list_layers_payload() -> dict:
    return {
        "layers": [
            {
                "name": Path(cog_name).name,
                "path": cog_name,
                "url": get_tif_url(cog_name),
            }
            for cog_name in get_available_cogs()
        ]
    }
