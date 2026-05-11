import express from "express";

import { PORT } from "./config.js";
import { catalogRouter } from "./routes/catalog.js";
import { ensureDataDirs } from "./services/files.js";


const app = express();
app.use(express.json({ limit: "2mb" }));
app.use(catalogRouter);


void ensureDataDirs().then(() => {
  app.listen(PORT, "0.0.0.0", () => {
    console.log(`Map manager listening on ${PORT}`);
  });
}).catch((error: Error) => {
  console.error("Failed to initialize map manager", error);
  process.exit(1);
});
