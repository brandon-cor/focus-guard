import type { FastifyRequest, FastifyReply } from "fastify";

// Verifies the JWT issued by our own server (not Apple's token — that's appleAuth.ts).
// Attach this as a preHandler hook on any route that requires authentication.
export async function requireAuth(
  request: FastifyRequest,
  reply: FastifyReply
) {
  try {
    // fastify-jwt attaches .jwtVerify() to the request object
    await request.jwtVerify();
  } catch {
    reply.status(401).send({ error: "Unauthorized" });
  }
}

// Typed helper to get the authenticated user from a verified request.
// Call this only inside routes protected by requireAuth.
export function getAuthUser(request: FastifyRequest): { userId: string } {
  const payload = request.user as { userId: string };
  return { userId: payload.userId };
}
