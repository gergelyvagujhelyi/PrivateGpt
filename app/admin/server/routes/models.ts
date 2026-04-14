import { readFile } from "node:fs/promises";
import path from "node:path";

import { Router } from "express";
import { parse as parseYaml } from "yaml";

import { ModelCatalogueSchema } from "../../shared/schema.ts";

const CATALOGUE_PATH = process.env.MODELS_YAML_PATH ?? path.resolve("/etc/admin/models.yaml");

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
