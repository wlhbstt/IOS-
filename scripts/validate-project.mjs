import { existsSync, readFileSync, readdirSync, statSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import assert from 'node:assert/strict';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const required = [
  'Package.swift', 'project.yml', 'App/Info.plist', 'App/PhotoCleanerApp.swift',
  '.github/workflows/ios.yml', 'scripts/build-ios.sh',
  'scripts/install-swift-test-toolchain.sh', 'README.md',
  'docs/INSTALL-WINDOWS.md', 'docs/DEVICE-CHECKLIST.md',
];
for (const path of required) {
  assert(existsSync(join(root, path)), `Missing project input: ${path}`);
  assert(statSync(join(root, path)).size > 0, `Empty project input: ${path}`);
}

function swiftFiles(directory) {
  return readdirSync(directory, { withFileTypes: true }).flatMap(entry => {
    const path = join(directory, entry.name);
    return entry.isDirectory() ? swiftFiles(path) : entry.name.endsWith('.swift') ? [path] : [];
  });
}
for (const directory of ['App', 'Sources/PhotoCleanerCore', 'Tests/PhotoCleanerCoreTests']) {
  const files = swiftFiles(join(root, directory));
  assert(files.length > 0, `No Swift inputs in ${directory}`);
  console.log(`${directory}: ${files.length} Swift files`);
}

// Check source-plist declarations only; Apple plutil validates the built plist on macOS.
const plist = readFileSync(join(root, 'App/Info.plist'), 'utf8');
const keys = new Set([...plist.matchAll(/<key>\s*([^<]+?)\s*<\/key>/g)].map(match => match[1]));
for (const key of [
  'CFBundleExecutable', 'CFBundleIdentifier', 'CFBundleName', 'CFBundlePackageType',
  'CFBundleShortVersionString', 'CFBundleVersion', 'NSPhotoLibraryUsageDescription',
  'LSRequiresIPhoneOS', 'UILaunchScreen',
]) {
  assert(keys.has(key), `Missing source Info.plist key: ${key}`);
}
const workflow = readFileSync(join(root, '.github/workflows/ios.yml'), 'utf8');
const buildScript = readFileSync(join(root, 'scripts/build-ios.sh'), 'utf8');
assert(workflow.includes('bash scripts/build-ios.sh'), 'Workflow must invoke the checked-in build script');
assert(workflow.includes('build/PhotoCleaner-unsigned.ipa'), 'Workflow artifact path is missing');
assert(buildScript.includes('/build/PhotoCleaner-unsigned.ipa'), 'Build output must match the artifact path');
console.log('Project inputs and required source-plist declarations checked.');
console.log('Static checks only: no Swift compilation, YAML/XML parsing, signing, or device validation.');
