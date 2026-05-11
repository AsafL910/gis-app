import { Router } from "express";
import { activateDtm, createMapSet, getCatalog } from "../services/mapSets.js";
import type { MapSetCreateRequest } from "../types.js";


export const catalogRouter = Router();


catalogRouter.get("/catalog/", async (_request, response) => {
  try {
    response.json(await getCatalog());
  } catch (error) {
    response.status(500).json({ detail: (error as Error).message });
  }
});


catalogRouter.post("/activate-dtm/", async (request, response) => {
  try {
    const relativePath = request.body?.path;
    if (typeof relativePath !== "string" || !relativePath) {
      throw new Error("Expected a non-empty 'path'");
    }
    const activeDataset = await activateDtm(relativePath);
    response.json({ active_dataset: activeDataset, status: "activated" });
  } catch (error) {
    response.status(400).json({ detail: (error as Error).message });
  }
});


catalogRouter.post("/map-sets/", async (request, response) => {
  try {
    const result = await createMapSet(request.body as MapSetCreateRequest);
    response.json(result);
  } catch (error) {
    response.status(400).json({ detail: (error as Error).message });
  }
});
