// A bare page for looking at the 3D stage on its own while tuning the art.
// Open /dev/stage.html?view=quests&gear=hand:rusty_spade,head:wool_cap&daily=2&streak=3&month=0.6
import { Stage, type View } from '../src/three/Stage';
import type { Gear } from '../src/three/hero';
import type { HairStyle } from '../src/three/models/hero';

const q = new URLSearchParams(location.search);
const stage = new Stage(document.getElementById('stage') as HTMLCanvasElement);

const gear: Gear = {};
for (const pair of (q.get('gear') ?? 'hand:rusty_spade').split(',')) {
  const [slot, id] = pair.split(':');
  if (slot && id) (gear as Record<string, string>)[slot] = id;
}
stage.setHero(
  {
    skin: q.get('skin') ?? '#e0ac84',
    hair: q.get('hair') ?? '#3d2817',
    hairStyle: (q.get('style') ?? 'tuft') as HairStyle,
    scarf: q.get('scarf') ?? '#b5472f',
  },
  gear,
);
const done = Number(q.get('week') ?? 3);
stage.setProgress({
  dailyDone: Number(q.get('daily') ?? 2),
  dailyTotal: 3,
  streak: Number(q.get('streak') ?? 3),
  week: [0, 1, 2, 3, 4, 5, 6].map((i) => i < done),
  today: done,
  month: Number(q.get('month') ?? 0.55),
});
stage.setRetro(q.get('retro') !== '0');
stage.snapView((q.get('view') ?? 'quests') as View);
if (q.has('yaw')) {
  (stage as unknown as { heroYaw: number; heroYawTarget: number }).heroYaw = Number(q.get('yaw'));
  (stage as unknown as { heroYaw: number; heroYawTarget: number }).heroYawTarget = Number(q.get('yaw'));
}
stage.start();
(window as unknown as { stage: Stage }).stage = stage;
