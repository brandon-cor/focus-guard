import type { FastifyInstance } from "fastify";
import { verifyAppleIdentityToken } from "../lib/appleAuth";
import sql from "../db/client";

interface AppleSignInBody {
  identityToken: string;
  // the full name from Apple (only sent on first sign in)
  fullName?: string;
}

export async function authRoutes(app: FastifyInstance) {
  // POST /auth/apple
  // Client sends Apple's identity token after a successful Sign in with Apple.
  // We verify it, upsert the user, and return our own JWT.
  app.post<{ Body: AppleSignInBody }>("/auth/apple", async (request, reply) => {
    const { identityToken } = request.body;

    if (!identityToken) {
      return reply.status(400).send({ error: "identityToken is required" });
    }

    // APPLE_CLIENT_ID must be set to your app's bundle ID (e.g. com.yourname.focusguard)
    // or your Sign in with Apple service ID if using a web flow.
    const clientId = process.env.APPLE_CLIENT_ID;
    if (!clientId) {
      throw new Error("APPLE_CLIENT_ID env var not set");
    }

    let claims;
    try {
      claims = await verifyAppleIdentityToken(identityToken, clientId);
    } catch (err) {
      request.log.warn({ err }, "Apple identity token verification failed");
      return reply.status(401).send({ error: "Invalid identity token" });
    }

    // upsert: create the user on first sign in, just return their id on subsequent ones
    const [user] = await sql<{ id: string }[]>`
      insert into users (apple_sub, email)
      values (${claims.sub}, ${claims.email ?? null})
      on conflict (apple_sub)
      do update set email = excluded.email
      returning id
    `;

    // sign our own JWT — the client uses this for all future requests
    const token = app.jwt.sign(
      { userId: user.id },
      { expiresIn: "30d" }
    );

    return reply.send({ token, userId: user.id });
  });
}
