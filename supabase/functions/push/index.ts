// Sends one notification to a list of phones through Firebase Cloud Messaging (HTTP v1).
//
// Called only by the database (private.send_push) with:
//   header  x-push-secret: <same value as the PUSH_SECRET function secret>
//   body    { title, body, data, tokens: string[] }
//
// Function secrets (set with `supabase secrets set`):
//   PUSH_SECRET           shared secret, also stored in Vault as `push_secret`
//   FCM_SERVICE_ACCOUNT   the Firebase service-account JSON file, as one string

type ServiceAccount = { project_id: string; client_email: string; private_key: string };

const encoder = new TextEncoder();

function base64url(input: ArrayBuffer | Uint8Array | string): string {
  const bytes = typeof input === "string"
    ? encoder.encode(input)
    : input instanceof Uint8Array ? input : new Uint8Array(input);
  let binary = "";
  for (const b of bytes) binary += String.fromCharCode(b);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

async function importKey(pem: string): Promise<CryptoKey> {
  const body = pem.replace(/-----[^-]+-----/g, "").replace(/\s+/g, "");
  const der = Uint8Array.from(atob(body), (c) => c.charCodeAt(0));
  return await crypto.subtle.importKey(
    "pkcs8",
    der,
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
}

let cachedToken: { value: string; expires: number } | null = null;

// Exchanges a signed JWT for a short-lived Google OAuth token.
async function accessToken(sa: ServiceAccount): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  if (cachedToken && cachedToken.expires - 60 > now) return cachedToken.value;

  const header = base64url(JSON.stringify({ alg: "RS256", typ: "JWT" }));
  const claims = base64url(JSON.stringify({
    iss: sa.client_email,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: "https://oauth2.googleapis.com/token",
    iat: now,
    exp: now + 3600,
  }));
  const unsigned = `${header}.${claims}`;
  const key = await importKey(sa.private_key);
  const signature = await crypto.subtle.sign("RSASSA-PKCS1-v1_5", key, encoder.encode(unsigned));
  const jwt = `${unsigned}.${base64url(signature)}`;

  const res = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: jwt,
    }),
  });
  if (!res.ok) throw new Error(`Google token request failed: ${res.status} ${await res.text()}`);
  const json = await res.json();
  cachedToken = { value: json.access_token, expires: now + (json.expires_in ?? 3600) };
  return cachedToken.value;
}

// FCM data values must be strings.
function stringify(data: Record<string, unknown>): Record<string, string> {
  const out: Record<string, string> = {};
  for (const [k, v] of Object.entries(data ?? {})) {
    if (v !== null && v !== undefined) out[k] = typeof v === "string" ? v : JSON.stringify(v);
  }
  return out;
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return new Response("Method not allowed", { status: 405 });

  const secret = Deno.env.get("PUSH_SECRET");
  if (!secret || req.headers.get("x-push-secret") !== secret) {
    return new Response("Forbidden", { status: 403 });
  }

  const raw = Deno.env.get("FCM_SERVICE_ACCOUNT");
  if (!raw) return new Response("FCM_SERVICE_ACCOUNT is not set", { status: 500 });
  const sa = JSON.parse(raw) as ServiceAccount;

  const { title, body, data, tokens } = await req.json() as {
    title: string;
    body: string;
    data?: Record<string, unknown>;
    tokens: string[];
  };
  if (!title || !Array.isArray(tokens) || tokens.length === 0) {
    return Response.json({ sent: 0 });
  }

  const token = await accessToken(sa);
  const url = `https://fcm.googleapis.com/v1/projects/${sa.project_id}/messages:send`;
  const results = await Promise.all(tokens.map(async (to) => {
    const res = await fetch(url, {
      method: "POST",
      headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" },
      body: JSON.stringify({
        message: {
          token: to,
          notification: { title, body },
          data: stringify(data ?? {}),
          android: { priority: "HIGH", notification: { channel_id: "alerts" } },
        },
      }),
    });
    return { ok: res.ok, status: res.status, error: res.ok ? undefined : await res.text() };
  }));

  const failed = results.filter((r) => !r.ok);
  if (failed.length) console.warn("Some pushes failed", failed);
  return Response.json({ sent: results.length - failed.length, failed: failed.length });
});
