import math
import os
import struct
from pathlib import Path

from fastapi import APIRouter, HTTPException
from osgeo import gdal, ogr, osr
from pydantic import BaseModel

router = APIRouter(tags=["Elevation Calculation"])

DATA_DIR = Path(os.environ.get("DATA_DIR", str(Path(__file__).resolve().parent.parent / "data")))
DTM_DIRNAME = os.environ.get("DTM_DIRNAME", "dtm")
DTM_DIR = DATA_DIR / DTM_DIRNAME
ELEV_FILENAME = os.environ.get("ELEV_FILENAME", f"{DTM_DIRNAME}/israel_merged.vrt")
DEFAULT_VRT_NAME = os.environ.get("ELEV_VRT_FILENAME", "israel_merged.vrt")
TOP_FILENAME = os.environ.get("TOP_ELEV_FILENAME", "israel_top_cog.tif")
BOTTOM_FILENAME = os.environ.get("BOTTOM_ELEV_FILENAME", "israel_bottom_cog.tif")


class Coordinates(BaseModel):
    latitude: float
    longitude: float


class ElevationRequest(Coordinates):
    dataset_path: str | None = None


class Polygon(BaseModel):
    coordinates: list[Coordinates]


class PolygonRequest(BaseModel):
    coordinates: list[Coordinates]
    dataset_path: str | None = None


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


def _build_default_vrt() -> Path:
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


def _resolve_dataset_path(dataset_path: str | None = None) -> Path:
    requested_path = (
        _resolve_relative_input(dataset_path, DATA_DIR)
        if dataset_path
        else (DATA_DIR / ELEV_FILENAME)
    )
    if requested_path.exists():
        return requested_path

    if requested_path.suffix.lower() == ".vrt":
        return _build_default_vrt()

    raise RuntimeError(f"Elevation dataset not found: {requested_path}")


def _ensure_data_dirs() -> None:
    DTM_DIR.mkdir(parents=True, exist_ok=True)


def _relative_to_data(path: Path) -> str:
    return path.resolve().relative_to(DATA_DIR.resolve()).as_posix()


def _resolve_relative_input(path_str: str, allowed_root: Path) -> Path:
    candidate = (DATA_DIR / path_str).resolve()
    root = allowed_root.resolve()
    if not str(candidate).startswith(str(root)):
        raise ValueError(f"Path is outside allowed root: {path_str}")
    if not candidate.exists():
        raise ValueError(f"File not found: {path_str}")
    return candidate


def load_dataset(dataset_path: str | None = None) -> None:
    resolved_dataset_path = _resolve_dataset_path(dataset_path)
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
    requested_dataset_path = _resolve_dataset_path(dataset_path)
    if CTX.dataset is None or CTX.path != str(requested_dataset_path):
        load_dataset(dataset_path)


def _project_lonlat_to_dataset(lon: float, lat: float, dataset_path: str | None = None) -> tuple[float, float]:
    ensure_dataset_loaded(dataset_path)
    if CTX.coord_transform is None:
        return lon, lat

    x, y, _ = CTX.coord_transform.TransformPoint(lon, lat)
    return x, y


def latlon_to_pixel(lat: float, lon: float, dataset_path: str | None = None) -> tuple[int, int]:
    dataset_x, dataset_y = _project_lonlat_to_dataset(lon, lat, dataset_path)
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


def _build_polygon_in_dataset_srs(polygon_coords: list[Coordinates], dataset_path: str | None = None):
    ring = ogr.Geometry(ogr.wkbLinearRing)
    for coord in polygon_coords:
        dataset_x, dataset_y = _project_lonlat_to_dataset(
            coord.longitude, coord.latitude, dataset_path
        )
        ring.AddPoint(dataset_x, dataset_y)
    ring.CloseRings()

    polygon = ogr.Geometry(ogr.wkbPolygon)
    polygon.AddGeometry(ring)
    return polygon


def _read_band_values(
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


def get_elevation(lat: float, lon: float, dataset_path: str | None = None) -> int:
    ensure_dataset_loaded(dataset_path)
    pixel_x, pixel_y = latlon_to_pixel(lat, lon, dataset_path)

    if (
        pixel_x < 0
        or pixel_y < 0
        or pixel_x >= CTX.dataset.RasterXSize
        or pixel_y >= CTX.dataset.RasterYSize
    ):
        raise ValueError("Coordinate is outside the elevation dataset")

    value = _read_band_values(pixel_x, pixel_y, 1, dataset_path=dataset_path)[0]
    if CTX.no_data_value is not None and value == CTX.no_data_value:
        raise ValueError("Coordinate falls on nodata")

    return int(value)


def get_highest_point(polygon_coords: list[Coordinates], dataset_path: str | None = None):
    ensure_dataset_loaded(dataset_path)
    polygon = _build_polygon_in_dataset_srs(polygon_coords, dataset_path)
    min_x, max_x, min_y, max_y = polygon.GetEnvelope()

    top_left_x, top_left_y = gdal.ApplyGeoTransform(
        CTX.inverse_geotransform, min_x, max_y
    )
    bottom_right_x, bottom_right_y = gdal.ApplyGeoTransform(
        CTX.inverse_geotransform, max_x, min_y
    )

    start_x = max(0, int(math.floor(min(top_left_x, bottom_right_x))))
    end_x = min(
        CTX.dataset.RasterXSize - 1, int(math.ceil(max(top_left_x, bottom_right_x)))
    )
    start_y = max(0, int(math.floor(min(top_left_y, bottom_right_y))))
    end_y = min(
        CTX.dataset.RasterYSize - 1, int(math.ceil(max(top_left_y, bottom_right_y)))
    )

    if start_x > end_x or start_y > end_y:
        raise ValueError("Polygon is outside the elevation dataset")

    highest_elevation = float("-inf")
    highest_coord = None

    for pixel_y in range(start_y, end_y + 1):
        row = _read_band_values(
            start_x, pixel_y, end_x - start_x + 1, dataset_path=dataset_path
        )
        for offset_x, value in enumerate(row):
            if CTX.no_data_value is not None and value == CTX.no_data_value:
                continue

            pixel_x = start_x + offset_x
            dataset_x, dataset_y = pixel_to_dataset_coords(pixel_x, pixel_y)
            point = ogr.Geometry(ogr.wkbPoint)
            point.AddPoint(dataset_x, dataset_y)

            if polygon.Contains(point) and value > highest_elevation:
                highest_elevation = float(value)
                lon, lat = dataset_to_lonlat(dataset_x, dataset_y, dataset_path)
                highest_coord = {"latitude": lat, "longitude": lon}

    if highest_coord is None:
        raise ValueError("No valid elevation found within the polygon")

    return {
        "highest_elevation": int(highest_elevation),
        "coordinate": highest_coord,
        "dataset_path": CTX.path,
    }


def _extract_polygon_coordinates_from_geojson(payload: dict) -> list[Coordinates]:
    geojson_type = payload.get("type")

    geometry = payload
    if geojson_type == "Feature":
        geometry = payload.get("geometry") or {}
        geojson_type = geometry.get("type")
    elif geojson_type == "FeatureCollection":
        features = payload.get("features") or []
        if not features:
            raise ValueError("FeatureCollection is empty")
        geometry = (features[0] or {}).get("geometry") or {}
        geojson_type = geometry.get("type")

    if geojson_type != "Polygon":
        raise ValueError("GeoJSON must be a Polygon, Feature<Polygon>, or FeatureCollection")

    coordinates = geometry.get("coordinates")
    if not isinstance(coordinates, list) or not coordinates or not isinstance(coordinates[0], list):
        raise ValueError("Polygon coordinates are missing or invalid")

    outer_ring = coordinates[0]
    if len(outer_ring) < 4:
        raise ValueError("Polygon outer ring must contain at least 4 positions")

    return [
        Coordinates(latitude=float(lat), longitude=float(lon))
        for lon, lat, *_ in outer_ring
    ]


@router.on_event("startup")
def startup_load_dataset():
    try:
        _ensure_data_dirs()
        load_dataset()
        print(f"Loaded elevation dataset from {CTX.path}")
    except Exception as exc:
        print(f"Warning: failed to load elevation dataset: {exc}")


@router.get("/dataset-info/")
def dataset_info(dataset_path: str | None = None):
    try:
        ensure_dataset_loaded(dataset_path)
        return {
            "dataset_path": CTX.path,
            "raster_size": [CTX.dataset.RasterXSize, CTX.dataset.RasterYSize],
            "projection": CTX.projection_wkt,
            "geotransform": CTX.geotransform,
            "nodata": CTX.no_data_value,
        }
    except Exception as exc:
        raise HTTPException(status_code=500, detail=str(exc))


@router.post("/reload-dataset/")
def reload_dataset(payload: dict | None = None):
    try:
        dataset_path = payload.get("dataset_path") if isinstance(payload, dict) else None
        if dataset_path is not None and not isinstance(dataset_path, str):
            raise ValueError("Expected 'dataset_path' to be a string when provided")
        load_dataset(dataset_path)
        return {"dataset_path": CTX.path, "status": "reloaded"}
    except Exception as exc:
        raise HTTPException(status_code=500, detail=str(exc))


@router.post("/get-elevation/")
def get_elevation_controller(request: ElevationRequest):
    try:
        elevation = get_elevation(
            request.latitude, request.longitude, request.dataset_path
        )
        return {
            "latitude": request.latitude,
            "longitude": request.longitude,
            "elevation": elevation,
            "dataset_path": CTX.path,
        }
    except Exception as exc:
        raise HTTPException(status_code=400, detail=str(exc))


@router.post("/get-highest-point/")
def get_highest_point_controller(request: PolygonRequest):
    try:
        return get_highest_point(request.coordinates, request.dataset_path)
    except Exception as exc:
        raise HTTPException(status_code=400, detail=str(exc))


@router.post("/get-highest-point-geojson/")
def get_highest_point_geojson_controller(payload: dict):
    try:
        dataset_path = payload.get("dataset_path")
        if dataset_path is not None and not isinstance(dataset_path, str):
            raise ValueError("Expected 'dataset_path' to be a string when provided")

        geometry_payload = payload.get("geojson") if isinstance(payload.get("geojson"), dict) else payload
        polygon_coords = _extract_polygon_coordinates_from_geojson(geometry_payload)
        result = get_highest_point(polygon_coords, dataset_path)
        point_lon = result["coordinate"]["longitude"]
        point_lat = result["coordinate"]["latitude"]

        return {
            "type": "FeatureCollection",
            "features": [
                {
                    "type": "Feature",
                    "geometry": {
                        "type": "Point",
                        "coordinates": [point_lon, point_lat],
                    },
                    "properties": {
                        "highest_elevation": result["highest_elevation"],
                        "dataset_path": result["dataset_path"],
                    },
                }
            ],
            "input_geojson": geometry_payload,
            "highest_elevation": result["highest_elevation"],
            "dataset_path": result["dataset_path"],
        }
    except Exception as exc:
        raise HTTPException(status_code=400, detail=str(exc))
