import { useState } from 'react';
import { sfx } from '../audio/sfx';
import { useStore } from '../game/store';
import { CATEGORIES } from '../game/types';
import { Icon } from './stage';

/** Settings: display, sound, which kinds of quest to deal, your own quests, and the save. */
export function Settings({ onClose }: { onClose: () => void }) {
  const save = useStore((s) => s.save);
  const setSettings = useStore((s) => s.setSettings);
  const toggleCategory = useStore((s) => s.toggleCategory);
  const removeCustom = useStore((s) => s.removeCustom);
  const exportSave = useStore((s) => s.exportSave);
  const importSave = useStore((s) => s.importSave);
  const reset = useStore((s) => s.reset);

  const [text, setText] = useState('');
  const [note, setNote] = useState('');
  const [confirming, setConfirming] = useState(false);

  const copy = async () => {
    const data = exportSave();
    setText(data);
    try {
      await navigator.clipboard.writeText(data);
      setNote('Copied. Paste it somewhere safe.');
    } catch {
      setNote('Select the text below and copy it.');
    }
  };

  const load = () => {
    if (importSave(text.trim())) {
      setNote('Save loaded.');
      sfx.done();
    } else {
      setNote("That doesn't look like a Spade save.");
    }
  };

  return (
    <div className="modal" role="dialog" aria-label="Settings">
      <div className="modal-head">
        <h2 className="display">Settings</h2>
        <button className="textlink" onClick={onClose}>
          Close
        </button>
      </div>

      <div className="modal-body">
        <div className="section">
          <span className="label">Display and sound</span>
          <div className="row" style={{ borderTop: '1px solid var(--moss)' }}>
            <div>
              <div>Retro pixels</div>
              <div className="label faint" style={{ marginTop: 5 }}>
                Chunky, dithered 3D
              </div>
            </div>
            <button
              className="toggle plate"
              role="switch"
              aria-checked={save.settings.retro}
              aria-label="Retro pixels"
              onClick={() => setSettings({ retro: !save.settings.retro })}
            />
          </div>
          <div className="row">
            <div>Sound</div>
            <button
              className="toggle plate"
              role="switch"
              aria-checked={save.settings.sound}
              aria-label="Sound"
              onClick={() => setSettings({ sound: !save.settings.sound })}
            />
          </div>
        </div>

        <div className="section">
          <span className="label">Kinds of quest to deal</span>
          <div className="chips">
            {CATEGORIES.map((c) => (
              <button key={c} className="chip plate" aria-pressed={save.settings.categories[c]} onClick={() => toggleCategory(c)}>
                <Icon kind="prop" id={c} size={18} res={18} />
                {c}
              </button>
            ))}
          </div>
          <p className="italic faint" style={{ fontSize: 15, paddingTop: 9 }}>
            Changes apply from the next deal.
          </p>
        </div>

        <div className="section">
          <span className="label">Your own quests</span>
          {save.custom.length === 0 ? (
            <p className="italic dim">None yet. Add one from the bottom of the quest board.</p>
          ) : (
            <ul style={{ borderTop: '1px solid var(--moss)' }}>
              {save.custom.map((q) => (
                <li key={q.id} className="row">
                  <div style={{ minWidth: 0 }}>
                    <div>{q.title}</div>
                    <div className="label faint" style={{ marginTop: 5 }}>
                      {q.cadence} · {q.pinned ? 'always shown' : 'in the deck'}
                    </div>
                  </div>
                  <button className="textlink" style={{ color: 'var(--rust)' }} onClick={() => removeCustom(q.id)}>
                    Remove
                  </button>
                </li>
              ))}
            </ul>
          )}
        </div>

        <div className="section">
          <span className="label">Your save</span>
          <p className="dim" style={{ fontSize: 16, paddingBottom: 11 }}>
            Progress lives only on this device. Copy it out to back it up or move it.
          </p>
          <div style={{ display: 'flex', gap: 10 }}>
            <button className="btn plate" style={{ flex: 1 }} onClick={copy}>
              Copy save
            </button>
            <button className="btn plate" style={{ flex: 1 }} disabled={text.trim().length === 0} onClick={load}>
              Load save
            </button>
          </div>
          <label className="field plate" style={{ marginTop: 10 }}>
            <textarea
              value={text}
              placeholder="Paste a save here, then press Load save"
              onChange={(e) => setText(e.target.value)}
              spellCheck={false}
              aria-label="Save data"
            />
          </label>
          {note && (
            <p className="label dim" style={{ paddingTop: 9 }}>
              {note}
            </p>
          )}
        </div>

        <div className="section">
          <span className="label">Start over</span>
          <button
            className="btn plate danger block"
            onClick={() => {
              if (!confirming) {
                setConfirming(true);
                return;
              }
              reset();
              onClose();
            }}
          >
            {confirming ? 'Tap again to erase everything' : 'Erase all progress'}
          </button>
        </div>

        <div className="section">
          <span className="label">About</span>
          <p className="dim" style={{ fontSize: 15 }}>
            Spade 0.1. All models, textures and sounds are generated by the app's own code. Typefaces: Jacquard 24 and Jersey 15 by
            Sarah Cadigan-Fried, IM Fell English by Igino Marini, under the SIL Open Font License.
          </p>
        </div>
      </div>
    </div>
  );
}
