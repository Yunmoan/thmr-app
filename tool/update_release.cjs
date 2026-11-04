#!/usr/bin/env node
'use strict';
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');

function options(argv) {
  const result = {};
  for (let i = 0; i < argv.length; i += 2) {
    if (!argv[i].startsWith('--') || argv[i + 1] === undefined) throw new Error('Expected --name value');
    result[argv[i].slice(2)] = argv[i + 1];
  }
  return result;
}

function publicBytes(key) {
  return crypto.createPublicKey(key).export({ format: 'der', type: 'spki' }).subarray(-32).toString('base64');
}

async function createManifest(opt, env = process.env) {
  const version = opt.version;
  const build = Number(opt['build-number']);
  if (!/^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$/.test(version) ||
      !Number.isSafeInteger(build) || build < 1) throw new Error('A stable version and positive build number are required');
  const privatePem = env.THMR_UPDATE_PRIVATE_KEY;
  if (!privatePem) throw new Error('Configure THMR_UPDATE_PRIVATE_KEY (Ed25519 PKCS8 PEM)');
  const key = crypto.createPrivateKey(privatePem);
  if (key.asymmetricKeyType !== 'ed25519') throw new Error('Expected an Ed25519 key');
  const expectedKey = env.THMR_UPDATE_PUBLIC_KEY;
  if (!expectedKey || publicBytes(key) !== expectedKey) throw new Error('Signing key does not match THMR_UPDATE_PUBLIC_KEY');
  const base = new URL(opt['base-url']);
  if (base.protocol !== 'https:' || base.username || base.password) throw new Error('HTTPS artifact base URL required');
  const files = {
    'windows-x86_64': ['thmr-app-windows-x64.zip', 'zip'],
    'darwin-x86_64': ['thmr-app-macos-universal.zip', 'zip'],
    'darwin-aarch64': ['thmr-app-macos-universal.zip', 'zip'],
    'linux-x86_64': ['thmr-app-linux-x64.tar.gz', 'tar.gz'],
    'android-universal': ['thmr-app-android.apk', 'apk'],
  };
  const platforms = {};
  for (const [platform, [name, format]] of Object.entries(files)) {
    const file = path.join(opt.artifacts, name);
    const stat = fs.statSync(file);
    if (!stat.isFile() || stat.size < 1 || stat.size > 1073741824) throw new Error(`Invalid artifact: ${name}`);
    const hash = crypto.createHash('sha256');
    for await (const block of fs.createReadStream(file)) hash.update(block);
    platforms[platform] = { url: new URL(name, base.href.replace(/\/?$/, '/')).href,
      sha256: hash.digest('hex'), size: stat.size, format };
  }
  const notes = opt['notes-file'] ? fs.readFileSync(opt['notes-file'], 'utf8') : '客户端更新';
  if (notes.length > 65536) throw new Error('Release notes are too large');
  const data = { program: 'THMR', version, build_number: build, notes,
    pub_date: new Date().toISOString(), release_page: opt['release-page'] || 'https://thmr.yunmoan.cn', platforms };
  const bytes = Buffer.from(JSON.stringify(data));
  return { schema: 1, algorithm: 'ed25519', payload: bytes.toString('base64'),
    signature: crypto.sign(null, bytes, key).toString('base64') };
}

async function main() {
  const [command, ...args] = process.argv.slice(2);
  const opt = options(args);
  if (command === 'keygen') {
    if (!opt.output) throw new Error('Use --output .update-keys/thmr-ed25519.pem');
    const keys = crypto.generateKeyPairSync('ed25519');
    fs.mkdirSync(path.dirname(opt.output), { recursive: true });
    fs.writeFileSync(opt.output, keys.privateKey.export({ format: 'pem', type: 'pkcs8' }), { mode: 0o600, flag: 'wx' });
    console.log(publicBytes(keys.privateKey));
  } else if (command === 'manifest') {
    const envelope = await createManifest(opt);
    fs.writeFileSync(opt.output, JSON.stringify(envelope, null, 2) + '\n');
    console.log(`Signed THMR manifest: ${opt.output}`);
  } else if (command === 'publish') {
    const url = new URL(opt.url);
    if (url.protocol !== 'https:' || url.username || url.password) throw new Error('HTTPS publish URL required');
    const token = process.env.THMR_UPDATE_PUBLISH_TOKEN;
    if (!token || token.length < 32) throw new Error('Configure THMR_UPDATE_PUBLISH_TOKEN (at least 32 characters)');
    const envelope = JSON.parse(fs.readFileSync(opt.file, 'utf8'));
    const manifest = JSON.parse(Buffer.from(envelope.payload, 'base64').toString('utf8'));
    for (const artifact of new Map(Object.values(manifest.platforms).map(a => [a.url, a])).values()) {
      let available = false;
      for (let attempt = 0; attempt < 3 && !available; attempt++) {
        let assetUrl = new URL(artifact.url);
        for (let redirects = 0; redirects <= 5; redirects++) {
          if (assetUrl.protocol !== 'https:' || assetUrl.username || assetUrl.password) throw new Error('Invalid artifact URL');
          const head = await fetch(assetUrl, { method: 'HEAD', redirect: 'manual', signal: AbortSignal.timeout(20000) });
          if ([301, 302, 303, 307, 308].includes(head.status)) {
            const location = head.headers.get('location');
            if (!location) break;
            assetUrl = new URL(location, assetUrl); continue;
          }
          const length = head.headers.get('content-length');
          available = head.ok && (!length || Number(length) === artifact.size);
          break;
        }
        if (!available && attempt < 2) await new Promise(resolve => setTimeout(resolve, 2000));
      }
      if (!available) throw new Error('An update artifact is unavailable or has the wrong size; API publication stopped');
    }
    const response = await fetch(url, { method: 'POST', redirect: 'error',
      signal: AbortSignal.timeout(30000), headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${token}` },
      body: JSON.stringify(envelope) });
    if (!response.ok) throw new Error(`Update API publication failed (HTTP ${response.status})`);
    console.log('Update API published successfully');
  } else throw new Error('Commands: keygen, manifest, publish');
}

module.exports = { createManifest, publicBytes };
if (require.main === module) main().catch(error => { console.error(error.message); process.exitCode = 1; });
