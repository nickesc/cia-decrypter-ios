import assert from 'node:assert/strict';
import { access, readFile } from 'node:fs/promises';
import { resolve } from 'node:path';
import test from 'node:test';

const build = resolve('build');
const base = process.env.BASE_PATH || '';
const origin = 'https://pages.example';

test('static pages link to existing routes and assets under the Pages base path', async () => {
  for (const route of ['/', '/altstore/']) {
    const html = await readFile(resolve(build, `.${route}index.html`), 'utf8');
    const pageURL = new URL(`${base}${route}`, origin);
    assert.match(html, /<h1[\s>]/);

    for (const match of html.matchAll(/(?:href|src)="([^"]+)"/g)) {
      const url = new URL(match[1], pageURL);
      if (url.origin !== origin) continue;
      assert.ok(url.pathname.startsWith(`${base}/`), `${url} escapes the Pages base path`);
      const path = decodeURIComponent(url.pathname.slice(base.length));
      await access(resolve(build, `.${path}${path.endsWith('/') ? 'index.html' : ''}`));
    }
  }
});

test('AltStore opens the release feed displayed for manual setup', async () => {
  const html = await readFile(resolve(build, 'altstore/index.html'), 'utf8');
  const match = html.match(/href="(altstore:\/\/source\?url=[^"]+)"/);
  assert.ok(match, 'Missing Add to AltStore link');
  const source = new URL(match[1]).searchParams.get('url');
  assert.equal(source, 'https://github.com/nickesc/cia-decrypter-ios/releases/latest/download/source.json');
  assert.ok(html.includes(`<code>${source}</code>`), 'Manual and AltStore source URLs must agree');
});
