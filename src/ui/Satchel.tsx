import { useState } from 'react';
import { sfx } from '../audio/sfx';
import { ITEMS } from '../game/content';
import { useStore } from '../game/store';
import { SLOTS, type ItemDef, type Slot } from '../game/types';
import { Icon } from './stage';

/** Where an item comes from, in words, for items not found yet. */
function whereFrom(item: ItemDef): string {
  if (item.source === 'milestone') return `Waiting at level ${item.level}.`;
  if (item.source === 'feat') return 'A reward for a feat.';
  if (item.rarity === 'common') return 'Turns up on daily and weekly quests.';
  if (item.rarity === 'uncommon') return 'Dug up on weekly quests, now and then on dailies.';
  if (item.rarity === 'rare') return 'Buried deep. Monthly quests find these most often.';
  return 'Almost never surfaces. Monthly quests are your best chance.';
}

/** Everything that can be found, with what you have so far. */
export function Satchel() {
  const save = useStore((s) => s.save);
  const equip = useStore((s) => s.equip);
  const [filter, setFilter] = useState<Slot | 'all'>('all');
  const [openId, setOpenId] = useState<string | null>(null);

  const shown = ITEMS.filter((item) => filter === 'all' || item.slot === filter);
  const open = openId ? ITEMS.find((i) => i.id === openId) : undefined;
  const owns = (id: string) => save.inventory.includes(id);

  return (
    <>
      <div className="sheet-head">
        <div className="screen-title">
          <h2 className="display">Satchel</h2>
          <span className="label dim">
            {save.inventory.length} / {ITEMS.length} found
          </span>
        </div>
        <div className="chips strip" style={{ paddingBottom: 12 }}>
          {(['all', ...SLOTS] as const).map((f) => (
            <button key={f} className="chip plate" aria-pressed={filter === f} onClick={() => setFilter(f)}>
              {f}
            </button>
          ))}
        </div>
      </div>

      <div className="sheet-body">
        <div className="grid four">
          {shown.map((item) => {
            const have = owns(item.id);
            const worn = save.equipped[item.slot] === item.id;
            return (
              <button
                key={item.id}
                className="slot-cell"
                aria-label={have ? item.name : 'Not found yet'}
                onClick={() => {
                  sfx.tap();
                  setOpenId(item.id);
                }}
              >
                <span className={`slot plate ${have ? '' : 'unknown'} ${worn ? 'worn' : ''}`}>
                  {have ? <Icon kind="item" id={item.id} size={62} /> : '?'}
                  <span className={`slot-pip rarity-${item.rarity}`} style={have ? undefined : { opacity: 0.45 }} />
                </span>
              </button>
            );
          })}
        </div>
      </div>

      {open && (
        <>
          <div className="drawer-shade" onClick={() => setOpenId(null)} />
          <div className="drawer" role="dialog" aria-label="Item">
            <div style={{ display: 'flex', gap: 16, alignItems: 'center' }}>
              <span className={`slot plate ${owns(open.id) ? '' : 'unknown'}`} style={{ width: 96, flex: 'none' }}>
                {owns(open.id) ? <Icon kind="item" id={open.id} size={80} /> : '?'}
              </span>
              <div style={{ minWidth: 0 }}>
                <span className={`label rarity-${open.rarity}`}>
                  {open.rarity} · {open.slot}
                </span>
                <h3 className="display" style={{ fontSize: 36, padding: '5px 0 6px' }}>
                  {owns(open.id) ? open.name : 'Not yet found'}
                </h3>
                <p className="italic dim" style={{ fontSize: 16 }}>
                  {owns(open.id) ? open.lore : whereFrom(open)}
                </p>
              </div>
            </div>
            <div style={{ display: 'flex', gap: 10, paddingTop: 16 }}>
              {owns(open.id) &&
                (save.equipped[open.slot] === open.id ? (
                  <button
                    className="btn plate"
                    style={{ flex: 1 }}
                    onClick={() => {
                      sfx.tap();
                      equip(open.slot, null);
                    }}
                  >
                    Take off
                  </button>
                ) : (
                  <button
                    className="btn plate primary"
                    style={{ flex: 1 }}
                    onClick={() => {
                      sfx.done();
                      equip(open.slot, open.id);
                    }}
                  >
                    Wear it
                  </button>
                ))}
              <button className="btn plate" style={{ flex: owns(open.id) ? 'none' : 1 }} onClick={() => setOpenId(null)}>
                Close
              </button>
            </div>
          </div>
        </>
      )}
    </>
  );
}
