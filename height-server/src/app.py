from fastapi import FastAPI
from src.routes.elevation import router as elevation_router

app = FastAPI(
    title="Height Calculation Server",
    description="Dedicated server for elevation and spatial calculations via GDAL"
)

app.include_router(elevation_router)

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8001)
