import { sfx } from '../audio/sfx';
import { haptic } from './platform';

// What the player hears and feels when they do something. Each call pairs a
// sound with a tap from the phone, the way built-in iPhone apps do.

export const feedback = {
  /** An ordinary button press. */
  tap() {
    haptic();
    sfx.tap();
  },
  /** Picking one option from several: felt, but silent. */
  select() {
    haptic();
  },
  /** A counted quest moved one step. */
  step() {
    haptic();
    sfx.step();
  },
  /** A quest was sealed. */
  done() {
    haptic();
    sfx.done();
  },
  /** Every daily quest finished. */
  clear() {
    haptic();
    sfx.clear();
  },
  dig() {
    haptic();
    sfx.dig();
  },
  reveal() {
    haptic();
    sfx.reveal();
  },
  level() {
    haptic();
    sfx.level();
  },
  feat() {
    sfx.feat();
  },
};
