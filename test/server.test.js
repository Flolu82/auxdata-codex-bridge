'use strict';
// Tests fuer den HTTP-Teil der Bridge. Statt AuxData antwortet ein kleiner
// Platzhalter-Server auf diesem Rechner; es geht nichts ins Netz.
//   node --test

const test = require('node:test');
const assert = require('node:assert/strict');
const http = require('node:http');

const seen = []; // was der Platzhalter-Gateway empfangen hat
let gateway;
let bridgeServer;
let bridgeUrl;

function listen(server) {
  return new Promise((resolve) => server.listen(0, '127.0.0.1', () => resolve(server.address().port)));
}

test.before(async () => {
  gateway = http.createServer((req, res) => {
    const chunks = [];
    req.on('data', (c) => chunks.push(c));
    req.on('end', () => {
      const body = chunks.length ? JSON.parse(Buffer.concat(chunks).toString('utf8')) : null;
      seen.push({ method: req.method, url: req.url, authorization: req.headers.authorization, headers: req.headers, body });
      if (req.url.startsWith('/v1/messages')) {
        if (body && body.model === 'anthropic/gibt-es-nicht') {
          res.writeHead(404, { 'Content-Type': 'application/json' });
          return res.end(JSON.stringify({ type: 'error', error: { type: 'not_found_error', message: 'Model not found or not permitted' } }));
        }
        if (body && body.stream) {
          res.writeHead(200, { 'Content-Type': 'text/event-stream' });
          res.write('event: message_start\ndata: {"type":"message_start"}\n\n');
          return res.end('event: message_stop\ndata: {"type":"message_stop"}\n\n');
        }
        res.writeHead(200, { 'Content-Type': 'application/json' });
        return res.end(JSON.stringify({ type: 'message', role: 'assistant', content: [{ type: 'text', text: 'OK' }] }));
      }
      res.setHeader('Content-Type', 'application/json');
      if (req.url === '/v1/models') {
        return res.end(JSON.stringify({ object: 'list', data: [{ id: 'anthropic/claude-sonnet-5-5', object: 'model' }] }));
      }
      if (body && body.model === 'gibt/es-nicht') {
        res.statusCode = 404;
        return res.end(JSON.stringify({ error: { message: 'Model not found or not permitted' } }));
      }
      return res.end(JSON.stringify({
        choices: [{ finish_reason: 'stop', message: { role: 'assistant', content: 'OK' } }],
        usage: { prompt_tokens: 7, completion_tokens: 1 },
      }));
    });
  });
  const gatewayPort = await listen(gateway);
  process.env.AUXDATA_BASE_URL = `http://127.0.0.1:${gatewayPort}`;
  const bridge = require('../bridge.js');
  bridgeServer = bridge.createServer();
  bridgeUrl = `http://127.0.0.1:${await listen(bridgeServer)}`;
});

test.after(() => {
  bridgeServer.close();
  gateway.close();
});

const AUTH = { Authorization: 'Bearer sk-auxdata-testschluessel', 'Content-Type': 'application/json' };

test('/health antwortet ohne Schluessel und verraet keinen', async () => {
  const health = await (await fetch(`${bridgeUrl}/health`)).json();
  assert.equal(health.ok, true);
  assert.equal(health.service, 'auxdata-codex-bridge');
  assert.doesNotMatch(JSON.stringify(health), /sk-auxdata/);
});

test('ohne Authorization-Header kommt 401, der Gateway wird nicht gefragt', async () => {
  const before = seen.length;
  const resp = await fetch(`${bridgeUrl}/v1/responses`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ model: 'x/y', input: 'hi' }) });
  assert.equal(resp.status, 401);
  assert.equal((await resp.json()).error.type, 'authentication_error');
  assert.equal(seen.length, before);
});

test('der Schluessel des Clients geht unveraendert an den Gateway', async () => {
  const resp = await fetch(`${bridgeUrl}/v1/responses`, { method: 'POST', headers: AUTH, body: JSON.stringify({ model: 'anthropic/claude-sonnet-5-5', input: 'Sag OK' }) });
  assert.equal(resp.status, 200);
  const data = await resp.json();
  assert.equal(data.output_text, 'OK');
  assert.equal(data.usage.input_tokens, 7);
  const call = seen.at(-1);
  assert.equal(call.url, '/v1/chat/completions');
  assert.equal(call.authorization, 'Bearer sk-auxdata-testschluessel');
  assert.equal(call.body.model, 'anthropic/claude-sonnet-5-5');
  assert.deepEqual(call.body.messages, [{ role: 'user', content: 'Sag OK' }]);
});

test('Kurzname aus models.json wird vor dem Aufruf aufgeloest', async () => {
  await fetch(`${bridgeUrl}/v1/responses`, { method: 'POST', headers: AUTH, body: JSON.stringify({ model: 'opus', input: 'hi' }) });
  assert.equal(seen.at(-1).body.model, 'anthropic/claude-opus-5-5');
});

test('stream=true liefert Server-Sent Events bis response.completed', async () => {
  const resp = await fetch(`${bridgeUrl}/v1/responses`, { method: 'POST', headers: AUTH, body: JSON.stringify({ model: 'anthropic/claude-sonnet-5-5', input: 'Sag OK', stream: true }) });
  assert.match(resp.headers.get('content-type'), /text\/event-stream/);
  const text = await resp.text();
  assert.match(text, /^event: response\.created/);
  assert.match(text, /event: response\.completed/);
});

test('Fehler des Gateways behalten ihren Statuscode', async () => {
  const resp = await fetch(`${bridgeUrl}/v1/responses`, { method: 'POST', headers: AUTH, body: JSON.stringify({ model: 'gibt/es-nicht', input: 'hi' }) });
  assert.equal(resp.status, 404);
  assert.match((await resp.json()).error.message, /Model not found or not permitted/);
});

test('/v1/models reicht die Liste des Gateways durch', async () => {
  const resp = await fetch(`${bridgeUrl}/v1/models`, { headers: AUTH });
  assert.equal(resp.status, 200);
  assert.equal((await resp.json()).data[0].id, 'anthropic/claude-sonnet-5-5');
  assert.equal(seen.at(-1).authorization, 'Bearer sk-auxdata-testschluessel');
});

test('unbekannte Pfade geben 404', async () => {
  const resp = await fetch(`${bridgeUrl}/v1/embeddings`, { method: 'POST', headers: AUTH, body: '{}' });
  assert.equal(resp.status, 404);
});

// --- Claude Code: /v1/messages wird durchgereicht ---------------------------

const CLAUDE_HEADERS = { ...AUTH, 'anthropic-version': '2023-06-01', 'anthropic-beta': 'claude-code-20250219' };

test('/v1/messages geht mit Schluessel, Query und Anthropic-Headern an den Gateway', async () => {
  const request = {
    model: 'anthropic/claude-sonnet-5-5',
    max_tokens: 100,
    thinking: { type: 'adaptive' },
    system: [{ type: 'text', text: 'Du bist Claude Code.' }],
    messages: [
      { role: 'user', content: [{ type: 'text', text: 'Hallo' }] },
      { role: 'system', content: '# Environment\nOrdner: /tmp/projekt' },
    ],
  };
  const resp = await fetch(`${bridgeUrl}/v1/messages?beta=true`, { method: 'POST', headers: CLAUDE_HEADERS, body: JSON.stringify(request) });
  assert.equal(resp.status, 200);
  assert.deepEqual(await resp.json(), { type: 'message', role: 'assistant', content: [{ type: 'text', text: 'OK' }] }, 'die Antwort kommt unveraendert zurueck');
  const call = seen.at(-1);
  assert.equal(call.url, '/v1/messages?beta=true');
  assert.equal(call.authorization, 'Bearer sk-auxdata-testschluessel');
  assert.equal(call.headers['anthropic-version'], '2023-06-01');
  assert.equal(call.headers['anthropic-beta'], 'claude-code-20250219');
  assert.deepEqual(call.body.messages.map((m) => m.role), ['user'], 'kein Eintrag mit role "system" mehr');
  assert.match(call.body.messages[0].content[1].text, /^<system-reminder>\n# Environment/);
  assert.deepEqual(call.body.thinking, { type: 'adaptive' }, 'alles andere bleibt, wie es war');
  assert.deepEqual(call.body.system, request.system);
});

test('/v1/messages nimmt den Schluessel auch als x-api-key', async () => {
  const resp = await fetch(`${bridgeUrl}/v1/messages`, {
    method: 'POST',
    headers: { 'x-api-key': 'sk-auxdata-testschluessel', 'Content-Type': 'application/json' },
    body: JSON.stringify({ model: 'anthropic/claude-haiku-4-5', max_tokens: 10, messages: [{ role: 'user', content: 'hi' }] }),
  });
  assert.equal(resp.status, 200);
  assert.equal(seen.at(-1).headers['x-api-key'], 'sk-auxdata-testschluessel');
});

test('/v1/messages ohne Schluessel gibt 401 im Anthropic-Format', async () => {
  const before = seen.length;
  const resp = await fetch(`${bridgeUrl}/v1/messages`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ model: 'x', messages: [] }) });
  assert.equal(resp.status, 401);
  const data = await resp.json();
  assert.equal(data.type, 'error');
  assert.equal(data.error.type, 'authentication_error');
  assert.equal(seen.length, before);
});

test('/v1/messages reicht einen Stream unveraendert durch', async () => {
  const resp = await fetch(`${bridgeUrl}/v1/messages`, {
    method: 'POST', headers: CLAUDE_HEADERS,
    body: JSON.stringify({ model: 'anthropic/claude-sonnet-5-5', max_tokens: 10, stream: true, messages: [{ role: 'user', content: 'hi' }] }),
  });
  assert.match(resp.headers.get('content-type'), /text\/event-stream/);
  assert.equal(await resp.text(), 'event: message_start\ndata: {"type":"message_start"}\n\nevent: message_stop\ndata: {"type":"message_stop"}\n\n');
});

test('/v1/messages gibt Fehler des Gateways mit Status und Text weiter', async () => {
  const resp = await fetch(`${bridgeUrl}/v1/messages`, {
    method: 'POST', headers: CLAUDE_HEADERS,
    body: JSON.stringify({ model: 'anthropic/gibt-es-nicht', max_tokens: 10, messages: [{ role: 'user', content: 'hi' }] }),
  });
  assert.equal(resp.status, 404);
  assert.equal((await resp.json()).error.message, 'Model not found or not permitted');
});
