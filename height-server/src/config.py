import os
from pathlib import Path


DATA_DIR = Path(os.environ.get("DATA_DIR", str(Path(__file__).resolve().parent.parent / "data")))
DTM_DIRNAME = os.environ.get("DTM_DIRNAME", "dtm")
DTM_DIR = DATA_DIR / DTM_DIRNAME
ELEV_FILENAME = os.environ.get("ELEV_FILENAME", f"{DTM_DIRNAME}/israel_merged.vrt")
DEFAULT_VRT_NAME = os.environ.get("ELEV_VRT_FILENAME", "israel_merged.vrt")
TOP_FILENAME = os.environ.get("TOP_ELEV_FILENAME", "israel_top_cog.tif")
BOTTOM_FILENAME = os.environ.get("BOTTOM_ELEV_FILENAME", "israel_bottom_cog.tif")
