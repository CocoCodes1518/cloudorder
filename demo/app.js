const catalog = {
  "cloud-keyboard": { name: "Cloud Keyboard", price: 69.99 },
  "cloud-mouse": { name: "Cloud Mouse", price: 29.99 },
  "cloud-monitor": { name: "Cloud Monitor", price: 249.99 },
};
const state = { processed: Number(localStorage.getItem("cloudorder-processed") || 0), events: [] };
const $ = (selector) => document.querySelector(selector);

function render() {
  $("#processed-count").textContent = state.processed;
  $("#queue-count").textContent = state.events.filter((event) => event.stage === "queued").length;
  $("#queue-state").textContent = $("#queue-count").textContent === "0" ? "Healthy" : "Processing";
  const list = $("#activity-list");
  list.innerHTML = state.events.length ? state.events.slice(0, 7).map((event) => `<div class="event"><i class="event-dot ${event.stage === "done" ? "done" : ""}"></i><div class="event-main">${event.message}<small>${event.id}</small></div><time>${event.time}</time></div>`).join("") : '<p class="empty">No events yet. Submit a test order to see the workflow.</p>';
}
function addEvent(message, id, stage) {
  state.events.unshift({ message, id, stage, time: new Date().toLocaleTimeString([], { hour: "2-digit", minute: "2-digit", second: "2-digit" }) });
  render();
}
async function waitForProcessing(id) {
  if (!window.CLOUDORDER_API_URL) {
    await new Promise((resolve) => setTimeout(resolve, 1500));
    return { status: "PROCESSED" };
  }
  for (let attempt = 0; attempt < 12; attempt += 1) {
    await new Promise((resolve) => setTimeout(resolve, 1000));
    const response = await fetch(`${window.CLOUDORDER_API_URL}/orders/${id}`);
    if (response.ok) return response.json();
    if (response.status !== 404) throw new Error("Could not retrieve order status");
  }
  throw new Error("Order is taking longer than expected. Check the queue and Lambda logs.");
}
async function submitOrder() {
  const customer = $("#customer-id").value.trim();
  const quantity = Number($("#quantity").value);
  if (!customer || quantity < 1) return;
  const product = catalog[$("#sku").value];
  let id = `ord_${crypto.randomUUID().slice(0, 8)}`;
  const payload = { customer_id: customer, items: [{ sku: $("#sku").value, quantity, unit_price: product.price }] };
  if (window.CLOUDORDER_API_URL) {
    try {
      const response = await fetch(`${window.CLOUDORDER_API_URL}/orders`, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(payload) });
      if (!response.ok) throw new Error("The API rejected this order");
      id = (await response.json()).order_id;
    } catch (error) {
      alert(`Order could not be submitted: ${error.message}`);
      return;
    }
  }
  addEvent(`Order accepted for ${customer}`, id, "queued");
  $("#order-result").textContent = `${id}  •  202 Accepted`;
  $("#dialog-copy").textContent = `${quantity} × ${product.name} ($${(quantity * product.price).toFixed(2)}) has been validated and added to SQS.`;
  $("#result-dialog").showModal();
  try { await waitForProcessing(id); const event = state.events.find((item) => item.id === id); if (event) { event.stage = "done"; event.message = `Order processed and saved to DynamoDB`; state.processed += 1; localStorage.setItem("cloudorder-processed", state.processed); render(); } } catch (error) { const event = state.events.find((item) => item.id === id); if (event) { event.stage = "failed"; event.message = error.message; render(); } }
}
$("#order-form").addEventListener("submit", (event) => { event.preventDefault(); submitOrder(); });
$("#new-order").addEventListener("click", () => { $("#customer-id").focus(); window.scrollTo({ top: 250, behavior: "smooth" }); });
$(".close").addEventListener("click", () => $("#result-dialog").close());
$(".close-wide").addEventListener("click", () => $("#result-dialog").close());
render();
