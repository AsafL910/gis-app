from fastapi import APIRouter

from src.services.catalog import list_layers_payload


router = APIRouter(tags=["Metadata"])


@router.get("/layers")
def list_layers():
    return list_layers_payload()
