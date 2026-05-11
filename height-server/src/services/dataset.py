import math
import struct
from pathlib import Path

from osgeo import gdal, osr

from src.config import BOTTOM_FILENAME, DATA_DIR, DEFAULT_VRT_NAME, DTM_DIR, ELEV_FILENAME, TOP_FILENAME


class DatasetContext:
    def __init__(self) -> None:
        self.path: str | None = None
        self.dataset = None
        self.band = None
        self.geotransform = None
        self.inverse_geotransform = None
        self.projection_wkt = None
        self.coord_transform = None
        self.inverse_coord_transform = None
        self.no_data_value = None


CTX = DatasetContext()

GDAL_STRUCT_FORMATS = {
    gdal.GDT_Byte: "B",
    gdal.GDT_Int16: "h",
    gdal.GDT_UInt16: "H",
    gdal.GDT_Int32: "i",
    gdal.GDT_UInt32: "I",
    gdal.GDT_Float32: "f",
    gdal.GDT_Float64: "d",
}


def ensure_data_dirs() -> None:
    DTM_DIR.mkdir(parents=True, exist_ok=True)


def relative_to_data(path: Path) -> str:
    return path.resolve().relative_to(DATA_DIR.resolve()).as_posix()


def resolve_relative_input(path_str: str, allowed_root: Path) -> Path:
    candidate = (DATA_DIR / path_str).resolve()
    root = allowed_root.resolve()
    if not str(candidate).startswith(str(root)):
        raise ValueError(f"Path is outside allowed root: {path_str}")
    if not candidate.exists():
        raise ValueError(f"File not found: {path_str}")
    return candidate


def build_default_vrt() -> Path:
    vrt_path = DTM_DIR / DEFAULT_VRT_NAME
    sources = [DTM_DIR / TOP_FILENAME, DTM_DIR / BOTTOM_FILENAME]

    missing = [str(path.name) for path in sources if not path.exists()]
    if missing:
        raise RuntimeError(
            f"Cannot build VRT because source files are missing: {', '.join(missing)}"
        )

    vrt = gdal.BuildVRT(str(vrt_path), [str(path) for path in sources])
    if vrt is None:
        raise RuntimeError(f"GDAL failed to build VRT at {vrt_path}")
    vrt.FlushCache()
    vrt = None
    return vrt_path


def resolve_dataset_path(dataset_path: str | None = None) -> Path:
    requested_path = (
        resolve_relative_input(dataset_path, DATA_DIR)
        if dataset_path
        else (DATA_DIR / ELEV_FILENAME)
    )
    if requested_path.exists():
        return requested_path

    if requested_path.suffix.lower() == ".vrt":
        return build_default_vrt()

    raise RuntimeError(f"Elevation dataset not found: {requested_path}")


def load_dataset(dataset_path: str | None = None) -> None:
    resolved_dataset_path = resolve_dataset_path(dataset_path)
    if CTX.dataset is not None and CTX.path == str(resolved_dataset_path):
        return

    dataset = gdal.Open(str(resolved_dataset_path))
    if dataset is None:
        raise RuntimeError(f"Failed to open elevation dataset at {resolved_dataset_path}")

    band = dataset.GetRasterBand(1)
    geotransform = dataset.GetGeoTransform()
    inverse_result = gdal.InvGeoTransform(geotransform)
    if inverse_result is None:
        raise RuntimeError("Failed to invert dataset geotransform")

    if isinstance(inverse_result, tuple) and len(inverse_result) == 2:
        success, inverse_geotransform = inverse_result
        if not success:
            raise RuntimeError("Failed to invert dataset geotransform")
    else:
        inverse_geotransform = inverse_result

    projection_wkt = dataset.GetProjection()
    coord_transform = None
    inverse_coord_transform = None
    if projection_wkt:
        src_ref = osr.SpatialReference()
        src_ref.ImportFromEPSG(4326)
        dst_ref = osr.SpatialReference()
        dst_ref.ImportFromWkt(projection_wkt)
        coord_transform = osr.CoordinateTransformation(src_ref, dst_ref)
        inverse_coord_transform = osr.CoordinateTransformation(dst_ref, src_ref)

    CTX.path = str(resolved_dataset_path)
    CTX.dataset = dataset
    CTX.band = band
    CTX.geotransform = geotransform
    CTX.inverse_geotransform = inverse_geotransform
    CTX.projection_wkt = projection_wkt
    CTX.coord_transform = coord_transform
    CTX.inverse_coord_transform = inverse_coord_transform
    CTX.no_data_value = band.GetNoDataValue()


def ensure_dataset_loaded(dataset_path: str | None = None) -> None:
    requested_dataset_path = resolve_dataset_path(dataset_path)
    if CTX.dataset is None or CTX.path != str(requested_dataset_path):
        load_dataset(dataset_path)


def project_lonlat_to_dataset(lon: float, lat: float, dataset_path: str | None = None) -> tuple[float, float]:
    ensure_dataset_loaded(dataset_path)
    if CTX.coord_transform is None:
        return lon, lat

    x, y, _ = CTX.coord_transform.TransformPoint(lon, lat)
    return x, y


def latlon_to_pixel(lat: float, lon: float, dataset_path: str | None = None) -> tuple[int, int]:
    dataset_x, dataset_y = project_lonlat_to_dataset(lon, lat, dataset_path)
    pixel_x, pixel_y = gdal.ApplyGeoTransform(
        CTX.inverse_geotransform, dataset_x, dataset_y
    )
    return int(math.floor(pixel_x)), int(math.floor(pixel_y))


def pixel_to_dataset_coords(pixel_x: int, pixel_y: int) -> tuple[float, float]:
    return gdal.ApplyGeoTransform(CTX.geotransform, pixel_x + 0.5, pixel_y + 0.5)


def dataset_to_lonlat(dataset_x: float, dataset_y: float, dataset_path: str | None = None) -> tuple[float, float]:
    ensure_dataset_loaded(dataset_path)
    if CTX.inverse_coord_transform is None:
        return dataset_x, dataset_y

    lon, lat, _ = CTX.inverse_coord_transform.TransformPoint(dataset_x, dataset_y)
    return lon, lat


def read_band_values(
    pixel_x: int, pixel_y: int, width: int, height: int = 1, dataset_path: str | None = None
) -> list[float]:
    ensure_dataset_loaded(dataset_path)
    fmt = GDAL_STRUCT_FORMATS.get(CTX.band.DataType)
    if fmt is None:
        raise RuntimeError(f"Unsupported GDAL band type: {CTX.band.DataType}")

    raw = CTX.band.ReadRaster(pixel_x, pixel_y, width, height)
    if raw is None:
        raise RuntimeError("GDAL raster read failed")

    count = width * height
    values = struct.unpack(f"{count}{fmt}", raw)
    return [float(value) for value in values]
