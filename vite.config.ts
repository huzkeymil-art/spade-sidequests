import { defineConfig } from 'vitest/config';
import type { Plugin } from 'vite';
import { existsSync, readdirSync } from 'node:fs';
import react from '@vitejs/plugin-react';

/**
 * Tiny offline support: after the build, write a service worker that knows
 * the exact list of files the app is made of, so it can keep a copy of all
 * of them on the phone.
 */
function offlineWorker(): Plugin {
  return {
    name: 'spade-offline-worker',
    apply: 'build',
    generateBundle(_options, bundle) {
      // Everything Vite built, plus the files copied straight from /public (icons, manifest).
      const built = Object.keys(bundle).filter((f) => !f.endsWith('.map') && f !== 'index.html');
      const copied = existsSync('public') ? readdirSync('public') : [];
      const files = [...new Set([...built, ...copied])];
      const version = Date.now().toString(36);
      const source = `
const CACHE = 'spade-${version}';
const FILES = ${JSON.stringify(['./', ...files.map((f) => './' + f)])};

self.addEventListener('install', (event) => {
  event.waitUntil(
    caches.open(CACHE).then((cache) => cache.addAll(FILES)).then(() => self.skipWaiting()),
  );
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches
      .keys()
      .then((keys) => Promise.all(keys.filter((k) => k !== CACHE).map((k) => caches.delete(k))))
      .then(() => self.clients.claim()),
  );
});

self.addEventListener('fetch', (event) => {
  if (event.request.method !== 'GET') return;
  // ignoreVary: some servers label files "Vary: Origin", which would make the
  // cache refuse to hand back a file it has. The files are the same for
  // everyone, so that label is safely ignored.
  event.respondWith(
    caches
      .match(event.request, { ignoreSearch: true, ignoreVary: true })
      .then((hit) => hit || fetch(event.request)),
  );
});
`;
      this.emitFile({ type: 'asset', fileName: 'sw.js', source });
    },
  };
}

export default defineConfig({
  // Relative paths, so the app works at any URL (GitHub Pages serves it from /spade-sidequests/).
  base: './',
  plugins: [react(), offlineWorker()],
  build: { chunkSizeWarningLimit: 900 },
  test: { environment: 'node', include: ['src/**/*.test.ts'] },
});
