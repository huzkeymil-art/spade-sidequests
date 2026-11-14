// Small bridges to things the phone provides: the keyboard, the share sheet,
// haptic taps, and long-term storage. Each one checks that the feature exists
// first, so the app still works in browsers that lack it.

let hapticsEnabled = true;

export function setHapticsEnabled(on: boolean) {
  hapticsEnabled = on;
}

/**
 * A light tap felt through the phone.
 *
 * Web pages have no official way to trigger this on an iPhone. But iOS makes
 * its own on/off switches tick when they are flipped, so this quietly flips a
 * hidden switch. On Android, the standard vibrate call does the same job.
 * Anywhere else it does nothing.
 */
export function haptic() {
  if (!hapticsEnabled) return;
  try {
    if (typeof navigator.vibrate === 'function') {
      navigator.vibrate(8);
      return;
    }
    const label = document.createElement('label');
    label.setAttribute('aria-hidden', 'true');
    label.style.display = 'none';
    const input = document.createElement('input');
    input.type = 'checkbox';
    input.setAttribute('switch', '');
    label.appendChild(input);
    document.head.appendChild(label);
    label.click();
    document.head.removeChild(label);
  } catch {
    // No haptics here; nothing is lost.
  }
}

/**
 * Keeps the CSS variable --kb equal to the height of the on-screen keyboard,
 * so buttons and text boxes can sit just above it. Returns a function that
 * stops watching.
 */
export function watchKeyboard(): () => void {
  const viewport = window.visualViewport;
  if (!viewport) return () => {};
  const root = document.documentElement;
  let last = -1;
  const update = () => {
    // The keyboard is whatever part of the page the visible area no longer reaches.
    const hidden = Math.max(0, Math.round(window.innerHeight - viewport.height - viewport.offsetTop));
    const keyboard = hidden > 60 ? hidden : 0; // ignore small changes like a toolbar sliding away
    if (keyboard !== last) {
      last = keyboard;
      root.style.setProperty('--kb', `${keyboard}px`);
    }
  };
  // When typing ends, iPhones can leave the page nudged upward. Put it back.
  const settle = () => window.setTimeout(() => window.scrollTo(0, 0), 60);
  viewport.addEventListener('resize', update);
  viewport.addEventListener('scroll', update);
  document.addEventListener('focusout', settle);
  update();
  return () => {
    viewport.removeEventListener('resize', update);
    viewport.removeEventListener('scroll', update);
    document.removeEventListener('focusout', settle);
  };
}

export type ShareResult = 'shared' | 'copied' | 'cancelled' | 'failed';

/**
 * Hands the save to the phone's share sheet as a file (to keep in Files,
 * AirDrop, or send to yourself). Falls back to copying it as text.
 */
export async function shareSave(json: string): Promise<ShareResult> {
  const name = `spade-save-${new Date().toISOString().slice(0, 10)}.json`;
  try {
    const file = new File([json], name, { type: 'application/json' });
    if (navigator.canShare?.({ files: [file] })) {
      await navigator.share({ files: [file], title: 'Spade save' });
      return 'shared';
    }
  } catch (error) {
    if ((error as DOMException)?.name === 'AbortError') return 'cancelled';
  }
  try {
    await navigator.clipboard.writeText(json);
    return 'copied';
  } catch {
    return 'failed';
  }
}

/** Opens the phone's file picker and returns the chosen file's text, or null if nothing was picked. */
export function pickTextFile(): Promise<string | null> {
  return new Promise((resolve) => {
    const input = document.createElement('input');
    input.type = 'file';
    input.accept = 'application/json,.json,text/plain';
    input.onchange = () => {
      const file = input.files?.[0];
      if (!file) return resolve(null);
      file.text().then(resolve, () => resolve(null));
    };
    input.addEventListener('cancel', () => resolve(null));
    input.click();
  });
}

/** Asks the browser not to clear Spade's save when the phone runs low on space. */
export function requestPersistence() {
  try {
    void navigator.storage?.persist?.();
  } catch {
    // Not supported; the save still works, it is just less protected.
  }
}

/** True when the player has asked their phone to cut down on animation. */
export function prefersReducedMotion(): boolean {
  return window.matchMedia?.('(prefers-reduced-motion: reduce)').matches ?? false;
}

/** True when Spade is running as a home-screen app rather than in a browser tab. */
export function isInstalled(): boolean {
  const iosStandalone = (navigator as Navigator & { standalone?: boolean }).standalone === true;
  return iosStandalone || window.matchMedia('(display-mode: standalone)').matches;
}

/** Formats a whole number the way the player's region writes it (1,480 or 1.480). */
export function formatNumber(n: number): string {
  return n.toLocaleString();
}
