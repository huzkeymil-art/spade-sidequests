import { featProgress } from '../game/achievements';
import { FEATS, ITEM_BY_ID } from '../game/content';
import { useStore } from '../game/store';
import { formatNumber } from './platform';
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

  const stats: [number, string][] = [
    [save.counts.quests, 'Quests'],
    [save.counts.bestStreak, 'Best run'],
    [save.counts.dailyClears, 'Full days'],
    [save.inventory.length, 'Finds'],
  ];

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
          {stats.map(([value, name]) => (
            <div key={name} className="stat">
              <b>{formatNumber(value)}</b>
              <span className="label faint">{name}</span>
            </div>
          ))}
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
                  <div className="gauge" role="progressbar" aria-label={`${feat.name} progress`} aria-valuemin={0} aria-valuemax={goal} aria-valuenow={value}>
                    {value > 0 && <div className="gauge-fill" style={{ width: `${(value / goal) * 100}%` }} />}
                  </div>
                )}
              </div>
              <div className="quest-side">
                <span className="xp" style={done ? { color: 'var(--faint)' } : undefined}>
                  +{formatNumber(feat.xp)}
                </span>
                {done ? (
                  <span className="label faint">Earned</span>
                ) : (
                  goal > 1 && (
                    <span className="label faint">
                      {formatNumber(value)}/{formatNumber(goal)}
                    </span>
                  )
                )}
              </div>
            </li>
          ))}
        </ul>
      </div>
    </>
  );
}
