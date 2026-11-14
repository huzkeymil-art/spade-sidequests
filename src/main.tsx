import { StrictMode } from 'react';
import { createRoot } from 'react-dom/client';
import '@fontsource/jacquard-24/latin-400.css';
import '@fontsource/jersey-15/latin-400.css';
import '@fontsource/im-fell-english/latin-400.css';
import '@fontsource/im-fell-english/latin-400-italic.css';
import './ui/theme.css';
import { App } from './ui/App';

/**
 * Waits for Spade's three typefaces before the first draw, so the app never
 * flashes up in a stand-in font and then jumps. If they are slow (a bad
 * connection on the very first visit), it gives up after a moment and starts anyway.
 */
function fontsReady(): Promise<unknown> {
  const wanted = ['1em "Jacquard 24"', '1em "Jersey 15"', '1em "IM Fell English"', 'italic 1em "IM Fell English"'];
  const loading = Promise.all(wanted.map((font) => document.fonts.load(font))).catch(() => undefined);
  const giveUp = new Promise((resolve) => setTimeout(resolve, 1500));
  return Promise.race([loading, giveUp]);
}

void fontsReady().then(() => {
  createRoot(document.getElementById('root')!).render(
    <StrictMode>
      <App />
    </StrictMode>,
  );
});

// In the built app, keep a copy of everything on the device so it opens with no signal.
if (import.meta.env.PROD && 'serviceWorker' in navigator) {
  window.addEventListener('load', () => {
    navigator.serviceWorker.register('./sw.js').catch(() => {
      // Offline support is a bonus; the app works without it.
    });
  });
}
