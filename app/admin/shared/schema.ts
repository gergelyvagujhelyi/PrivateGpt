import { z } from "zod";

export const PreferencesSchema = z.object({
  userId: z.string(),
  digestFrequency: z.enum(["daily", "weekly", "off"]),
  unsubscribedAt: z.string().datetime().nullable(),
  lastSentAt: z.string().datetime().nullable(),
});
export type Preferences = z.infer<typeof PreferencesSchema>;

export const PreferencesPatchSchema = PreferencesSchema.pick({
  digestFrequency: true,
}).partial();
export type PreferencesPatch = z.infer<typeof PreferencesPatchSchema>;

export const ModelSchema = z.object({
  name: z.string(),
  provider: z.enum(["openai", "anthropic"]),
  purpose: z.enum(["chat", "embedding", "reranker"]),
  exposedAs: z.string(),
});
export const ModelCatalogueSchema = z.object({ models: z.array(ModelSchema) });
export type Model = z.infer<typeof ModelSchema>;
export type ModelCatalogue = z.infer<typeof ModelCatalogueSchema>;

export const UsageSummarySchema = z.object({
  userId: z.string(),
  windowDays: z.number().int().positive(),
  traceCount: z.number().int().nonnegative(),
  totalTokens: z.number().int().nonnegative(),
  costUsd: z.number().nonnegative(),
  topModels: z.array(z.object({ name: z.string(), count: z.number().int() })),
});
export type UsageSummary = z.infer<typeof UsageSummarySchema>;
