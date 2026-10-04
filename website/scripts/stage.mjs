import fs from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {execFileSync} from 'node:child_process';

const site = fileURLToPath(new URL('../', import.meta.url));
const root = path.resolve(site, '..');
const game = path.join(root, 'exports/web');
const destination = path.join(site, 'public');
for (const name of ['index.html', 'index.js', 'index.wasm', 'index.pck', 'THIRD_PARTY_LICENSES.txt']) {
  try {await fs.access(path.join(game, name));}
  catch {throw new Error(`Missing exports/web/${name}. Run python3 scripts/build_web.py from the repository root first.`);}
}
await fs.rm(path.join(destination, 'game'), {recursive: true, force: true});
await fs.cp(game, path.join(destination, 'game'), {recursive: true});
await fs.copyFile(path.join(root, 'LICENSE'), path.join(destination, 'game/LICENSE.txt'));
const downloads = path.join(destination, 'downloads');
await fs.mkdir(downloads, {recursive: true});
await fs.copyFile(path.join(root, 'schemas/lab-pack.schema.json'), path.join(downloads, 'lab-pack.schema.json'));
await fs.copyFile(path.join(root, 'mods/lab_hemp/manifest.json'), path.join(downloads, 'hemp-manifest.json'));
execFileSync('python3', [path.join(root, 'scripts/package_mod.py'), path.join(root, 'mods/lab_hemp'), '--output', downloads], {stdio: 'inherit'});

// Preserve the installed packages' actual notice texts, including transitive libraries.
const lock = JSON.parse(await fs.readFile(path.join(site, 'package-lock.json'), 'utf8'));
const sections = ['COURTYARD BLOCK WEBSITE — THIRD-PARTY NOTICES\n\nOriginal project: Copyright (c) 2026 Christopher Smothers, MIT.\nDependencies retain their individual copyrights and licenses.'];
for (const directory of Object.keys(lock.packages).filter(Boolean).sort()) {
  const packageRoot = path.join(site, directory);
  let files;
  try {files = await fs.readdir(packageRoot, {withFileTypes: true});} catch {continue;}
  const info = JSON.parse(await fs.readFile(path.join(packageRoot, 'package.json'), 'utf8'));
  sections.push(`\n${'='.repeat(72)}\n${info.name} ${info.version}\nDeclared license: ${JSON.stringify(info.license || info.licenses || 'See package notices')}\n`);
  for (const file of files.filter((entry) => /^(?:licen[sc]e|copying|notice|ofl)(?:[._-]|$)/i.test(entry.name))) {
    const location = path.join(packageRoot, file.name);
    if (file.isFile()) sections.push(await fs.readFile(location, 'utf8'));
    else if (file.isDirectory()) {
      for (const child of await fs.readdir(location, {withFileTypes: true})) {
        if (child.isFile()) sections.push(await fs.readFile(path.join(location, child.name), 'utf8'));
      }
    }
  }
}
await fs.writeFile(path.join(downloads, 'WEBSITE_NOTICES.txt'), sections.join('\n'));
console.log('Staged browser game, mod downloads and third-party notices.');
