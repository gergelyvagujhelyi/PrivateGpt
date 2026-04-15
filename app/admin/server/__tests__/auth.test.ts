import { describe, expect, it } from "vitest";

import { PreferencesPatchSchema, PreferencesSchema } from "../../shared/schema.js";

describe("schema contracts", () => {
  it("rejects unknown digest frequency", () => {
    expect(() => PreferencesSchema.parse({
      userId: "u",
      digestFrequency: "hourly",
      unsubscribedAt: null,
      lastSentAt: null,
    })).toThrow();
  });

  it("accepts partial patch with just digestFrequency", () => {
    const parsed = PreferencesPatchSchema.parse({ digestFrequency: "weekly" });
    expect(parsed.digestFrequency).toBe("weekly");
  });

  it("accepts empty patch", () => {
    expect(PreferencesPatchSchema.parse({})).toEqual({});
  });
});
