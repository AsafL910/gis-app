from pydantic import BaseModel


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
