// Runs scripts/ios-data.ts. Vite does the loading, so the script can import
// the web app's TypeScript and JSON files exactly as the app itself does.
import { createServer } from 'vite';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const server = await createServer({ root, server: { middlewareMode: true }, appType: 'custom', logLevel: 'error', plugins: [] });
try {
  const mod = await server.ssrLoadModule('/scripts/ios-data.ts');
  mod.run(root);
} finally {
  await server.close();
}
