import { createClient } from "npm:@supabase/supabase-js@2";

const ACCESS_REQUEST_SECRET = Deno.env.get("ACCESS_REQUEST_SECRET")!;
const RESEND_API_KEY = Deno.env.get("RESEND_API_KEY")!;
const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

Deno.serve(async (req) => {
  if (req.headers.get("x-access-secret") !== ACCESS_REQUEST_SECRET) {
    return new Response("unauthorized", { status: 401 });
  }
  const { user_id } = await req.json();
  const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);
  const { data: reqRow } = await supabase
    .from("access_requests")
    .select("name, callsign, company, email")
    .eq("user_id", user_id)
    .maybeSingle();
  if (!reqRow) return new Response("request not found", { status: 200 });

  const resp = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${RESEND_API_KEY}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      from: "ResQruck <onboarding@resend.dev>",
      to: "allamerican82consulting@gmail.com",
      subject: `New Access Request: ${reqRow.name}`,
      text: `Name: ${reqRow.name}\nCallsign: ${reqRow.callsign || "—"}\nCompany: ${reqRow.company || "—"}\nEmail: ${reqRow.email || "—"}\n\nApprove or deny from the Command Console or the mobile app's Admin Panel.`,
    }),
  });
  return new Response(await resp.text(), { status: resp.ok ? 200 : 500 });
});
