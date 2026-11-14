import { featProgress } from '../game/achievements';
import { FEATS, ITEM_BY_ID } from '../game/content';
import { useStore } from '../game/store';
import { Icon } from './stage';

/** Achievements and lifetime numbers. */
export function Feats() {
  const save = useStore((s) => s.save);
  const earned = FEATS.filter((f) => f.id in save.feats).length;

  // Earned feats first (newest at the top), then the rest by how close they are.
  const rows = FEATS.map((feat) => ({ feat, ...featProgress(save, feat) })).sort((a, b) => {
    if (a.done !== b.done) return a.done ? -1 : 1;
    if (a.done) return save.feats[b.feat.id] - save.feats[a.feat.id];
    return b.value / b.goal - a.value / a.goal;
  });

  return (
    <>
      <div className="sheet-head">
        <div className="screen-title">
          <h2 className="display">Feats</h2>
          <span className="label dim">
            {earned} / {FEATS.length} earned
          </span>
        </div>
        <div className="stats">
          <div className="stat">
            <b>{save.counts.quests}</b>
            <span className="label faint">Quests</span>
          </div>
          <div className="stat">
            <b>{save.counts.bestStreak}</b>
            <span className="label faint">Best run</span>
          </div>
          <div className="stat">
            <b>{save.counts.dailyClears}</b>
            <span className="label faint">Full days</span>
          </div>
          <div className="stat">
            <b>{save.inventory.length}</b>
            <span className="label faint">Finds</span>
          </div>
        </div>
      </div>

      <div className="sheet-body">
        <ul>
          {rows.map(({ feat, value, goal, done }) => (
            <li key={feat.id} className="feat" data-done={done}>
              <Icon kind="prop" id={done ? 'feat' : 'feat_locked'} size={40} res={22} />
              <div className="feat-main">
                <div className="feat-name">{feat.name}</div>
                <div className="feat-desc">
                  {feat.desc}
                  {feat.item && ITEM_BY_ID[feat.item] ? ` Reward: ${ITEM_BY_ID[feat.item].name}.` : ''}
                </div>
                {!done && goal > 1 && (
                  <div className="gauge">
                    {value > 0 && <div className="gauge-fill" style={{ width: `${(value / goal) * 100}%` }} />}
                  </div>
                )}
              </div>
              <div className="quest-side">
                <span className="xp" style={done ? { color: 'var(--faint)' } : undefined}>
                  +{feat.xp}
                </span>
                {!done && goal > 1 && (
                  <span className="label faint">
                    {value}/{goal}
                  </span>
                )}
              </div>
            </li>
          ))}
        </ul>
      </div>
    </>
  );
}
