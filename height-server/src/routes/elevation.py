from fastapi import APIRouter, HTTPException

from src.models.requests import ElevationRequest, PolygonRequest
from src.services.dataset import CTX, ensure_data_dirs, ensure_dataset_loaded, load_dataset
from src.services.elevation import extract_polygon_coordinates_from_geojson, get_elevation, get_highest_point


router = APIRouter(tags=["Elevation Calculation"])


@router.on_event("startup")
def startup_load_dataset():
    try:
        ensure_data_dirs()
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
        polygon_coords = extract_polygon_coordinates_from_geojson(geometry_payload)
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
