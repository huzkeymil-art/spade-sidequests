import { createContext, useContext } from 'react';
import type { Stage } from '../three/Stage';
import type { Gear, HeroLook } from '../three/hero';
import type { HairStyle } from '../three/models/hero';
import { LOOKS } from '../game/content';
import type { HeroSave, Rarity, Save } from '../game/types';

// The bridge between the screens and the 3D stage.

export const StageContext = createContext<Stage | null>(null);

export function useStage(): Stage {
  const stage = useContext(StageContext);
  if (!stage) throw new Error('The stage is not ready yet');
  return stage;
}

/** Turns the saved palette indexes into real colours for the 3D hero. */
export function lookOf(hero: HeroSave): HeroLook {
  return {
    skin: LOOKS.skin[hero.skin] ?? LOOKS.skin[0],
    hair: LOOKS.hair[hero.hair] ?? LOOKS.hair[0],
    hairStyle: (LOOKS.hairStyles[hero.hairStyle] ?? 'crop') as HairStyle,
    scarf: LOOKS.scarf[hero.scarf] ?? LOOKS.scarf[0],
  };
}

export function gearOf(save: Save): Gear {
  return { ...save.equipped };
}

/** The colour of light each rarity gives off when dug up. */
export const RARITY_LIGHT: Record<Rarity, string> = {
  common: '#e6dfc8',
  uncommon: '#5fe0b0',
  rare: '#7ab8ff',
  mythic: '#ffc24a',
};

interface IconProps {
  /** `item`: an inventory item. `prop`: one of the small icon models. */
  kind: 'item' | 'prop';
  id: string;
  /** Size on screen, in CSS pixels. */
  size: number;
  /** How many chunky pixels across the picture is. Fewer = chunkier. */
  res?: number;
  className?: string;
}

/** An icon photographed from a 3D model. */
export function Icon({ kind, id, size, res, className }: IconProps) {
  const stage = useStage();
  const src = kind === 'item' ? stage.icons.item(id, res ?? 30) : stage.icons.prop(id, res ?? 22);
  return <img className={`icon ${className ?? ''}`} src={src} width={size} height={size} alt="" draggable={false} />;
}

/** The hero's face, as they look right now. */
export function Portrait({ hero, gear, size }: { hero: HeroSave; gear: Gear; size: number }) {
  const stage = useStage();
  const src = stage.icons.portrait(lookOf(hero), gear, 24);
  return <img className="icon" src={src} width={size} height={size} alt="" draggable={false} />;
}
