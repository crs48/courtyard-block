import fs from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import config from '../astro.config.mjs';

const dist = fileURLToPath(new URL('../dist/', import.meta.url));
const base = `${config.base.replace(/\/$/, '')}/`;
const origin = new URL(config.site).origin;
const html = new Map();
const files = new Set();
async function walk(directory, prefix = '') {
  for (const entry of await fs.readdir(directory, {withFileTypes: true})) {
    const relative = path.posix.join(prefix, entry.name);
    if (entry.isDirectory()) await walk(path.join(directory, entry.name), relative);
    else {
      files.add(relative);
      // The exported Godot shell has its own canvas/loading markup, not site links.
      if (relative.endsWith('.html') && !relative.startsWith('game/')) html.set(relative, await fs.readFile(path.join(dist, relative), 'utf8'));
    }
  }
}
await walk(dist);
const errors = [];
let checked = 0;
for (const [file, source] of html) {
  const current = new URL(base + file.replace(/index\.html$/, ''), origin);
  for (const match of source.matchAll(/\b(?:href|src)="([^"]+)"/g)) {
    const value = match[1].replaceAll('&amp;', '&');
    if (/^(?:data:|mailto:|tel:|javascript:)/i.test(value)) continue;
    const target = new URL(value, current);
    if (target.origin !== origin) continue;
    checked++;
    if (!target.pathname.startsWith(base)) {errors.push(`${file}: URL escapes Pages base: ${value}`); continue;}
    let relative = decodeURIComponent(target.pathname.slice(base.length));
    if (!relative || relative.endsWith('/')) relative += 'index.html';
    if (!files.has(relative)) {errors.push(`${file}: missing target: ${value}`); continue;}
    if (target.hash && html.has(relative)) {
      const id = decodeURIComponent(target.hash.slice(1));
      const attributes = [...html.get(relative).matchAll(/\bid="([^"]+)"/g)].map((entry) => entry[1]);
      if (!attributes.includes(id)) errors.push(`${file}: missing heading: ${value}`);
    }
  }
}
if (errors.length) {console.error(errors.join('\n')); process.exit(1);}
console.log(`Verified ${checked} local links/assets across ${html.size} website pages under ${base}.`);
