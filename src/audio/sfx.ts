// Sound effects, made from scratch with the Web Audio API.
// There are no sound files: each effect is a few notes played by simple
// oscillators (the electronic equivalent of a tuning fork), shaped so they
// fade out quickly like a plucked string.

let ctx: AudioContext | null = null;
let enabled = true;

export function setSoundEnabled(on: boolean) {
  enabled = on;
}

/** Browsers only allow sound after the player has touched the screen, so the engine starts lazily. */
function audio(): AudioContext | null {
  if (!enabled) return null;
  try {
    if (!ctx) {
      const Ctor = window.AudioContext ?? (window as unknown as { webkitAudioContext?: typeof AudioContext }).webkitAudioContext;
      if (!Ctor) return null;
      ctx = new Ctor();
    }
    if (ctx.state === 'suspended') void ctx.resume();
    return ctx;
  } catch {
    return null;
  }
}

/** Call from any touch or click. Phones keep sound switched off until the player has interacted. */
export function unlockAudio() {
  audio();
}

interface Note {
  /** Pitch in hertz. */
  freq: number;
  /** Seconds after the effect starts. */
  at: number;
  /** How long the note rings. */
  length: number;
  volume?: number;
  wave?: OscillatorType;
  /** Slide to this pitch over the note's length. */
  slideTo?: number;
}

function play(notes: Note[]) {
  const ac = audio();
  if (!ac) return;
  const start = ac.currentTime + 0.01;
  for (const note of notes) {
    const osc = ac.createOscillator();
    const gain = ac.createGain();
    osc.type = note.wave ?? 'triangle';
    osc.frequency.setValueAtTime(note.freq, start + note.at);
    if (note.slideTo) osc.frequency.exponentialRampToValueAtTime(note.slideTo, start + note.at + note.length);
    const volume = (note.volume ?? 0.5) * 0.22;
    gain.gain.setValueAtTime(0, start + note.at);
    gain.gain.linearRampToValueAtTime(volume, start + note.at + 0.008);
    gain.gain.exponentialRampToValueAtTime(0.0001, start + note.at + note.length);
    osc.connect(gain).connect(ac.destination);
    osc.start(start + note.at);
    osc.stop(start + note.at + note.length + 0.02);
  }
}

/** A short burst of hiss, for earthy thumps. */
function noise(at: number, length: number, volume: number) {
  const ac = audio();
  if (!ac) return;
  const frames = Math.floor(ac.sampleRate * length);
  const buffer = ac.createBuffer(1, frames, ac.sampleRate);
  const data = buffer.getChannelData(0);
  for (let i = 0; i < frames; i++) data[i] = (Math.random() * 2 - 1) * Math.pow(1 - i / frames, 2);
  const source = ac.createBufferSource();
  source.buffer = buffer;
  const filter = ac.createBiquadFilter();
  filter.type = 'lowpass';
  filter.frequency.value = 900;
  const gain = ac.createGain();
  gain.gain.value = volume * 0.3;
  source.connect(filter).connect(gain).connect(ac.destination);
  source.start(ac.currentTime + 0.01 + at);
}

export const sfx = {
  /** A soft tick for ordinary taps. */
  tap() {
    play([{ freq: 520, at: 0, length: 0.05, volume: 0.25, wave: 'square' }]);
  },
  /** A counted quest moved one step. */
  step() {
    play([{ freq: 392, at: 0, length: 0.12, volume: 0.4 }]);
  },
  /** Quest sealed. */
  done() {
    play([
      { freq: 440, at: 0, length: 0.16 },
      { freq: 660, at: 0.07, length: 0.26 },
    ]);
  },
  /** Every daily finished. */
  clear() {
    play([
      { freq: 440, at: 0, length: 0.16 },
      { freq: 587, at: 0.09, length: 0.16 },
      { freq: 784, at: 0.18, length: 0.4 },
    ]);
  },
  /** The ground breaks. */
  dig() {
    play([{ freq: 130, at: 0, length: 0.3, volume: 0.9, wave: 'sine', slideTo: 46 }]);
    noise(0, 0.28, 0.9);
    noise(0.34, 0.22, 0.5);
  },
  /** The lockbox opens. */
  reveal() {
    play([
      { freq: 392, at: 0, length: 0.2 },
      { freq: 494, at: 0.09, length: 0.2 },
      { freq: 622, at: 0.18, length: 0.22 },
      { freq: 831, at: 0.27, length: 0.7, volume: 0.6 },
      { freq: 415, at: 0.27, length: 0.7, volume: 0.3, wave: 'sine' },
    ]);
  },
  /** Level up. */
  level() {
    play([
      { freq: 294, at: 0, length: 0.18 },
      { freq: 440, at: 0.1, length: 0.18 },
      { freq: 554, at: 0.2, length: 0.18 },
      { freq: 740, at: 0.3, length: 0.24 },
      { freq: 880, at: 0.44, length: 0.9, volume: 0.6 },
      { freq: 440, at: 0.44, length: 0.9, volume: 0.3, wave: 'sine' },
    ]);
  },
  /** A feat was earned. */
  feat() {
    play([
      { freq: 988, at: 0, length: 0.14, volume: 0.35 },
      { freq: 1319, at: 0.08, length: 0.4, volume: 0.35 },
    ]);
  },
};
