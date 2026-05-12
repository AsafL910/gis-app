from dataclasses import dataclass
from functools import lru_cache
from pathlib import Path
from urllib.parse import quote
from xml.etree.ElementTree import Element, SubElement, register_namespace, tostring

import numpy as np
import rasterio
from fastapi import HTTPException
from rasterio.crs import CRS
from rasterio.enums import Resampling
from rasterio.io import MemoryFile
from rasterio.windows import from_bounds as window_from_bounds

from src.config import WMTS_TILE_SIZE, GeoPackageLayerConfig, load_wmts_gpkg_layers, resolve_data_path
from src.services.preview import normalize_to_uint8


WGS84_CRS = CRS.from_epsg(4326)
WGS84 = "EPSG:4326"
WMTS_MATRIX_SET = "EPSG4326"
WORLD_MIN_X = -180.0
WORLD_MAX_X = 180.0
WORLD_MIN_Y = -90.0
WORLD_MAX_Y = 90.0
WORLD_WIDTH = WORLD_MAX_X - WORLD_MIN_X
WORLD_HEIGHT = WORLD_MAX_Y - WORLD_MIN_Y
INITIAL_RESOLUTION = WORLD_HEIGHT / WMTS_TILE_SIZE
OGC_PIXEL_SIZE = 0.00028


@dataclass(frozen=True)
class WmtsLayerMetadata:
    identifier: str
    title: str
    relative_path: str
    absolute_path: Path
    bounds_4326: tuple[float, float, float, float]
    band_count: int


@dataclass(frozen=True)
class SkippedLayer:
    identifier: str
    title: str
    relative_path: str
    reason: str


def get_wmts_layer_configs() -> list[GeoPackageLayerConfig]:
    return load_wmts_gpkg_layers()


@lru_cache(maxsize=32)
def _inspect_layer(config: GeoPackageLayerConfig) -> WmtsLayerMetadata | SkippedLayer:
    absolute_path = resolve_data_path(config.relative_path)
    with rasterio.open(absolute_path) as src:
        if src.crs != WGS84_CRS:
            return SkippedLayer(
                identifier=config.identifier,
                title=config.title,
                relative_path=config.relative_path,
                reason=f"Expected EPSG:4326 source but found {src.crs or 'unknown CRS'}",
            )

        left, bottom, right, top = src.bounds
        return WmtsLayerMetadata(
            identifier=config.identifier,
            title=config.title,
            relative_path=config.relative_path,
            absolute_path=absolute_path,
            bounds_4326=(left, bottom, right, top),
            band_count=src.count,
        )


def list_wmts_layers() -> list[WmtsLayerMetadata]:
    layers: list[WmtsLayerMetadata] = []
    for config in get_wmts_layer_configs():
        result = _inspect_layer(config)
        if isinstance(result, WmtsLayerMetadata):
            layers.append(result)
    return layers


def list_skipped_wmts_layers() -> list[SkippedLayer]:
    skipped: list[SkippedLayer] = []
    for config in get_wmts_layer_configs():
        result = _inspect_layer(config)
        if isinstance(result, SkippedLayer):
            skipped.append(result)
    return skipped


def get_wmts_layer(identifier: str) -> WmtsLayerMetadata:
    for layer in list_wmts_layers():
        if layer.identifier == identifier:
            return layer
    raise HTTPException(status_code=404, detail=f"WMTS layer {identifier} was not found")


def _matrix_dimensions(tile_matrix: int) -> tuple[int, int]:
    return 2 ** (tile_matrix + 1), 2**tile_matrix


def _tile_bounds(tile_matrix: int, tile_row: int, tile_col: int) -> tuple[float, float, float, float]:
    matrix_width, matrix_height = _matrix_dimensions(tile_matrix)
    if tile_col < 0 or tile_row < 0 or tile_col >= matrix_width or tile_row >= matrix_height:
        raise HTTPException(status_code=404, detail="Requested tile is outside the WMTS matrix")

    tile_span_x = WORLD_WIDTH / matrix_width
    tile_span_y = WORLD_HEIGHT / matrix_height
    min_x = WORLD_MIN_X + tile_col * tile_span_x
    max_x = min_x + tile_span_x
    max_y = WORLD_MAX_Y - tile_row * tile_span_y
    min_y = max_y - tile_span_y
    return min_x, min_y, max_x, max_y


def _intersects_bounds(
    left_a: float,
    bottom_a: float,
    right_a: float,
    top_a: float,
    left_b: float,
    bottom_b: float,
    right_b: float,
    top_b: float,
) -> bool:
    return not (
        right_a <= left_b
        or right_b <= left_a
        or top_a <= bottom_b
        or top_b <= bottom_a
    )


def _prepare_png_bands(data: np.ndarray, alpha: np.ndarray | None) -> np.ndarray:
    array = np.asarray(data)
    if array.ndim == 2:
        array = array[np.newaxis, ...]

    band_count = array.shape[0]
    if band_count == 0:
        array = np.zeros((3, WMTS_TILE_SIZE, WMTS_TILE_SIZE), dtype=np.uint8)
    elif band_count == 1:
        array = normalize_to_uint8(array)
    elif band_count == 2:
        grayscale = normalize_to_uint8(array[:1])
        array = np.concatenate([grayscale, array[1:2].astype(np.uint8)], axis=0)
    elif band_count in {3, 4} and array.dtype == np.uint8:
        array = array[:band_count]
    else:
        core = normalize_to_uint8(array[: min(3, band_count)])
        if band_count >= 4:
            alpha_band = array[3:4].astype(np.uint8)
            array = np.concatenate([core, alpha_band], axis=0)
        else:
            array = core

    if alpha is not None:
        alpha_uint8 = alpha.astype(np.uint8)[np.newaxis, ...]
        if array.shape[0] == 4:
            array[3] = np.minimum(array[3], alpha_uint8[0])
        else:
            array = np.concatenate([array[:3], alpha_uint8], axis=0)

    if array.shape[0] == 2:
        gray = array[:1]
        alpha_band = array[1:2]
        array = np.concatenate([gray, gray, gray, alpha_band], axis=0)

    return array


def _encode_png(data: np.ndarray) -> bytes:
    with MemoryFile() as memfile:
        with memfile.open(
            driver="PNG",
            width=data.shape[2],
            height=data.shape[1],
            count=data.shape[0],
            dtype="uint8",
        ) as dst:
            dst.write(data.astype(np.uint8))
        return memfile.read()


@lru_cache(maxsize=1)
def _blank_png() -> bytes:
    rgba = np.zeros((4, WMTS_TILE_SIZE, WMTS_TILE_SIZE), dtype=np.uint8)
    return _encode_png(rgba)


def render_wmts_tile(identifier: str, tile_matrix_set: str, tile_matrix: int, tile_row: int, tile_col: int) -> bytes:
    if tile_matrix_set != WMTS_MATRIX_SET:
        raise HTTPException(status_code=404, detail=f"Unsupported tile matrix set {tile_matrix_set}")

    layer = get_wmts_layer(identifier)
    min_x, min_y, max_x, max_y = _tile_bounds(tile_matrix, tile_row, tile_col)
    if not _intersects_bounds(min_x, min_y, max_x, max_y, *layer.bounds_4326):
        return _blank_png()

    with rasterio.open(layer.absolute_path) as src:
        band_indexes = list(range(1, min(max(src.count, 1), 4) + 1))
        resampling = Resampling.nearest if src.count >= 4 else Resampling.bilinear
        window = window_from_bounds(min_x, min_y, max_x, max_y, transform=src.transform)
        raster = src.read(
            band_indexes,
            window=window,
            out_shape=(len(band_indexes), WMTS_TILE_SIZE, WMTS_TILE_SIZE),
            boundless=True,
            fill_value=0,
            resampling=resampling,
            masked=True,
        )

    data = raster.filled(0)
    valid_mask = (~np.all(raster.mask, axis=0)).astype(np.uint8) * 255
    png_bands = _prepare_png_bands(data, valid_mask)
    return _encode_png(png_bands)


def build_wmts_capabilities_xml(base_url: str) -> str:
    ns = {
        "wmts": "http://www.opengis.net/wmts/1.0",
        "ows": "http://www.opengis.net/ows/1.1",
        "xlink": "http://www.w3.org/1999/xlink",
    }
    register_namespace("", ns["wmts"])
    register_namespace("ows", ns["ows"])
    register_namespace("xlink", ns["xlink"])

    capabilities = Element("{http://www.opengis.net/wmts/1.0}Capabilities", {"version": "1.0.0"})

    service_identification = SubElement(capabilities, "{http://www.opengis.net/ows/1.1}ServiceIdentification")
    SubElement(service_identification, "{http://www.opengis.net/ows/1.1}Title").text = "GeoPackage WMTS"
    SubElement(service_identification, "{http://www.opengis.net/ows/1.1}Abstract").text = (
        "FastAPI WMTS endpoint for EPSG:4326 GeoPackage rasters without runtime reprojection."
    )
    SubElement(service_identification, "{http://www.opengis.net/ows/1.1}ServiceType").text = "OGC WMTS"
    SubElement(service_identification, "{http://www.opengis.net/ows/1.1}ServiceTypeVersion").text = "1.0.0"

    operations_metadata = SubElement(capabilities, "{http://www.opengis.net/ows/1.1}OperationsMetadata")
    for operation_name in ["GetCapabilities", "GetTile"]:
        operation = SubElement(operations_metadata, "{http://www.opengis.net/ows/1.1}Operation", {"name": operation_name})
        dcp = SubElement(operation, "{http://www.opengis.net/ows/1.1}DCP")
        http = SubElement(dcp, "{http://www.opengis.net/ows/1.1}HTTP")
        get = SubElement(http, "{http://www.opengis.net/ows/1.1}Get", {"{http://www.w3.org/1999/xlink}href": f"{base_url}/wmts"})
        constraint = SubElement(get, "{http://www.opengis.net/ows/1.1}Constraint", {"name": "GetEncoding"})
        allowed_values = SubElement(constraint, "{http://www.opengis.net/ows/1.1}AllowedValues")
        SubElement(allowed_values, "{http://www.opengis.net/ows/1.1}Value").text = "KVP"

    contents = SubElement(capabilities, "{http://www.opengis.net/wmts/1.0}Contents")
    for layer in list_wmts_layers():
        layer_el = SubElement(contents, "{http://www.opengis.net/wmts/1.0}Layer")
        SubElement(layer_el, "{http://www.opengis.net/ows/1.1}Title").text = layer.title
        SubElement(layer_el, "{http://www.opengis.net/ows/1.1}Identifier").text = layer.identifier

        lower_lon, lower_lat, upper_lon, upper_lat = layer.bounds_4326
        wgs84_box = SubElement(layer_el, "{http://www.opengis.net/ows/1.1}WGS84BoundingBox")
        SubElement(wgs84_box, "{http://www.opengis.net/ows/1.1}LowerCorner").text = f"{lower_lon} {lower_lat}"
        SubElement(wgs84_box, "{http://www.opengis.net/ows/1.1}UpperCorner").text = f"{upper_lon} {upper_lat}"

        SubElement(layer_el, "{http://www.opengis.net/wmts/1.0}Style", {"isDefault": "true"})
        style_id = layer_el[-1]
        SubElement(style_id, "{http://www.opengis.net/ows/1.1}Identifier").text = "default"
        SubElement(layer_el, "{http://www.opengis.net/wmts/1.0}Format").text = "image/png"
        SubElement(
            layer_el,
            "{http://www.opengis.net/wmts/1.0}ResourceURL",
            {
                "format": "image/png",
                "resourceType": "tile",
                "template": f"{base_url}/wmts/{quote(layer.identifier, safe='')}/{WMTS_MATRIX_SET}/{{TileMatrix}}/{{TileRow}}/{{TileCol}}.png",
            },
        )
        link = SubElement(layer_el, "{http://www.opengis.net/wmts/1.0}TileMatrixSetLink")
        SubElement(link, "{http://www.opengis.net/wmts/1.0}TileMatrixSet").text = WMTS_MATRIX_SET

    matrix_set = SubElement(contents, "{http://www.opengis.net/wmts/1.0}TileMatrixSet")
    SubElement(matrix_set, "{http://www.opengis.net/ows/1.1}Identifier").text = WMTS_MATRIX_SET
    SubElement(matrix_set, "{http://www.opengis.net/ows/1.1}SupportedCRS").text = "urn:ogc:def:crs:EPSG::4326"

    for zoom in range(0, 23):
        resolution = INITIAL_RESOLUTION / (2**zoom)
        matrix_width, matrix_height = _matrix_dimensions(zoom)
        tile_matrix = SubElement(matrix_set, "{http://www.opengis.net/wmts/1.0}TileMatrix")
        SubElement(tile_matrix, "{http://www.opengis.net/ows/1.1}Identifier").text = str(zoom)
        SubElement(tile_matrix, "{http://www.opengis.net/wmts/1.0}ScaleDenominator").text = str(resolution / OGC_PIXEL_SIZE)
        SubElement(tile_matrix, "{http://www.opengis.net/wmts/1.0}TopLeftCorner").text = f"{WORLD_MIN_X} {WORLD_MAX_Y}"
        SubElement(tile_matrix, "{http://www.opengis.net/wmts/1.0}TileWidth").text = str(WMTS_TILE_SIZE)
        SubElement(tile_matrix, "{http://www.opengis.net/wmts/1.0}TileHeight").text = str(WMTS_TILE_SIZE)
        SubElement(tile_matrix, "{http://www.opengis.net/wmts/1.0}MatrixWidth").text = str(matrix_width)
        SubElement(tile_matrix, "{http://www.opengis.net/wmts/1.0}MatrixHeight").text = str(matrix_height)

    return tostring(capabilities, encoding="utf-8", xml_declaration=True).decode("utf-8")


def list_wmts_payload(base_url: str) -> dict:
    return {
        "layers": [
            {
                "identifier": layer.identifier,
                "name": layer.title,
                "path": layer.relative_path,
                "provider": "wmts",
                "tile_url": f"/wmts/{quote(layer.identifier, safe='')}/{WMTS_MATRIX_SET}/{{z}}/{{y}}/{{x}}.png",
                "rest_tile_url": f"/wmts/{quote(layer.identifier, safe='')}/{WMTS_MATRIX_SET}/{{z}}/{{y}}/{{x}}.png",
                "capabilities_url": "/wmts/1.0.0/WMTSCapabilities.xml",
                "demo_url": "/wmts/demo",
                "source_modes": ["proxy"],
                "bounds": {
                    "epsg4326": layer.bounds_4326,
                },
            }
            for layer in list_wmts_layers()
        ],
        "skipped_layers": [
            {
                "identifier": skipped.identifier,
                "name": skipped.title,
                "path": skipped.relative_path,
                "reason": skipped.reason,
            }
            for skipped in list_skipped_wmts_layers()
        ],
        "service": {
            "capabilities_url": "/wmts/1.0.0/WMTSCapabilities.xml",
            "demo_url": "/wmts/demo",
            "kvp_url": "/wmts",
            "matrix_set": WMTS_MATRIX_SET,
            "crs": WGS84,
            "base_url": base_url,
        },
    }
