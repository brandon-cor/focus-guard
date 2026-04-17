import { createRemoteJWKSet, jwtVerify } from "jose";

// Apple publishes its public keys here — we verify the identity token signature
// against these so we know the token actually came from Apple.
const APPLE_JWKS = createRemoteJWKSet(
  new URL("https://appleid.apple.com/auth/keys")
);

export interface AppleClaims {
  sub: string;       // unique user identifier — stable per app per user
  email?: string;
  iss: string;
  aud: string | string[];
}

// clientId is your Apple Sign In service ID or app bundle ID.
// Apple sets "aud" to whichever was used to sign in.
export async function verifyAppleIdentityToken(
  identityToken: string,
  clientId: string
): Promise<AppleClaims> {
  const { payload } = await jwtVerify(identityToken, APPLE_JWKS, {
    issuer: "https://appleid.apple.com",
    audience: clientId,
  });

  if (!payload.sub) {
    throw new Error("Apple identity token missing sub claim");
  }

  return {
    sub: payload.sub as string,
    email: payload.email as string | undefined,
    iss: payload.iss as string,
    aud: payload.aud as string | string[],
  };
}
