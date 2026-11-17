'use strict';
// Tests fuer die Uebersetzung Responses <-> Chat Completions. Laufen ohne Netz:
//   node --test

const test = require('node:test');
const assert = require('node:assert/strict');
const bridge = require('../bridge.js');

const MODEL = 'anthropic/claude-sonnet-5-5';

function parseSse(parts) {
  return parts.map((part) => {
    const [eventLine, dataLine] = part.trim().split('\n');
    return { event: eventLine.replace('event: ', ''), data: JSON.parse(dataLine.replace('data: ', '')) };
  });
}

test('Kurznamen werden aufgeloest, Gateway-IDs gehen unveraendert durch', () => {
  const aliases = { opus: 'anthropic/claude-opus-5-5' };
  assert.equal(bridge.resolveModel('opus', aliases), 'anthropic/claude-opus-5-5');
  assert.equal(bridge.resolveModel('mistral/mistral-medium-3-5', aliases), 'mistral/mistral-medium-3-5');
  assert.throws(() => bridge.resolveModel('', aliases), (exc) => exc.status === 400);
});

test('models.json im Paket ist lesbar und zeigt auf Gateway-IDs', () => {
  const aliases = bridge.loadAliases();
  assert.ok(Object.keys(aliases).length > 0);
  for (const target of Object.values(aliases)) assert.match(target, /^[a-z0-9_.-]+\/.+/i);
});

test('Anfrage: Rollen, Text und Parameter', () => {
  const { payload } = bridge.responsesToChatPayload({
    instructions: 'Grundregeln',
    input: [
      { type: 'message', role: 'developer', content: [{ type: 'input_text', text: 'Du bist ein Coding-Agent.' }] },
      { type: 'message', role: 'user', content: [{ type: 'input_text', text: 'Hallo' }] },
      { type: 'reasoning', summary: [] },
      { type: 'message', role: 'assistant', content: [{ type: 'output_text', text: 'Hi' }] },
    ],
    max_output_tokens: 500,
    temperature: 0.2,
    stream: true,
  }, MODEL);
  assert.equal(payload.model, MODEL);
  assert.equal(payload.stream, false, 'der Gateway wird immer ohne Streaming aufgerufen');
  assert.deepEqual(payload.messages, [
    { role: 'system', content: 'Grundregeln' },
    { role: 'system', content: 'Du bist ein Coding-Agent.' },
    { role: 'user', content: 'Hallo' },
    { role: 'assistant', content: 'Hi' },
  ]);
  assert.equal(payload.max_tokens, 500);
  assert.equal(payload.temperature, 0.2);
  assert.equal(payload.tools, undefined);
});

test('Anfrage: einfacher Text als input', () => {
  const { payload } = bridge.responsesToChatPayload({ input: 'Sag OK' }, MODEL);
  assert.deepEqual(payload.messages, [{ role: 'user', content: 'Sag OK' }]);
});

test('Anfrage: Werkzeugaufrufe und Ergebnisse bleiben in der Reihenfolge', () => {
  const { payload } = bridge.responsesToChatPayload({
    input: [
      { type: 'message', role: 'user', content: [{ type: 'input_text', text: 'Lies zwei Dateien' }] },
      { type: 'function_call', call_id: 'call_1', name: 'exec_command', arguments: '{"cmd":"cat a"}' },
      { type: 'function_call', call_id: 'call_2', name: 'exec_command', arguments: '{"cmd":"cat b"}' },
      { type: 'function_call_output', call_id: 'call_1', output: 'Inhalt a' },
      { type: 'function_call_output', call_id: 'call_2', output: [{ type: 'input_text', text: 'Inhalt b' }] },
    ],
    tools: [{ type: 'function', name: 'exec_command', description: 'Befehl', parameters: { type: 'object' } }],
    tool_choice: 'auto',
  }, MODEL);
  const [, assistant, first, second] = payload.messages;
  assert.equal(assistant.role, 'assistant');
  assert.deepEqual(assistant.tool_calls.map((tc) => tc.id), ['call_1', 'call_2'], 'parallele Aufrufe stehen in einer Nachricht');
  assert.deepEqual(first, { role: 'tool', tool_call_id: 'call_1', content: 'Inhalt a' });
  assert.deepEqual(second, { role: 'tool', tool_call_id: 'call_2', content: 'Inhalt b' });
  assert.deepEqual(payload.tools, [{ type: 'function', function: { name: 'exec_command', description: 'Befehl', parameters: { type: 'object' } } }]);
  assert.equal(payload.tool_choice, 'auto');
});

test('Anfrage: Bilder werden zu image_url-Teilen', () => {
  const { payload } = bridge.responsesToChatPayload({
    input: [{ type: 'message', role: 'user', content: [
      { type: 'input_text', text: 'Was zeigt das Bild?' },
      { type: 'input_image', image_url: 'data:image/png;base64,AAAA' },
    ] }],
  }, MODEL);
  assert.deepEqual(payload.messages[0].content, [
    { type: 'text', text: 'Was zeigt das Bild?' },
    { type: 'image_url', image_url: { url: 'data:image/png;base64,AAAA' } },
  ]);
});

test('Anfrage: Namensraeume werden flach, Server-Werkzeuge fallen weg', () => {
  const { payload, toolNames } = bridge.responsesToChatPayload({
    input: [
      { type: 'message', role: 'user', content: 'Frag den MCP-Server' },
      { type: 'function_call', call_id: 'call_9', namespace: 'mcp__auxdata__', name: 'search_knowledge', arguments: '{}' },
      { type: 'function_call_output', call_id: 'call_9', output: 'Treffer' },
    ],
    tools: [
      { type: 'namespace', name: 'mcp__auxdata__', description: 'AuxData', tools: [
        { type: 'function', name: 'search_knowledge', description: 'Suche', parameters: { type: 'object' } },
        { type: 'function', name: 'chat', parameters: { type: 'object' } },
      ] },
      { type: 'namespace', name: 'multi_agent_v1', tools: [{ type: 'function', name: 'spawn_agent' }] },
      { type: 'web_search', external_web_access: false },
    ],
  }, MODEL);
  assert.deepEqual(payload.tools.map((t) => t.function.name), ['mcp__auxdata__search_knowledge', 'mcp__auxdata__chat', 'multi_agent_v1__spawn_agent']);
  assert.equal(payload.messages[1].tool_calls[0].function.name, 'mcp__auxdata__search_knowledge', 'der Verlauf nutzt denselben flachen Namen');
  assert.deepEqual(toolNames.namespaced.get('multi_agent_v1__spawn_agent'), { namespace: 'multi_agent_v1', name: 'spawn_agent' });
});

test('Flache Werkzeugnamen bleiben gueltig und hoechstens 64 Zeichen lang', () => {
  const taken = new Map();
  const flat = bridge.flatToolName('mcp__ein_sehr_langer_servername_mit_vielen_zeichen__', 'ein_ebenfalls_sehr_langer_werkzeugname_mit_umlaut_ä', taken);
  assert.ok(flat.length <= 64);
  assert.match(flat, /^[a-zA-Z0-9_-]+$/);
});

test('Anfrage: Freiform-Werkzeug wird zur Funktion mit einem Textfeld', () => {
  const { payload, toolNames } = bridge.responsesToChatPayload({
    input: [
      { type: 'message', role: 'user', content: 'Aendere die Datei' },
      { type: 'custom_tool_call', call_id: 'call_3', name: 'apply_patch', input: '*** Begin Patch' },
      { type: 'custom_tool_call_output', call_id: 'call_3', output: 'Done' },
    ],
    tools: [{ type: 'custom', name: 'apply_patch', description: 'Patch anwenden' }],
  }, MODEL);
  assert.deepEqual(payload.tools[0].function.parameters.required, ['input']);
  assert.equal(payload.messages[1].tool_calls[0].function.arguments, '{"input":"*** Begin Patch"}');
  assert.deepEqual(payload.messages[2], { role: 'tool', tool_call_id: 'call_3', content: 'Done' });
  assert.ok(toolNames.customNames.has('apply_patch'));
});

test('Anfrage: bei Gemini 4 Argon geht der Werkzeugverlauf als Text mit', () => {
  const body = {
    input: [
      { type: 'message', role: 'user', content: 'Lies a' },
      { type: 'function_call', call_id: 'call_1', name: 'exec_command', arguments: '{}' },
      { type: 'function_call_output', call_id: 'call_1', output: 'Inhalt a' },
    ],
  };
  const argon = bridge.responsesToChatPayload(body, 'google/gemini-4-argon').payload.messages;
  assert.equal(argon[1].tool_calls, undefined);
  assert.match(argon[1].content, /Previously requested tool calls/);
  assert.equal(argon[2].role, 'user');
  const andere = bridge.responsesToChatPayload(body, MODEL).payload.messages;
  assert.ok(andere[1].tool_calls, 'andere Modelle behalten die echten Werkzeugaufrufe');
});

test('Antwort: Text und Werkzeugaufruf des Gateways werden gelesen', () => {
  const data = {
    choices: [{ finish_reason: 'tool_calls', message: { role: 'assistant', content: 'Ich lese die Datei.', tool_calls: [
      { id: 'call_7', type: 'function', function: { name: 'exec_command', arguments: '{"cmd":"cat a"}' } },
    ] } }],
    usage: { prompt_tokens: 120, completion_tokens: 30 },
  };
  const { answer, toolCalls } = bridge.parseChatResponse(data);
  const usage = bridge.usageFromChat(data);
  assert.equal(usage.input_tokens, 120);
  assert.equal(usage.output_tokens, 30);
  assert.equal(usage.total_tokens, 150);
  const response = bridge.responsesObject(answer, MODEL, usage, toolCalls, null);
  assert.equal(response.status, 'completed');
  assert.equal(response.output[0].type, 'message');
  assert.equal(response.output[0].content[0].text, 'Ich lese die Datei.');
  assert.equal(response.output[1].type, 'function_call');
  assert.equal(response.output[1].call_id, 'call_7');
  assert.equal(response.output[1].arguments, '{"cmd":"cat a"}');
});

test('Antwort: Namensraum und Freiform-Werkzeug werden zurueckuebersetzt', () => {
  const { toolNames } = bridge.responsesToChatPayload({
    input: 'x',
    tools: [
      { type: 'namespace', name: 'multi_agent_v1', tools: [{ type: 'function', name: 'close_agent' }] },
      { type: 'custom', name: 'apply_patch' },
    ],
  }, MODEL);
  const response = bridge.responsesObject('', MODEL, {}, [
    { id: 'c1', function: { name: 'multi_agent_v1__close_agent', arguments: '{"id":"a"}' } },
    { id: 'c2', function: { name: 'apply_patch', arguments: '{"input":"*** Begin Patch"}' } },
  ], toolNames);
  assert.deepEqual(
    { type: response.output[0].type, namespace: response.output[0].namespace, name: response.output[0].name },
    { type: 'function_call', namespace: 'multi_agent_v1', name: 'close_agent' },
  );
  assert.deepEqual(
    { type: response.output[1].type, name: response.output[1].name, input: response.output[1].input },
    { type: 'custom_tool_call', name: 'apply_patch', input: '*** Begin Patch' },
  );
});

test('Antwort: leere Antwort ergibt trotzdem eine Nachricht', () => {
  const response = bridge.responsesObject('', MODEL, {}, [], null);
  assert.equal(response.output.length, 1);
  assert.equal(response.output[0].content[0].text, '');
});

test('Stream: Ereignisse in der Reihenfolge, die Codex erwartet', () => {
  const events = parseSse(bridge.streamResponses('Fertig. '.repeat(30), MODEL, { input_tokens: 1, output_tokens: 2, total_tokens: 3 }, [
    { id: 'call_1', function: { name: 'exec_command', arguments: '{"cmd":"ls"}' } },
  ], null));
  const names = events.map((e) => e.event);
  assert.equal(names[0], 'response.created');
  assert.equal(names[1], 'response.in_progress');
  assert.equal(names.at(-1), 'response.completed');
  assert.ok(names.filter((n) => n === 'response.output_text.delta').length > 1, 'langer Text kommt in mehreren Stuecken');
  assert.ok(names.includes('response.function_call_arguments.done'));
  assert.deepEqual(events.map((e) => e.data.sequence_number), events.map((_, i) => i + 1));
  for (const e of events) assert.equal(e.data.type, e.event);
  const done = events.at(-1).data.response;
  assert.equal(done.status, 'completed');
  assert.equal(done.output.length, 2);
  assert.equal(done.usage.total_tokens, 3);
  const text = events.filter((e) => e.event === 'response.output_text.delta').map((e) => e.data.delta).join('');
  assert.equal(text, 'Fertig. '.repeat(30));
});

test('Fehlertexte des Gateways werden lesbar', () => {
  assert.equal(bridge.upstreamErrorMessage('{"error":{"message":"Model not found or not permitted"}}'), 'Model not found or not permitted');
  assert.equal(bridge.upstreamErrorMessage('{"error":"kaputt"}'), 'kaputt');
  assert.equal(bridge.upstreamErrorMessage('404 page not found'), '404 page not found');
});
