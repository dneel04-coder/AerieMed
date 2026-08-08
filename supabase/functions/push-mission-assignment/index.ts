// Sends a real push notification (FCM/APNs) when a user is assigned to an
// incident, so they find out even if their phone/app is closed. Triggered by
// the incident_members_push_trigger Postgres trigger (see
// notify_incident_member_pending in resqruck_auto_migrate()), not called
// directly by any client — authenticated via a shared secret header instead
// of a Supabase JWT since this is an internal server-to-server call.
//
// The FCM service-account credential lives only here (as an Edge Function
// secret) — it must never be embedded in the mobile app or the Command
// Console, since the Console is Microsoft-Store-distributed and therefore
// extractable.
import { createClient } from "npm:@supabase/supabase-js@2";
import { GoogleAuth } from "npm:google-auth-library@9";

const PUSH_TRIGGER_SECRET = Deno.env.get("PUSH_TRIGGER_SECRET")!;
const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!; // auto-provided to every Edge Function
const FCM_SERVICE_ACCOUNT_JSON = Deno.env.get("FCM_SERVICE_ACCOUNT_JSON")!;
const FIREBASE_PROJECT_ID = Deno.env.get("FIREBASE_PROJECT_ID")!;

Deno.serve(async (req) => {
  if (req.headers.get("x-push-secret") !== PUSH_TRIGGER_SECRET) {
    return new Response("unauthorized", { status: 401 });
  }

  const { user_id, incident_id } = await req.json();
  const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

  const [{ data: tokenRow }, { data: incident }] = await Promise.all([
    supabase.from("device_push_tokens").select("fcm_token").eq("user_id", user_id).maybeSingle(),
    supabase.from("incidents").select("name, mission_code").eq("id", incident_id).maybeSingle(),
  ]);
  if (!tokenRow?.fcm_token) return new Response("no token", { status: 200 });

  const label = incident?.name || incident?.mission_code || "a mission";

  const auth = new GoogleAuth({
    credentials: JSON.parse(FCM_SERVICE_ACCOUNT_JSON),
    scopes: ["https://www.googleapis.com/auth/firebase.messaging"],
  });
  const accessToken = await auth.getAccessToken();

  const resp = await fetch(
    `https://fcm.googleapis.com/v1/projects/${FIREBASE_PROJECT_ID}/messages:send`,
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${accessToken}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        message: {
          token: tokenRow.fcm_token,
          notification: {
            title: "Mission Assignment",
            body: `You've been assigned to mission: ${label}`,
          },
        },
      }),
    },
  );

  return new Response(await resp.text(), { status: resp.ok ? 200 : 500 });
});
