from fastapi import FastAPI, HTTPException
from pydantic import BaseModel, Field
from typing import Optional
import os
import subprocess
import logging

GDALWARP = os.getenv("GDALWARP", "gdalwarp")
RIO = os.getenv("RIO", "rio")
GDAL2TILES = os.getenv("GDAL2TILES", "gdal2tiles.py")

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = FastAPI()

class GeoTiffRequest(BaseModel):
    tif_name: str
    output_directory: str
    min_zoom: Optional[int] = 8
    max_zoom: Optional[int] = 10
    duplicate_option: Optional[str] = Field(
        default="error",
        pattern="^(skip|override|error)$",
        description="What to do if output directory already exists: 'skip', 'override', or 'error'."
    )

def run_command(command):
    try:
        result = subprocess.run(command, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        logger.info(result.stdout)
        return result.stdout
    except subprocess.CalledProcessError as e:
        logger.error(e.stderr)
        raise HTTPException(status_code=500, detail=f"Error running command: {e.stderr}")

def reproject_geotiff(input_path, output_path):
    command = [GDALWARP, "-t_srs", "EPSG:4326", "-dstnodata", "None", "-co", "TILED=YES", "-co", "COMPRESS=DEFLATE", "-co", "BIGTIFF=IF_NEEDED", input_path, output_path]
    run_command(command)

def rgbify_geotiff(input_path, output_path):
    command = [RIO, "rgbify", "-b", "-10000", "-i", "0.1", input_path, output_path]
    run_command(command)

def generate_hat_tiles(input_path, output_dir, min_zoom, max_zoom):
    command = [GDAL2TILES, "-z", f"{min_zoom}-{max_zoom}", "-p", "geodetic", "--xyz", input_path, output_dir]
    run_command(command)

@app.post("/generate-tiles/")
def generate_tiles(request: GeoTiffRequest):
    """
    Generate tiles from a GeoTIFF file and save them to a specified output directory.
    """
    tif_path = f"../data/{request.tif_name}"
    output_dir = f"../data/{request.output_directory}"

    if (request.duplicate_option == "override"):
        for root, dirs, files in os.walk(output_dir, topdown=False):
                for name in files:
                    os.remove(os.path.join(root, name))
                for name in dirs:
                    os.rmdir(os.path.join(root, name))
        logger.info(f"Deleted all previous hat files in directory '{request.output_directory}'")

    if not os.path.exists(tif_path):
        raise HTTPException(status_code=400, detail=f"GeoTIFF file {request.tif_name} does not exist.")
    if request.min_zoom < 1 or request.max_zoom > 20:
        raise HTTPException(status_code=400, detail="Zoom levels must be between 1 and 20.")
    if request.min_zoom > request.max_zoom:
        raise HTTPException(status_code=400, detail="min_zoom cannot be greater than max_zoom.")

    os.makedirs(output_dir, exist_ok=True)

    try:
        def path_exists(path):
            return os.path.exists(path)
        def should_skip_process(path):
            path_already_exists = path_exists(path)

            if request.duplicate_option == "override":
                return False
            elif request.duplicate_option == "skip" and path_already_exists:
                return True
            elif not path_already_exists:
                return False

            return False
        
        # Step 1: Reproject GeoTIFF to EPSG:4326
        reprojected_tif = os.path.join(output_dir, "reprojected.tif")

        if not should_skip_process(reprojected_tif):
            reproject_geotiff(tif_path, reprojected_tif)
        else:
            logger.info(f"Skipped reprojection process since a file named {reprojected_tif} already exists.")

        # Step 2: RGB-ify the reprojected GeoTIFF
        rgb_tif = os.path.join(output_dir, "rgbified.tif")
        if not should_skip_process(rgb_tif):
            rgbify_geotiff(reprojected_tif, rgb_tif)
        else:
            logger.info(f"Skipped rgbify process since a file named {rgb_tif} already exists.")

        # Step 3: Generate Tile Pyramid

        generate_hat_tiles(rgb_tif, output_dir, request.min_zoom, request.max_zoom)

        return {"message": "Tiles generated successfully.", "output_directory": output_dir}

    except subprocess.CalledProcessError as e:
        raise HTTPException(status_code=500, detail=f"Error during tile generation: {str(e)}")

    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Unexpected error: {str(e)}")