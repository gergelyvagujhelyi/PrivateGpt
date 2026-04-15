import { readFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

import { Router } from "express";
import { parse as parseYaml } from "yaml";

import { ModelCatalogueSchema } from "../../shared/schema.js";

// Production: Dockerfile ships app/models.yaml to /app/models.yaml and sets MODELS_YAML_PATH.
// Local dev: fall back to the repo copy two levels up from this source file.
const __dirname = path.dirname(fileURLToPath(import.meta.url));
const DEFAULT_PATH = path.resolve(__dirname, "..", "..", "..", "models.yaml");
const CATALOGUE_PATH = process.env.MODELS_YAML_PATH ?? DEFAULT_PATH;

export const modelsRouter = Router();

modelsRouter.get("/", async (_req, res) => {
  const raw = await readFile(CATALOGUE_PATH, "utf8");
  const parsed = parseYaml(raw) as { models: Array<Record<string, unknown>> };
  const catalogue = ModelCatalogueSchema.parse({
    models: parsed.models.map((m) => ({
      name: m.name,
      provider: m.provider,
      purpose: m.purpose,
      exposedAs: m.exposed_as,
    })),
  });
  res.json(catalogue);
});
