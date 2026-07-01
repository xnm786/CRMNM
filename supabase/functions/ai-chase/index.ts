// Clera — `ai-chase` Edge Function
//
// The CRM front-end calls this with:
//   const { data, error } = await sb.functions.invoke('ai-chase', { body: { prompt } })
// and expects back JSON of the shape:  { text: "..." }
//
// It drafts the polite-but-persistent chasing messages (and answers the
// plain-English queries) that Clera is built around. The Anthropic API key is
// read from an environment variable and never leaves the server, so it is never
// exposed to the browser. If anything goes wrong the front-end falls back to a
// local template, so a failure here degrades gracefully rather than breaking.
//
// Deploy:   supabase functions deploy ai-chase
// Secrets:  supabase secrets set ANTHROPIC_API_KEY=sk-ant-...
//           (optionally CLERA_AI_MODEL to override the default model)

const ANTHROPIC_URL = "https://api.anthropic.com/v1/messages";
const DEFAULT_MODEL = "claude-opus-4-8";

const SYSTEM_PROMPT = [
  "You are Clera, an assistant inside a CRM for UK accountancy practices.",
  "You help the practice chase clients for outstanding documents and answer",
  "questions about their clients and deadlines. When drafting a message to a",
  "client, be polite, warm and professional but clear about what is needed and",
  "by when. Keep it concise — a short email or SMS, not an essay. Use British",
  "English. Do not invent facts that were not provided; if a detail is missing,",
  "leave a clearly marked placeholder like [deadline]. Return only the message",
  "text or the answer itself, with no preamble such as \"Here is\".",
].join(" ");

const CORS_HEADERS: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
  });
}

Deno.serve(async (req: Request): Promise<Response> => {
  // Browsers send a CORS preflight before the real POST.
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: CORS_HEADERS });
  }
  if (req.method !== "POST") {
    return json({ error: "Method not allowed" }, 405);
  }

  let prompt: unknown;
  try {
    ({ prompt } = await req.json());
  } catch {
    return json({ error: "Invalid JSON body" }, 400);
  }
  if (typeof prompt !== "string" || prompt.trim() === "") {
    return json({ error: "Missing 'prompt'" }, 400);
  }

  const apiKey = Deno.env.get("ANTHROPIC_API_KEY");
  if (!apiKey) {
    // Not configured yet — tell the front-end so it uses its template fallback.
    return json({ error: "AI is not configured on the server." }, 503);
  }
  const model = Deno.env.get("CLERA_AI_MODEL") ?? DEFAULT_MODEL;

  try {
    const upstream = await fetch(ANTHROPIC_URL, {
      method: "POST",
      headers: {
        "content-type": "application/json",
        "x-api-key": apiKey,
        "anthropic-version": "2023-06-01",
      },
      body: JSON.stringify({
        model,
        max_tokens: 1024,
        system: SYSTEM_PROMPT,
        messages: [{ role: "user", content: prompt }],
      }),
    });

    if (!upstream.ok) {
      const detail = await upstream.text();
      console.error("Anthropic API error", upstream.status, detail);
      return json({ error: "AI upstream error" }, 502);
    }

    const data = await upstream.json();
    const text = data?.content
      ?.filter((b: { type: string }) => b.type === "text")
      .map((b: { text: string }) => b.text)
      .join("")
      .trim() ?? "";

    return json({ text });
  } catch (err) {
    console.error("ai-chase failed", err);
    return json({ error: "AI request failed" }, 500);
  }
});
