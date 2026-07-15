import http from "node:http";

const port = Number(process.env.AZURE_FOUNDRY_PROXY_PORT || 41437);
const key = process.env.AZURE_API_KEY;
const baseUrl = (
  process.env.AZURE_FOUNDRY_BASE_URL ||
  "https://ih-foundry-resource.services.ai.azure.com/openai/v1"
).replace(/\/+$/, "");
const target = `${baseUrl}/chat/completions`;

if (!key) throw new Error("AZURE_API_KEY is required");

const server = http.createServer(async (req, res) => {
  if (req.method !== "POST" || !req.url?.endsWith("/chat/completions")) {
    res.writeHead(404).end("not found");
    return;
  }

  try {
    let raw = "";
    for await (const chunk of req) raw += chunk;
    const body = JSON.parse(raw || "{}");
    const model = String(body.model || "").toLowerCase();

    if (body.max_tokens !== undefined && body.max_completion_tokens === undefined) {
      body.max_completion_tokens = body.max_tokens;
    }
    delete body.max_tokens;
    delete body.stop;

    if (model.startsWith("gpt-5.6-")) {
      delete body.reasoning_effort;
      if (body.temperature !== undefined && body.temperature !== 1) {
        delete body.temperature;
      }
    }

    const upstream = await fetch(target, {
      method: "POST",
      headers: {
        "content-type": "application/json",
        authorization: `Bearer ${key}`,
      },
      body: JSON.stringify(body),
    });

    res.writeHead(upstream.status, Object.fromEntries(upstream.headers));
    res.end(Buffer.from(await upstream.arrayBuffer()));
  } catch (error) {
    if (!res.headersSent) {
      res.writeHead(502, { "content-type": "application/json" });
      res.end(JSON.stringify({ error: { message: String(error) } }));
    }
  }
});

server.listen(port, "127.0.0.1", () => {
  console.error(`azure-foundry-proxy listening on http://127.0.0.1:${port}/v1`);
});
