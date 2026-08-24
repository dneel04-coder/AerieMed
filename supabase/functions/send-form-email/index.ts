// Directly invoked by the Flutter app (SupabaseService.client!.functions.invoke),
// not triggered by Postgres -- unlike the other functions in this project, so
// it relies on Supabase's default JWT verification (the anon key the app
// already embeds is itself a valid JWT) rather than a shared-secret header.
// See supabase/config.toml -- this function is deliberately NOT listed with
// verify_jwt = false.
const RESEND_API_KEY = Deno.env.get("RESEND_API_KEY")!;

interface SendFormEmailBody {
  to: string;
  subject: string;
  text?: string;
  filename: string;
  pdfBase64: string;
}

Deno.serve(async (req) => {
  let body: SendFormEmailBody;
  try {
    body = await req.json();
  } catch {
    return new Response("invalid JSON body", { status: 400 });
  }

  const { to, subject, text, filename, pdfBase64 } = body;
  if (!to || !subject || !filename || !pdfBase64) {
    return new Response("missing required field(s)", { status: 400 });
  }

  const resp = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${RESEND_API_KEY}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      from: "ResQruck <douglas.neel@peninsulathreat.com>",
      to,
      subject,
      text: text || "See attached.",
      attachments: [{ filename, content: pdfBase64 }],
    }),
  });
  return new Response(await resp.text(), { status: resp.ok ? 200 : 500 });
});
