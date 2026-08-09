import { createClient } from "npm:@supabase/supabase-js@2";
import { GoogleAuth } from "npm:google-auth-library@9";

const ACCESS_REQUEST_SECRET = Deno.env.get("ACCESS_REQUEST_SECRET")!;
const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const FCM_SERVICE_ACCOUNT_JSON = Deno.env.get("FCM_SERVICE_ACCOUNT_JSON")!;
const FIREBASE_PROJECT_ID = Deno.env.get("FIREBASE_PROJECT_ID")!;

Deno.serve(async (req) => {
  if (req.headers.get("x-access-secret") !== ACCESS_REQUEST_SECRET) {
    return new Response("unauthorized", { status: 401 });
  }
  const { user_id, status } = await req.json();
  const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);
  const { data: tokenRow } = await supabase
    .from("device_push_tokens")
    .select("fcm_token")
    .eq("user_id", user_id)
    .maybeSingle();
  if (!tokenRow?.fcm_token) return new Response("no token", { status: 200 });

  const auth = new GoogleAuth({
    credentials: JSON.parse(FCM_SERVICE_ACCOUNT_JSON),
    scopes: ["https://www.googleapis.com/auth/firebase.messaging"],
  });
  const accessToken = await auth.getAccessToken();
  const notification = status === "approved"
    ? { title: "Access Approved", body: "Your ResQruck access request was approved — open the app to continue." }
    : { title: "Access Request Update", body: "Your ResQruck access request was not approved." };
  const resp = await fetch(
    `https://fcm.googleapis.com/v1/projects/${FIREBASE_PROJECT_ID}/messages:send`,
    {
      method: "POST",
      headers: { Authorization: `Bearer ${accessToken}`, "Content-Type": "application/json" },
      body: JSON.stringify({ message: { token: tokenRow.fcm_token, notification } }),
    },
  );
  return new Response(await resp.text(), { status: resp.ok ? 200 : 500 });
});
