import { useState } from 'react';
import { questXp } from '../game/rewards';
import { useStore } from '../game/store';
import { CADENCES, CATEGORIES, type Cadence, type Category, type Difficulty } from '../game/types';
import { Sheet, ToggleRow } from './Sheet';
import { feedback } from './feedback';
import { Icon } from './stage';

const EFFORT: [Difficulty, string][] = [
  [1, 'Light'],
  [2, 'Steady'],
  [3, 'Hard'],
];
const EVERY: Record<Cadence, string> = { daily: 'day', weekly: 'week', monthly: 'month' };
const MAX_LENGTH = 80;

/** The sheet for writing your own quest. */
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
    feedback.done();
    onClose();
  };

  return (
    <Sheet
      title="Your quest"
      onClose={onClose}
      footer={
        <button className="btn plate primary block" disabled={!ready} onClick={submit}>
          Add quest
        </button>
      }
    >
      <div className="section">
        <span className="label">What will you do?</span>
        <label className="field plate">
          <input
            value={title}
            maxLength={MAX_LENGTH}
            placeholder="Practise guitar for 20 minutes"
            aria-label="What will you do?"
            onChange={(e) => setTitle(e.target.value)}
            onKeyDown={(e) => e.key === 'Enter' && submit()}
            enterKeyHint="done"
            autoCapitalize="sentences"
            autoComplete="off"
          />
        </label>
        {title.length > MAX_LENGTH - 20 && (
          <div className="field-count">
            <span className="label faint">{MAX_LENGTH - title.length} left</span>
          </div>
        )}
      </div>

      <div className="section">
        <span className="label">How often?</span>
        <div className="chips">
          {CADENCES.map((c) => (
            <button
              key={c}
              className="chip plate"
              aria-pressed={c === cadence}
              onClick={() => {
                feedback.select();
                setCadence(c);
              }}
            >
              {c}
            </button>
          ))}
        </div>
      </div>

      <div className="section">
        <span className="label">What kind?</span>
        <div className="chips">
          {CATEGORIES.map((c) => (
            <button
              key={c}
              className="chip plate"
              aria-pressed={c === category}
              onClick={() => {
                feedback.select();
                setCategory(c);
              }}
            >
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
            <button
              key={d}
              className="chip plate"
              aria-pressed={d === difficulty}
              onClick={() => {
                feedback.select();
                setDifficulty(d);
              }}
            >
              {name} · {questXp(cadence, d)} XP
            </button>
          ))}
        </div>
      </div>

      <div className="section">
        <div className="group plate">
          <ToggleRow
            label={`Show it every ${EVERY[cadence]}`}
            note={pinned ? 'Always on the board' : 'Shuffled into the deck'}
            checked={pinned}
            onChange={setPinned}
          />
        </div>
      </div>
    </Sheet>
  );
}
