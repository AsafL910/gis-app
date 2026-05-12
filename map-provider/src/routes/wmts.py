from pathlib import Path

from fastapi import APIRouter, Request
from fastapi.responses import HTMLResponse, Response

from src.services.wmts import (
    build_wmts_capabilities_xml,
    list_wmts_payload,
    render_wmts_tile,
)


router = APIRouter(tags=["WMTS"])
DEMO_HTML = Path(__file__).resolve().parent.parent / "templates" / "wmts_demo.html"


def _base_url(request: Request) -> str:
    return str(request.base_url).rstrip("/")


@router.get("/wmts/layers")
def list_wmts_layers(request: Request):
    return list_wmts_payload(_base_url(request))


@router.get("/wmts/1.0.0/WMTSCapabilities.xml")
def wmts_capabilities(request: Request):
    xml = build_wmts_capabilities_xml(_base_url(request))
    return Response(content=xml, media_type="application/xml")


@router.get("/wmts", response_class=Response)
def wmts_kvp(request: Request):
    params = {key.lower(): value for key, value in request.query_params.items()}
    service = params.get("service", "").upper()
    action = params.get("request", "").lower()

    if service and service != "WMTS":
        return Response(content="Unsupported service", status_code=400, media_type="text/plain")

    if action == "getcapabilities":
        xml = build_wmts_capabilities_xml(_base_url(request))
        return Response(content=xml, media_type="application/xml")

    if action == "gettile":
        tile = render_wmts_tile(
            identifier=params.get("layer", ""),
            tile_matrix_set=params.get("tilematrixset", ""),
            tile_matrix=int(params.get("tilematrix", "0")),
            tile_row=int(params.get("tilerow", "0")),
            tile_col=int(params.get("tilecol", "0")),
        )
        return Response(content=tile, media_type="image/png")

    return Response(content="Unsupported WMTS request", status_code=400, media_type="text/plain")


@router.get("/wmts/{identifier}/{tile_matrix_set}/{tile_matrix}/{tile_row}/{tile_col}.png")
def wmts_rest_tile(identifier: str, tile_matrix_set: str, tile_matrix: int, tile_row: int, tile_col: int):
    tile = render_wmts_tile(identifier, tile_matrix_set, tile_matrix, tile_row, tile_col)
    return Response(content=tile, media_type="image/png")


@router.get("/wmts/demo", response_class=HTMLResponse)
def wmts_demo_page():
    return DEMO_HTML.read_text(encoding="utf-8")
