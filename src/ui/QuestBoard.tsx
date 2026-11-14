import { useEffect, useRef, useState } from 'react';
import { sfx } from '../audio/sfx';
import { formatCountdown, nextReset } from '../game/periods';
import { DAILY_CLEAR_XP } from '../game/rewards';
import { rerollsLeft } from '../game/state';
import { useStore } from '../game/store';
import { CADENCES, type ActiveQuest, type Cadence } from '../game/types';
import { QuestForm } from './QuestForm';
import { Icon, useStage } from './stage';

const HOLD_MS = 650;
const CADENCE_NAME: Record<Cadence, string> = { daily: 'Daily', weekly: 'Weekly', monthly: 'Monthly' };

export function QuestBoard() {
  const save = useStore((s) => s.save);
  const now = useStore((s) => s.now);
  const [cadence, setCadence] = useState<Cadence>('daily');
  const [writing, setWriting] = useState(false);

  const board = save.boards[cadence];
  const swaps = rerollsLeft(save);
  const done = save.boards.daily.quests.filter((q) => q.done).length;
  const total = save.boards.daily.quests.length;

  return (
    <>
      <div className="sheet-head">
        <div className="cadences" role="tablist">
          {CADENCES.map((c) => {
            const open = save.boards[c].quests.filter((q) => !q.done).length;
            return (
              <button
                key={c}
                role="tab"
                aria-selected={c === cadence}
                className="cadence"
                onClick={() => {
                  sfx.tap();
                  setCadence(c);
                }}
              >
                {CADENCE_NAME[c]}
                {open > 0 && <span className="cadence-count">{open}</span>}
              </button>
            );
          })}
        </div>
        <div className="board-note">
          <span className="label faint">New in {formatCountdown(nextReset(cadence, new Date(now)).getTime() - now)}</span>
          {cadence === 'daily' && <span className="label faint">{swaps > 0 ? `${swaps} swap left` : 'No swaps left'}</span>}
        </div>
      </div>

      <div className="sheet-body">
        <ul>
          {board.quests.map((quest) => (
            <QuestRow key={quest.key} quest={quest} canSwap={cadence === 'daily' && swaps > 0 && !quest.pinned} />
          ))}
        </ul>

        {cadence === 'daily' && (
          <div className="bonus">
            <div>
              <div>{save.boards.daily.cleared ? 'Lantern full' : 'Fill the lantern'}</div>
              <div className="label faint" style={{ marginTop: 5 }}>
                All of today's quests: +{DAILY_CLEAR_XP} XP
              </div>
            </div>
            <div className="pips" aria-label={`${done} of ${total} done`}>
              {save.boards.daily.quests.map((q) => (
                <span key={q.key} className={`pip ${q.done ? 'on' : ''}`} />
              ))}
            </div>
          </div>
        )}

        <button
          className="add-quest"
          onClick={() => {
            sfx.tap();
            setWriting(true);
          }}
        >
          <span className="socket plate">+</span>
          <span className="italic">Write a quest of your own</span>
        </button>
      </div>

      {writing && <QuestForm cadence={cadence} onClose={() => setWriting(false)} />}
    </>
  );
}

/**
 * One quest. Pressing and holding fills the square socket; when it is full the
 * quest is marked. A quick tap just shows a reminder to hold, and dragging
 * (to scroll) cancels, so quests are never completed by accident.
 */
function QuestRow({ quest, canSwap }: { quest: ActiveQuest; canSwap: boolean }) {
  const mark = useStore((s) => s.mark);
  const reroll = useStore((s) => s.reroll);
  const stage = useStage();
  const [holding, setHolding] = useState(false);
  const [hint, setHint] = useState(false);
  const [gain, setGain] = useState<number | null>(null);
  const press = useRef<{ x: number; y: number; at: number; timer: number } | null>(null);
  const timers = useRef<number[]>([]);

  useEffect(
    () => () => {
      if (press.current) clearTimeout(press.current.timer);
      timers.current.forEach(clearTimeout);
    },
    [],
  );

  const later = (fn: () => void, ms: number) => {
    timers.current.push(window.setTimeout(fn, ms));
  };

  const finish = () => {
    press.current = null;
    setHolding(false);
    const events = mark(quest.cadence, quest.key);
    const earned = events.reduce((sum, e) => (e.type === 'xp' ? sum + e.amount : sum), 0);
    if (earned > 0) {
      stage.cheer();
      if (events.some((e) => e.type === 'clear')) sfx.clear();
      else sfx.done();
      setGain(earned);
      later(() => setGain(null), 950);
    } else {
      sfx.step();
    }
  };

  const onDown = (e: React.PointerEvent) => {
    if (quest.done || (e.target as HTMLElement).closest('[data-nohold]')) return;
    const timer = window.setTimeout(finish, HOLD_MS);
    press.current = { x: e.clientX, y: e.clientY, at: performance.now(), timer };
    setHolding(true);
    setHint(false);
  };

  const release = (wasTap: boolean) => {
    const p = press.current;
    if (!p) return;
    clearTimeout(p.timer);
    press.current = null;
    setHolding(false);
    if (wasTap && performance.now() - p.at < 300) {
      setHint(true);
      later(() => setHint(false), 1500);
    }
  };

  const onMove = (e: React.PointerEvent) => {
    const p = press.current;
    if (p && Math.hypot(e.clientX - p.x, e.clientY - p.y) > 10) release(false);
  };

  const counted = quest.target > 1;

  return (
    <li
      className={`quest ${holding ? 'holding' : ''}`}
      data-done={quest.done}
      style={{ ['--hold' as string]: `${HOLD_MS}ms` }}
      onPointerDown={onDown}
      onPointerMove={onMove}
      onPointerUp={() => release(true)}
      onPointerCancel={() => release(false)}
      onPointerLeave={() => release(false)}
      onContextMenu={(e) => e.preventDefault()}
    >
      <div className="socket plate">
        <span className="socket-fill" />
        {quest.done ? (
          <Icon kind="prop" id="seal" size={28} res={20} />
        ) : counted ? (
          <span className="socket-count">
            {quest.progress}/{quest.target}
          </span>
        ) : null}
      </div>

      <div className="quest-main">
        <div className="quest-title">{quest.title}</div>
        {hint ? (
          <div className="quest-meta">
            <span className="label" style={{ color: 'var(--lantern)' }}>
              Press and hold to {counted && quest.progress + 1 < quest.target ? 'count it' : 'seal it'}
            </span>
          </div>
        ) : (
          <div className="quest-meta">
            <Icon kind="prop" id={quest.category} size={18} res={18} />
            <span className="label">{quest.category}</span>
            {quest.custom && <span className="label">· yours</span>}
          </div>
        )}
      </div>

      <div className="quest-side">
        <span className="xp">+{quest.xp}</span>
        {canSwap && !quest.done && (
          <button
            className="swap"
            data-nohold
            onClick={() => {
              sfx.tap();
              reroll(quest.key);
            }}
          >
            Swap
          </button>
        )}
      </div>

      {gain !== null && <span className="float-xp">+{gain}</span>}
    </li>
  );
}
