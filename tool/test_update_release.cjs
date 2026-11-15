const { test } = require('node:test');
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { execFileSync, spawnSync } = require('node:child_process');
const { createManifest, inspectManifest, publicBytes, releaseNotes } = require('./update_release.cjs');

test('workflow permits unsigned previews but enforces signing for tags and configured keys', {
  skip: process.platform === 'win32' && !process.env.THMR_TEST_BASH,
}, async t => {
  const workflow = fs.readFileSync(path.join(__dirname, '../.github/workflows/build.yml'), 'utf8').replace(/\r\n/g, '\n');
  const step = workflow.split('      - name: Sign the updater manifest')[1].split('      - name:')[0];
  const script = step.split('        run: |')[1].replace(/^ {10}/gm, '');
  const { privateKey } = crypto.generateKeyPairSync('ed25519');
  const pem = privateKey.export({ type: 'pkcs8', format: 'pem' });
  const publicKey = publicBytes(privateKey);
  for (const [name, refType, privatePem, publicValue, succeeds, signed] of [
    ['unconfigured preview', 'branch', '', '', true, false],
    ['unconfigured tag', 'tag', '', '', false, false],
    ['public key only', 'branch', '', publicKey, false, false],
    ['private key only', 'branch', pem, '', false, false],
    ['mismatched keys', 'branch', pem, Buffer.alloc(32).toString('base64'), false, false],
    ['configured preview', 'branch', pem, publicKey, true, true],
    ['configured tag', 'tag', pem, publicKey, true, true],
  ]) {
    await t.test(name, () => {
      const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'thmr-signing-'));
      try {
        fs.mkdirSync(path.join(directory, 'tool'));
        fs.copyFileSync(path.join(__dirname, 'update_release.cjs'), path.join(directory, 'tool/update_release.cjs'));
        fs.mkdirSync(path.join(directory, 'release/metadata'), { recursive: true });
        fs.writeFileSync(path.join(directory, 'release/metadata/RELEASE_NOTES.md'), '- 测试');
        for (const file of ['thmr-app-windows-x64.zip', 'thmr-app-macos-universal.zip',
          'thmr-app-linux-x64.tar.gz', 'thmr-app-android.apk']) {
          fs.writeFileSync(path.join(directory, 'release', file), file);
        }
        const result = spawnSync(process.env.THMR_TEST_BASH || 'bash', ['-e', '-c', script], {
          cwd: directory, encoding: 'utf8', timeout: 15000,
          env: { ...process.env, GITHUB_REF_TYPE: refType, GITHUB_REPOSITORY: 'example/thmr-app',
            RELEASE_TAG: refType === 'tag' ? 'v0.1.9' : 'build-0.1.9-101',
            RELEASE_VERSION: '0.1.9', RELEASE_BUILD: '101',
            THMR_UPDATE_PRIVATE_KEY: privatePem, THMR_UPDATE_PUBLIC_KEY: publicValue },
        });
        assert.ifError(result.error);
        assert.equal(result.status === 0, succeeds, result.stdout + result.stderr);
        if (!succeeds) assert.match(result.stderr, /Configure THMR_UPDATE_PRIVATE_KEY|Signing key does not match/);
        const file = path.join(directory, 'release/metadata/thmr-update.json');
        assert.equal(fs.existsSync(file), signed);
        if (signed) assert.equal(inspectManifest(JSON.parse(fs.readFileSync(file)), publicKey).build_number, 101);
      } finally {
        fs.rmSync(directory, { recursive: true, force: true });
      }
    });
  }
});

test('signed payload carries the version and build; macOS updates keep ZIP compatibility', async t => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'thmr-manifest-'));
  t.after(() => fs.rmSync(directory, { recursive: true, force: true }));
  for (const name of ['thmr-app-windows-x64.zip', 'thmr-app-macos-universal.zip',
    'thmr-app-linux-x64.tar.gz', 'thmr-app-android.apk']) fs.writeFileSync(path.join(directory, name), name);
  // The human installer must never replace the updater ZIP in the signed manifest.
  fs.writeFileSync(path.join(directory, 'thmr-app-macos-universal.dmg'), 'installer');
  const { privateKey } = crypto.generateKeyPairSync('ed25519');
  const notesFile = path.join(directory, 'notes.txt');
  fs.writeFileSync(notesFile, '- 优化更新通知\n- 修复安装失败');
  const publicKey = publicBytes(privateKey);
  const envelope = await createManifest({ version: '0.3.0', 'build-number': '5201',
    artifacts: directory, 'base-url': 'https://example.com/releases/', 'notes-file': notesFile }, {
    THMR_UPDATE_PRIVATE_KEY: privateKey.export({ type: 'pkcs8', format: 'pem' }),
    THMR_UPDATE_PUBLIC_KEY: publicKey,
  });
  const data = inspectManifest(envelope, publicKey);
  assert.equal(data.version, '0.3.0');
  assert.equal(data.build_number, 5201);
  assert.equal(data.notes, '- 优化更新通知\n- 修复安装失败');
  for (const platform of ['darwin-x86_64', 'darwin-aarch64']) {
    const artifact = data.platforms[platform];
    assert.equal(artifact.format, 'zip');
    assert.ok(artifact.url.endsWith('/thmr-app-macos-universal.zip'));
    const bytes = fs.readFileSync(path.join(directory, 'thmr-app-macos-universal.zip'));
    assert.equal(artifact.size, bytes.length);
    assert.equal(artifact.sha256, crypto.createHash('sha256').update(bytes).digest('hex'));
  }
  const tampered = { ...envelope, payload: Buffer.from(JSON.stringify({ ...data, version: '9.0.0' })).toString('base64') };
  assert.throws(() => inspectManifest(tampered, publicKey), /signature/);
  assert.throws(() => inspectManifest(envelope, ''), /public key/);
  const file = path.join(directory, 'thmr-release.json');
  fs.writeFileSync(file, JSON.stringify(envelope));
  const args = [path.join(__dirname, 'update_release.cjs'), 'inspect', '--file', file,
    '--public-key', publicKey, '--version', '0.3.0', '--build-number', '5201'];
  assert.equal(JSON.parse(execFileSync(process.execPath, args)).build_number, 5201);
  assert.throws(() => execFileSync(process.execPath, [...args.slice(0, -1), '5202'],
    { stdio: 'pipe' }), /Signed version does not match/);
});

test('release notes come from the matching packaged changelog section', () => {
  const changelog = '# 更新记录\n\n## 0.1.4\n\n- 修复 Windows 更新\n\n## 0.1.3\n\n- 新增 DMG\n';
  assert.equal(releaseNotes('0.1.4', changelog), '- 修复 Windows 更新');
  assert.equal(releaseNotes('0.1.3', changelog), '- 新增 DMG');
  assert.throws(() => releaseNotes('0.2.0', changelog), /Add release notes/);
  assert.throws(() => releaseNotes('0.2.0', '## 0.2.0\n'), /empty/);
});

test('release notes CLI exports the same Chinese text used by the signed manifest', () => {
  const script = path.join(__dirname, 'update_release.cjs');
  const notes = execFileSync(process.execPath, [script, 'notes', '--version', '0.1.4'], { encoding: 'utf8' }).trim();
  assert.equal(notes, releaseNotes('0.1.4'));
  assert.match(notes, /修复 Windows/);
  assert.equal(execFileSync(process.execPath, [script, 'notes', '--version', '0.1.4-rc.1'],
    { encoding: 'utf8' }).trim(), notes);
});
