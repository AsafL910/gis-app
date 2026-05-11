from osgeo import ogr, gdal

from src.models.requests import Coordinates
from src.services.dataset import (
    CTX,
    dataset_to_lonlat,
    ensure_dataset_loaded,
    latlon_to_pixel,
    pixel_to_dataset_coords,
    project_lonlat_to_dataset,
    read_band_values,
)


def build_polygon_in_dataset_srs(polygon_coords: list[Coordinates], dataset_path: str | None = None):
    ring = ogr.Geometry(ogr.wkbLinearRing)
    for coord in polygon_coords:
        dataset_x, dataset_y = project_lonlat_to_dataset(
            coord.longitude, coord.latitude, dataset_path
        )
        ring.AddPoint(dataset_x, dataset_y)
    ring.CloseRings()

    polygon = ogr.Geometry(ogr.wkbPolygon)
    polygon.AddGeometry(ring)
    return polygon


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

    value = read_band_values(pixel_x, pixel_y, 1, dataset_path=dataset_path)[0]
    if CTX.no_data_value is not None and value == CTX.no_data_value:
        raise ValueError("Coordinate falls on nodata")

    return int(value)


def get_highest_point(polygon_coords: list[Coordinates], dataset_path: str | None = None):
    ensure_dataset_loaded(dataset_path)
    polygon = build_polygon_in_dataset_srs(polygon_coords, dataset_path)
    min_x, max_x, min_y, max_y = polygon.GetEnvelope()

    top_left_x, top_left_y = gdal.ApplyGeoTransform(
        CTX.inverse_geotransform, min_x, max_y
    )
    bottom_right_x, bottom_right_y = gdal.ApplyGeoTransform(
        CTX.inverse_geotransform, max_x, min_y
    )

    start_x = max(0, int(min(top_left_x, bottom_right_x)))
    end_x = min(
        CTX.dataset.RasterXSize - 1, int(max(top_left_x, bottom_right_x) + 1)
    )
    start_y = max(0, int(min(top_left_y, bottom_right_y)))
    end_y = min(
        CTX.dataset.RasterYSize - 1, int(max(top_left_y, bottom_right_y) + 1)
    )

    if start_x > end_x or start_y > end_y:
        raise ValueError("Polygon is outside the elevation dataset")

    highest_elevation = float("-inf")
    highest_coord = None

    for pixel_y in range(start_y, end_y + 1):
        row = read_band_values(
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


def extract_polygon_coordinates_from_geojson(payload: dict) -> list[Coordinates]:
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
