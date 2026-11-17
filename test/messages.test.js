'use strict';
// Tests fuer die eine Anpassung an Claude-Code-Anfragen: Eintraege mit
// role "system" in der Nachrichtenliste werden zu Text in einer Nutzernachricht.
//   node --test

const test = require('node:test');
const assert = require('node:assert/strict');
const { systemTurnsToUser } = require('../bridge.js');

const wrapped = (text) => `<system-reminder>\n${text}\n</system-reminder>`;

test('ohne system-Eintrag bleibt die Anfrage dasselbe Objekt', () => {
  const body = { model: 'anthropic/claude-haiku-4-5', messages: [{ role: 'user', content: 'hi' }] };
  const result = systemTurnsToUser(body);
  assert.equal(result.body, body);
  assert.equal(result.moved, 0);
});

test('system nach einer Nutzernachricht wird an diese angehaengt', () => {
  const body = {
    model: 'anthropic/claude-sonnet-5-5',
    system: [{ type: 'text', text: 'Grundregeln' }],
    messages: [
      { role: 'user', content: [{ type: 'text', text: 'Hallo', cache_control: { type: 'ephemeral' } }] },
      { role: 'system', content: '# Environment' },
    ],
  };
  const { body: out, moved } = systemTurnsToUser(body);
  assert.equal(moved, 1);
  assert.deepEqual(out.messages, [{ role: 'user', content: [
    { type: 'text', text: 'Hallo', cache_control: { type: 'ephemeral' } },
    { type: 'text', text: wrapped('# Environment') },
  ] }]);
  assert.deepEqual(out.system, body.system, 'der system-Block oben bleibt unberuehrt');
  assert.equal(body.messages.length, 2, 'die Eingabe wird nicht veraendert');
  assert.equal(body.messages[0].content.length, 1);
});

test('Text einer Nutzernachricht als String wird zur Blockliste', () => {
  const { body: out } = systemTurnsToUser({ messages: [
    { role: 'user', content: 'Hallo' },
    { role: 'system', content: [{ type: 'text', text: 'Hinweis', cache_control: { type: 'ephemeral' } }] },
  ] });
  assert.deepEqual(out.messages[0].content, [
    { type: 'text', text: 'Hallo' },
    { type: 'text', text: wrapped('Hinweis'), cache_control: { type: 'ephemeral' } },
  ]);
});

test('system nach einem Werkzeugaufruf landet hinter den Werkzeugergebnissen', () => {
  const { body: out, moved } = systemTurnsToUser({ messages: [
    { role: 'user', content: 'Lies die Datei' },
    { role: 'assistant', content: [{ type: 'tool_use', id: 'toolu_1', name: 'Read', input: {} }] },
    { role: 'system', content: 'Werkzeugliste hat sich geaendert' },
    { role: 'user', content: [
      { type: 'tool_result', tool_use_id: 'toolu_1', content: 'Inhalt' },
      { type: 'text', text: 'weiter' },
    ] },
  ] });
  assert.equal(moved, 1);
  assert.deepEqual(out.messages.map((m) => m.role), ['user', 'assistant', 'user']);
  assert.deepEqual(out.messages[2].content.map((b) => b.type), ['tool_result', 'text', 'text']);
  assert.equal(out.messages[2].content[1].text, wrapped('Werkzeugliste hat sich geaendert'));
});

test('mehrere system-Eintraege und einer ganz am Ende', () => {
  const { body: out, moved } = systemTurnsToUser({ messages: [
    { role: 'user', content: 'eins' },
    { role: 'system', content: 'A' },
    { role: 'system', content: 'B' },
    { role: 'assistant', content: 'Antwort' },
    { role: 'system', content: 'C' },
  ] });
  assert.equal(moved, 3);
  assert.deepEqual(out.messages.map((m) => m.role), ['user', 'assistant', 'user']);
  assert.deepEqual(out.messages[0].content.map((b) => b.text), ['eins', wrapped('A'), wrapped('B')]);
  assert.deepEqual(out.messages[2].content, [{ type: 'text', text: wrapped('C') }]);
});

test('leere system-Eintraege verschwinden ohne Spur', () => {
  const { body: out, moved } = systemTurnsToUser({ messages: [
    { role: 'user', content: 'eins' },
    { role: 'system', content: '   ' },
  ] });
  assert.equal(moved, 1);
  assert.deepEqual(out.messages, [{ role: 'user', content: [{ type: 'text', text: 'eins' }] }]);
});
