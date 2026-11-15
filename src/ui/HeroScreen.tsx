import { useState } from 'react';
import { ITEMS, ITEM_BY_ID, LOOKS } from '../game/content';
import { levelInfo, rankFor } from '../game/rewards';
import { useStore } from '../game/store';
import { SLOTS, type Slot } from '../game/types';
import { Sheet } from './Sheet';
import { feedback } from './feedback';
import { Icon } from './stage';

const HAIR_NAMES: Record<string, string> = { crop: 'Crop', tuft: 'Tuft', long: 'Long', knot: 'Knot', none: 'Bare' };
const SLOT_NAMES: Record<Slot, string> = { head: 'Head', body: 'Body', hand: 'Hand', shield: 'Shield', charm: 'Charm' };

/** The avatar screen: what the hero wears and how they look. */
export function HeroScreen() {
  const save = useStore((s) => s.save);
  const setHero = useStore((s) => s.setHero);
  const equip = useStore((s) => s.equip);
  const [picking, setPicking] = useState<Slot | null>(null);
  const [naming, setNaming] = useState(false);
  const [draft, setDraft] = useState(save.hero.name);
  const { level } = levelInfo(save.xp);

  const saveName = () => {
    setHero({ name: draft.trim().slice(0, 16) || save.hero.name });
    setNaming(false);
  };

  return (
    <>
      <div className="sheet-head">
        <div className="screen-title">
          {naming ? (
            <label className="field plate" style={{ flex: 1 }}>
              <input
                autoFocus
                value={draft}
                maxLength={16}
                aria-label="Hero name"
                onChange={(e) => setDraft(e.target.value)}
                onBlur={saveName}
                onKeyDown={(e) => e.key === 'Enter' && saveName()}
                enterKeyHint="done"
                autoCapitalize="words"
                autoComplete="off"
              />
            </label>
          ) : (
            <>
              <button
                className="rename"
                aria-label={`${save.hero.name}. Rename your hero`}
                onClick={() => {
                  feedback.tap();
                  setDraft(save.hero.name);
                  setNaming(true);
                }}
              >
                <h2 className="display">{save.hero.name}</h2>
                <span className="label faint">Rename</span>
              </button>
              <span className="label dim" style={{ flex: 'none' }}>
                {rankFor(level)} · Lv {level}
              </span>
            </>
          )}
        </div>
      </div>

      <div className="sheet-body">
        <div className="section" style={{ paddingTop: 2 }}>
          <span className="label">Worn</span>
          <div className="grid">
            {SLOTS.map((slot) => {
              const id = save.equipped[slot];
              return (
                <button
                  key={slot}
                  className="slot-cell"
                  aria-label={`${SLOT_NAMES[slot]}: ${id ? ITEM_BY_ID[id].name : 'empty'}. Change`}
                  onClick={() => {
                    feedback.tap();
                    setPicking(slot);
                  }}
                >
                  <span className={`slot plate ${id ? 'worn' : ''}`}>
                    {id ? <Icon kind="item" id={id} size={50} /> : <Icon kind="prop" id={`slot_${slot}`} size={38} res={20} />}
                  </span>
                  <span className="label faint">{slot}</span>
                </button>
              );
            })}
          </div>
        </div>

        <div className="section">
          <span className="label">Skin</span>
          <div className="swatches">
            {LOOKS.skin.filter(c => c !== '#39ff14').map((color, i) => (
              <button
                key={color}
                className="swatch plate"
                style={{ ['--fill' as string]: color }}
                aria-pressed={save.hero.skin === i}
                aria-label={`Skin tone ${i + 1}`}
                onClick={() => {
                  feedback.select();
                  setHero({ skin: i });
                }}
              />
            ))}
          </div>
        </div>

        <div className="section">
          <span className="label">Hair</span>
          <div className="chips" style={{ paddingBottom: 10 }}>
            {LOOKS.hairStyles.map((style, i) => (
              <button
                key={style}
                className="chip plate"
                aria-pressed={save.hero.hairStyle === i}
                onClick={() => {
                  feedback.select();
                  setHero({ hairStyle: i });
                }}
              >
                {HAIR_NAMES[style] ?? style}
              </button>
            ))}
          </div>
          <div className="swatches">
            {LOOKS.hair.filter(c => c !== '#39ff14').map((color, i) => (
              <button
                key={color}
                className="swatch plate"
                style={{ ['--fill' as string]: color }}
                aria-pressed={save.hero.hair === i}
                aria-label={`Hair colour ${i + 1}`}
                onClick={() => {
                  feedback.select();
                  setHero({ hair: i });
                }}
              />
            ))}
          </div>
        </div>

        <div className="section">
          <span className="label">Scarf</span>
          <div className="swatches">
            {LOOKS.scarf.filter(c => c !== '#39ff14').map((color, i) => (
              <button
                key={color}
                className="swatch plate"
                style={{ ['--fill' as string]: color }}
                aria-pressed={save.hero.scarf === i}
                aria-label={`Scarf colour ${i + 1}`}
                onClick={() => {
                  feedback.select();
                  setHero({ scarf: i });
                }}
              />
            ))}
          </div>
        </div>
      </div>

      {picking && (
        <Sheet title={SLOT_NAMES[picking]} size="fit" onClose={() => setPicking(null)}>
          <SlotPicker
            slot={picking}
            onPick={(id) => {
              feedback.select();
              equip(picking, id);
            }}
          />
        </Sheet>
      )}
    </>
  );
}

function SlotPicker({ slot, onPick }: { slot: Slot; onPick: (id: string | null) => void }) {
  const save = useStore((s) => s.save);
  const owned = ITEMS.filter((item) => item.slot === slot && save.inventory.includes(item.id));
  const worn = save.equipped[slot];

  if (owned.length === 0) {
    return <p className="italic dim">Nothing for this slot yet. Weekly and monthly quests always dig something up.</p>;
  }

  return (
    <>
      <div className="grid">
        <button className="slot-cell" aria-label="Wear nothing" aria-pressed={!worn} onClick={() => onPick(null)}>
          <span className={`slot plate ${!worn ? 'selected' : ''}`}>
            <span className="label faint">None</span>
          </span>
        </button>
        {owned.map((item) => (
          <button key={item.id} className="slot-cell" onClick={() => onPick(item.id)} aria-label={item.name} aria-pressed={worn === item.id}>
            <span className={`slot plate ${worn === item.id ? 'worn' : ''}`}>
              <Icon kind="item" id={item.id} size={50} />
              <span className={`slot-pip rarity-${item.rarity}`} />
            </span>
          </button>
        ))}
      </div>
      <p style={{ paddingTop: 14, minHeight: 44 }}>
        {worn ? (
          <>
            {ITEM_BY_ID[worn].name} <span className={`label rarity-${ITEM_BY_ID[worn].rarity}`}>· {ITEM_BY_ID[worn].rarity}</span>
          </>
        ) : (
          <span className="dim italic">Nothing worn here.</span>
        )}
      </p>
    </>
  );
}
