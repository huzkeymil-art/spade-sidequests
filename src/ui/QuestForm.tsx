import { useState } from 'react';
import { createPortal } from 'react-dom';
import { sfx } from '../audio/sfx';
import { questXp } from '../game/rewards';
import { useStore } from '../game/store';
import { CADENCES, CATEGORIES, type Cadence, type Category, type Difficulty } from '../game/types';
import { Icon } from './stage';

const EFFORT: [Difficulty, string][] = [
  [1, 'Light'],
  [2, 'Steady'],
  [3, 'Hard'],
];
const EVERY: Record<Cadence, string> = { daily: 'day', weekly: 'week', monthly: 'month' };

/** The form for writing your own quest. */
export function QuestForm({ cadence: startCadence, onClose }: { cadence: Cadence; onClose: () => void }) {
  const addCustom = useStore((s) => s.addCustom);
  const [title, setTitle] = useState('');
  const [cadence, setCadence] = useState<Cadence>(startCadence);
  const [category, setCategory] = useState<Category>('mind');
  const [difficulty, setDifficulty] = useState<Difficulty>(2);
  const [pinned, setPinned] = useState(false);
  const ready = title.trim().length > 0;

  const submit = () => {
    if (!ready) return;
    addCustom({ title, cadence, category, difficulty, pinned });
    sfx.done();
    onClose();
  };

  // Drawn over the whole app (not just the panel), so the text box sits near
  // the top of the screen, clear of the phone's keyboard.
  return createPortal(
    <div className="modal" role="dialog" aria-label="Write a quest">
      <div className="modal-head">
        <h2 className="display">Your quest</h2>
        <button className="textlink" onClick={onClose}>
          Close
        </button>
      </div>
      <div className="modal-body">
        <div className="section">
          <span className="label">What will you do?</span>
          <label className="field plate">
            <input
              value={title}
              maxLength={80}
              placeholder="Practise guitar for 20 minutes"
              onChange={(e) => setTitle(e.target.value)}
              onKeyDown={(e) => e.key === 'Enter' && submit()}
              enterKeyHint="done"
            />
          </label>
        </div>

        <div className="section">
          <span className="label">How often?</span>
          <div className="chips">
            {CADENCES.map((c) => (
              <button key={c} className="chip plate" aria-pressed={c === cadence} onClick={() => setCadence(c)}>
                {c}
              </button>
            ))}
          </div>
        </div>

        <div className="section">
          <span className="label">What kind?</span>
          <div className="chips">
            {CATEGORIES.map((c) => (
              <button key={c} className="chip plate" aria-pressed={c === category} onClick={() => setCategory(c)}>
                <Icon kind="prop" id={c} size={18} res={18} />
                {c}
              </button>
            ))}
          </div>
        </div>

        <div className="section">
          <span className="label">How much effort?</span>
          <div className="chips">
            {EFFORT.map(([d, name]) => (
              <button key={d} className="chip plate" aria-pressed={d === difficulty} onClick={() => setDifficulty(d)}>
                {name} · {questXp(cadence, d)} XP
              </button>
            ))}
          </div>
        </div>

        <div className="section">
          <div className="row" style={{ borderTop: '1px solid var(--moss)' }}>
            <div>
              <div>Show it every {EVERY[cadence]}</div>
              <div className="label faint" style={{ marginTop: 5 }}>
                {pinned ? 'Always on the board' : 'Shuffled into the deck'}
              </div>
            </div>
            <button className="toggle plate" role="switch" aria-checked={pinned} aria-label="Show every time" onClick={() => setPinned(!pinned)} />
          </div>
        </div>

        <div className="section">
          <button className="btn plate primary block" disabled={!ready} onClick={submit}>
            Add quest
          </button>
        </div>
      </div>
    </div>,
    document.querySelector('.app') ?? document.body,
  );
}
