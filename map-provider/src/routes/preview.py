from pathlib import Path

from fastapi import APIRouter
from fastapi.responses import HTMLResponse

from src.services.preview import preview_layer as build_preview


router = APIRouter()
DEMO_HTML = Path(__file__).resolve().parent.parent / "templates" / "demo.html"


@router.get("/preview", tags=["Preview"])
def preview_layer(filename: str, max_size: int = 1600):
    return build_preview(filename, max_size)


@router.get("/demo", response_class=HTMLResponse, tags=["Demo"])
def demo_page():
    return DEMO_HTML.read_text(encoding="utf-8")
