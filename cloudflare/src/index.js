const json = (body, status = 200) => new Response(JSON.stringify(body), {
  status,
  headers: { "Content-Type": "application/json; charset=utf-8" },
});

function validateOrder(body) {
  if (!body || typeof body.customer_id !== "string" || !body.customer_id.trim()) return "customer_id must be a non-empty string";
  if (!Array.isArray(body.items) || body.items.length === 0) return "items must be a non-empty list";
  for (const item of body.items) {
    if (!item || typeof item.sku !== "string" || !item.sku.trim()) return "every item needs a non-empty sku";
    if (!Number.isInteger(item.quantity) || item.quantity < 1) return "every item quantity must be a positive integer";
    if (!Number.isFinite(Number(item.unit_price)) || Number(item.unit_price) < 0) return "every item unit_price must be zero or greater";
  }
  return null;
}

async function processOrder(env, order) {
  // waitUntil keeps the acknowledgement fast while the status change happens asynchronously.
  const processed = { ...order, status: "PROCESSED", processed_at: new Date().toISOString() };
  await env.ORDERS.put(order.order_id, JSON.stringify(processed));
}

export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);
    if (request.method === "OPTIONS" && url.pathname.startsWith("/api/")) return new Response(null, { status: 204 });

    if (request.method === "POST" && url.pathname === "/api/orders") {
      let body;
      try { body = await request.json(); } catch { return json({ message: "request body must be valid JSON" }, 400); }
      const validationError = validateOrder(body);
      if (validationError) return json({ message: validationError }, 400);

      const total = body.items.reduce((sum, item) => sum + Number(item.unit_price) * item.quantity, 0);
      const order = {
        order_id: crypto.randomUUID(),
        customer_id: body.customer_id.trim(),
        items: body.items,
        total: total.toFixed(2),
        created_at: new Date().toISOString(),
        status: "RECEIVED",
      };
      await env.ORDERS.put(order.order_id, JSON.stringify(order));
      ctx.waitUntil(processOrder(env, order));
      return json({ order_id: order.order_id, status: "RECEIVED" }, 202);
    }

    const match = url.pathname.match(/^\/api\/orders\/([\w-]+)$/);
    if (request.method === "GET" && match) {
      const order = await env.ORDERS.get(match[1], "json");
      return order ? json(order) : json({ message: "order not found" }, 404);
    }

    return env.ASSETS.fetch(request);
  },
};
