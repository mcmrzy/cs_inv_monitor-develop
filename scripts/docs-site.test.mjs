import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import test from 'node:test';

const site = resolve(process.env.DOCS_SITE_DIR || '_site');

test('project Pages redirect stays inside the repository base path', () => {
  const html = readFileSync(resolve(site, 'index.html'), 'utf8');
  assert.ok(html.includes('url=./docs/swagger/'));
  assert.ok(html.includes('href="./docs/swagger/"'));
  const base = new URL('https://example.github.io/repository/');
  assert.equal(new URL('./docs/swagger/', base).pathname, '/repository/docs/swagger/');
});

test('Swagger page and its relative OpenAPI document are both published', () => {
  const html = readFileSync(resolve(site, 'docs/swagger/index.html'), 'utf8');
  assert.ok(html.includes('SwaggerUIBundle({'));
  assert.ok(html.includes('url: "./openapi.yaml"'));
  const spec = readFileSync(resolve(site, 'docs/swagger/openapi.yaml'), 'utf8');
  assert.match(spec, /^openapi:\s*["']?3\./m);
});

test('all pinned Swagger resources retain valid SHA-384 integrity values', () => {
  const html = readFileSync(resolve(site, 'docs/swagger/index.html'), 'utf8');
  const hashes = [...html.matchAll(/integrity="sha384-([^"]+)"/g)];
  assert.equal(hashes.length, 3);
  for (const [, hash] of hashes) {
    assert.match(hash, /^[A-Za-z0-9+/]{64}$/);
    assert.equal(Buffer.from(hash, 'base64').length, 48);
  }
});
