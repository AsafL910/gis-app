from fastapi import FastAPI
from fastapi.responses import RedirectResponse
from titiler.core.factory import TilerFactory

from src.routes.metadata import router as metadata_router
from src.routes.preview import router as preview_router


app = FastAPI(
    title="Map Provider Server",
    description="Dynamic COG tile provider with a self-contained preview page",
)


@app.get("/")
def root_redirect():
    return RedirectResponse(url="/demo")


cog = TilerFactory()
app.include_router(cog.router, prefix="/cog", tags=["COG Tiles"])
app.include_router(metadata_router)
app.include_router(preview_router)


if __name__ == "__main__":
    import uvicorn

    uvicorn.run(app, host="0.0.0.0", port=8000)
