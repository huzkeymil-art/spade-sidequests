import { useState } from 'react';
import { useStore } from '../game/store';
import { CATEGORIES } from '../game/types';
import { Confirm, Sheet, ToggleRow } from './Sheet';
import { feedback } from './feedback';
import { pickTextFile, shareSave } from './platform';
import { Icon } from './stage';

/** Settings: display, sound, which kinds of quest to deal, your own quests, and the save. */
export function Settings({ onClose, onGuide }: { onClose: () => void; onGuide: () => void }) {
  const save = useStore((s) => s.save);
  const setSettings = useStore((s) => s.setSettings);
  const toggleCategory = useStore((s) => s.toggleCategory);
  const removeCustom = useStore((s) => s.removeCustom);
  const exportSave = useStore((s) => s.exportSave);
  const importSave = useStore((s) => s.importSave);
  const reset = useStore((s) => s.reset);

  const [pasting, setPasting] = useState(false);
  const [text, setText] = useState('');
  const [note, setNote] = useState('');
  const [confirming, setConfirming] = useState(false);

  const backUp = async () => {
    feedback.tap();
    const data = exportSave();
    const result = await shareSave(data);
    if (result === 'shared') setNote('Save shared.');
    else if (result === 'copied') setNote('Save copied. Paste it somewhere safe.');
    else if (result === 'failed') {
      // Last resort: show the text so it can be copied by hand.
      setText(data);
      setPasting(true);
      setNote('Select the text below and copy it.');
    }
  };

  const load = (data: string) => {
    if (importSave(data.trim())) {
      setNote('Save loaded.');
      setPasting(false);
      setText('');
      feedback.done();
    } else {
      setNote("That doesn't look like a Spade save.");
    }
  };

  const restoreFromFile = async () => {
    feedback.tap();
    const data = await pickTextFile();
    if (data !== null) load(data);
  };

  return (
    <Sheet title="Settings" onClose={onClose}>
      <div className="section">
        <span className="label">Display and feel</span>
        <div className="group plate">
          <ToggleRow label="Retro pixels" note="Chunky, dithered 3D" checked={save.settings.retro} onChange={(retro) => setSettings({ retro })} />
          <ToggleRow label="Sound" checked={save.settings.sound} onChange={(sound) => setSettings({ sound })} />
          <ToggleRow label="Haptics" note="Small taps you can feel" checked={save.settings.haptics} onChange={(haptics) => setSettings({ haptics })} />
        </div>
      </div>

      <div className="section">
        <span className="label">Hero</span>
        <div className="group plate">
          <ToggleRow
            label="New hero"
            note={save.settings.newHero ? 'Detailed, in a hooded cloak' : 'Off: the original digger'}
            checked={save.settings.newHero}
            onChange={(newHero) => setSettings({ newHero })}
          />
          {save.settings.newHero && (
            <ToggleRow
              label="Cel shading"
              note={save.settings.celShading ? 'Flat bands of light, inked edges' : 'Off: soft, smooth light'}
              checked={save.settings.celShading}
              onChange={(celShading) => setSettings({ celShading })}
            />
          )}
        </div>
      </div>

      <div className="section">
        <span className="label">Kinds of quest to deal</span>
        <div className="chips">
          {CATEGORIES.map((c) => (
            <button
              key={c}
              className="chip plate"
              aria-pressed={save.settings.categories[c]}
              onClick={() => {
                feedback.select();
                toggleCategory(c);
              }}
            >
              <Icon kind="prop" id={c} size={18} res={18} />
              {c}
            </button>
          ))}
        </div>
        <p className="group-note" style={{ paddingLeft: 0 }}>
          Changes apply from the next deal. At least one kind stays on.
        </p>
      </div>

      <div className="section">
        <span className="label">Your own quests</span>
        {save.custom.length === 0 ? (
          <p className="italic dim">None yet. Add one from the bottom of the quest board.</p>
        ) : (
          <ul className="group plate">
            {save.custom.map((q) => (
              <li key={q.id} className="row" style={{ paddingRight: 0 }}>
                <span className="row-text">
                  <span>{q.title}</span>
                  <span className="row-note">
                    {q.cadence} · {q.pinned ? 'always shown' : 'in the deck'}
                  </span>
                </span>
                <button
                  className="label"
                  style={{ color: 'var(--rust)', minWidth: 44, minHeight: 44, padding: '0 14px', flex: 'none' }}
                  aria-label={`Remove "${q.title}"`}
                  onClick={() => {
                    feedback.tap();
                    removeCustom(q.id);
                  }}
                >
                  Remove
                </button>
              </li>
            ))}
          </ul>
        )}
      </div>

      <div className="section">
        <span className="label">Your save</span>
        <div className="group plate">
          <button className="row" onClick={backUp}>
            <span className="row-text">
              <span>Back up save</span>
              <span className="row-note">Share or copy it</span>
            </span>
            <span className="chevron" />
          </button>
          <button className="row" onClick={restoreFromFile}>
            <span>Restore from a file</span>
            <span className="chevron" />
          </button>
          <button
            className="row"
            aria-expanded={pasting}
            onClick={() => {
              feedback.tap();
              setPasting(!pasting);
            }}
          >
            <span>Paste a save</span>
            <span className="chevron" style={pasting ? { transform: 'rotate(135deg)' } : undefined} />
          </button>
        </div>
        {pasting && (
          <div style={{ paddingTop: 10 }}>
            <label className="field plate">
              <textarea
                value={text}
                placeholder="Paste a save here"
                onChange={(e) => setText(e.target.value)}
                spellCheck={false}
                autoCapitalize="off"
                autoCorrect="off"
                aria-label="Save data"
              />
            </label>
            <button className="btn plate block" style={{ marginTop: 10 }} disabled={text.trim().length === 0} onClick={() => load(text)}>
              Load this save
            </button>
          </div>
        )}
        <p className="group-note" style={{ paddingLeft: 0 }} role="status">
          {note || 'Progress lives only on this device. Back it up to keep it safe or move it to another phone.'}
        </p>
      </div>

      <div className="section">
        <span className="label">Help</span>
        <div className="group plate">
          <button
            className="row"
            onClick={() => {
              feedback.tap();
              onGuide();
            }}
          >
            <span>How Spade works</span>
            <span className="chevron" />
          </button>
        </div>
      </div>

      <div className="section">
        <span className="label">Start over</span>
        <div className="group plate">
          <button
            className="row danger"
            onClick={() => {
              feedback.tap();
              setConfirming(true);
            }}
          >
            <span>Erase all progress</span>
          </button>
        </div>
      </div>

      <div className="section">
        <span className="label">About</span>
        <p className="dim" style={{ fontSize: 'var(--t-foot)' }}>
          Spade 0.2. All models, textures and sounds are generated by the app's own code. Typefaces: Jacquard 24 and Jersey 15 by Sarah
          Cadigan-Fried, IM Fell English by Igino Marini, under the SIL Open Font License.
        </p>
      </div>

      {confirming && (
        <Confirm
          title="Erase all progress?"
          message="Your level, items, feats and quests will be gone for good. This can't be undone."
          action="Erase"
          destructive
          onCancel={() => setConfirming(false)}
          onConfirm={() => {
            setConfirming(false);
            reset();
            onClose();
          }}
        />
      )}
    </Sheet>
  );
}
