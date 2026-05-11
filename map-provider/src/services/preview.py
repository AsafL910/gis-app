import numpy as np
import rasterio
from fastapi import HTTPException
from fastapi.responses import Response
from rasterio.enums import Resampling
from rasterio.io import MemoryFile

from src.config import DATA_DIR


def normalize_to_uint8(data: np.ndarray) -> np.ndarray:
    array = np.asarray(data)

    if array.ndim == 2:
        array = array[np.newaxis, ...]

    if array.shape[0] == 1:
        array = np.repeat(array, 3, axis=0)
    elif array.shape[0] > 3:
        array = array[:3]

    result = np.zeros_like(array, dtype=np.uint8)
    for idx in range(array.shape[0]):
        band = array[idx].astype(np.float32)
        finite = np.isfinite(band)
        if not finite.any():
            continue

        values = band[finite]
        low = float(np.percentile(values, 2))
        high = float(np.percentile(values, 98))
        if high <= low:
            low = float(values.min())
            high = float(values.max())

        if high <= low:
            continue

        scaled = np.clip((band - low) / (high - low), 0.0, 1.0) * 255.0
        result[idx] = scaled.astype(np.uint8)

    return result


def preview_layer(filename: str, max_size: int = 1600) -> Response:
    path = DATA_DIR / filename
    if not path.exists():
        raise HTTPException(status_code=404, detail=f"File {filename} not found")

    max_size = max(128, min(max_size, 2400))

    with rasterio.open(path) as src:
        scale = min(1.0, max_size / max(src.width, src.height))
        out_width = max(1, int(src.width * scale))
        out_height = max(1, int(src.height * scale))
        band_indexes = [1, 2, 3] if src.count >= 3 else [1]
        raster = src.read(
            band_indexes,
            out_shape=(len(band_indexes), out_height, out_width),
            resampling=Resampling.bilinear,
        )

    rgb = normalize_to_uint8(raster)

    with MemoryFile() as memfile:
        with memfile.open(
            driver="PNG",
            width=rgb.shape[2],
            height=rgb.shape[1],
            count=rgb.shape[0],
            dtype="uint8",
        ) as dst:
            dst.write(rgb)
        return Response(content=memfile.read(), media_type="image/png")
