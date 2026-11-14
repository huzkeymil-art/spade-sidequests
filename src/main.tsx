import { StrictMode } from 'react';
import { createRoot } from 'react-dom/client';
import '@fontsource/jacquard-24/latin-400.css';
import '@fontsource/jersey-15/latin-400.css';
import '@fontsource/im-fell-english/latin-400.css';
import '@fontsource/im-fell-english/latin-400-italic.css';
import './ui/theme.css';
import { App } from './ui/App';

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <App />
  </StrictMode>,
);

// In the built app, keep a copy of everything on the device so it opens with no signal.
if (import.meta.env.PROD && 'serviceWorker' in navigator) {
  window.addEventListener('load', () => {
    navigator.serviceWorker.register('./sw.js').catch(() => {
      // Offline support is a bonus; the app works without it.
    });
  });
}
