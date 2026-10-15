// Regression test for the Gemini "missing thought_signature" bug: when the
// model returns a functionCall part carrying a thoughtSignature, the agent must
// push that part back into the conversation VERBATIM, or the next turn fails.

import { test } from "node:test";
import assert from "node:assert/strict";
import { Vault } from "../src/service.mjs";

function makeVault(aiTurns) {
  const sent = [];
  const bot = {
    async call(method, params) {
      if (method === "getBusinessConnection") return { id: params.business_connection_id, user: { id: 7 } };
      sent.push({ method, params });
      return {};
    },
  };
  const db = {
    chats: async () => [{ chat_title: "History", messages: 3 }],
    search: async () => [{ chat_title: "History", is_outgoing: false, text: "salom aka", deleted_at: null }],
  };
  let turnIndex = 0;
  const received = [];
  const ai = {
    async turn({ contents }) {
      received.push(JSON.parse(JSON.stringify(contents)));   // snapshot what the model is sent
      return aiTurns[turnIndex++];
    },
  };
  const vault = new Vault({ config: { ownerId: 7, geminiKeys: [], apiToken: "t" }, bot, db, log: {} });
  vault.ai = ai;
  return { vault, sent, received };
}

test("the model's functionCall part (with thoughtSignature) is sent back verbatim", async () => {
  const toolTurn = {
    role: "model",
    parts: [{ functionCall: { name: "search_messages", args: { query: "salom" } }, thoughtSignature: "SIG-123" }],
  };
  const finalTurn = { role: "model", parts: [{ text: "Topildi: salom aka" }] };
  const { vault, sent, received } = makeVault([toolTurn, finalTurn]);

  await vault.runAgent("salom so'zini qidir");

  // The second model call must have received history containing the EXACT
  // functionCall part, thoughtSignature intact.
  const secondCallHistory = received[1];
  const modelTurn = secondCallHistory.find((c) => c.role === "model" && c.parts.some((p) => p.functionCall));
  assert.ok(modelTurn, "model's tool turn must be in history");
  const fcPart = modelTurn.parts.find((p) => p.functionCall);
  assert.equal(fcPart.thoughtSignature, "SIG-123", "thoughtSignature must be preserved verbatim");
  // And a functionResponse must follow.
  const respTurn = secondCallHistory.find((c) => c.parts.some((p) => p.functionResponse));
  assert.ok(respTurn, "a functionResponse must be sent back");
  // The final answer reaches the owner.
  assert.ok(sent.some((m) => m.method === "sendMessage" && /Topildi/.test(m.params.text)));
});
