import type { AuthenticatedUser } from "./auth.js";

declare global {
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
