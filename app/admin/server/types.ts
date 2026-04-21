import type { AuthenticatedUser } from "./auth.js";

declare global {
  // eslint-disable-next-line @typescript-eslint/no-namespace -- required by Express to augment its global types
  namespace Express {
    interface Request {
      /** Entra-verified identity. Present on any /api route. */
      auth?: AuthenticatedUser;
      /** OpenWebUI user id resolved from the Entra email claim. */
      openwebuiUserId?: string;
    }
  }
}

export {};
