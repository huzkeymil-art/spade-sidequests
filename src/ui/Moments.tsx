import { useEffect, useState } from 'react';
import { sfx } from '../audio/sfx';
import { FEAT_BY_ID, ITEM_BY_ID } from '../game/content';
import { DAILY_CLEAR_XP, rankFor } from '../game/rewards';
import { useStore, type Moment, type Toast } from '../game/store';
import { Unearth } from '../three/unearth';
import { Icon, RARITY_LIGHT, useStage } from './stage';

// The big moments: the title screen, digging up an item, levelling up, and
// the small notices for feats.

/** First launch: the logo over the scene, and a name to choose. */
export function Title() {
  const begin = useStore((s) => s.begin);
  const [name, setName] = useState('');

  const start = () => {
    sfx.dig();
    begin(name);
  };

  return (
    <>
      <div className="title-logo">
        <h1 className="display">Spade</h1>
      </div>
      <div className="below">
        <p className="italic dim" style={{ fontSize: 19, paddingBottom: 18 }}>
          Real quests, every day, week and month. Dig a little. See what turns up.
        </p>
        <span className="label faint" style={{ paddingBottom: 9 }}>
          Name your digger
        </span>
        <label className="field plate">
          <input
            value={name}
            maxLength={16}
            placeholder="Digger"
            onChange={(e) => setName(e.target.value)}
            onKeyDown={(e) => e.key === 'Enter' && start()}
            enterKeyHint="go"
            autoCapitalize="words"
            autoComplete="off"
          />
        </label>
        <div className="spacer" />
        <button className="btn plate primary block" onClick={start}>
          Break ground
        </button>
        {!installed() && (
          <p className="label faint" style={{ paddingTop: 12, textAlign: 'center', lineHeight: 1.35 }}>
            Tip: tap Share, then Add to Home Screen
          </p>
        )}
      </div>
    </>
  );
}

/** True when Spade is running as a home-screen app rather than in a browser tab. */
function installed(): boolean {
  const iosStandalone = (navigator as Navigator & { standalone?: boolean }).standalone === true;
  return iosStandalone || window.matchMedia('(display-mode: standalone)').matches;
}

/** An item being dug up. The 3D scene plays the dig; this adds the words. */
export function Found({ moment }: { moment: Extract<Moment, { type: 'item' }> }) {
  const stage = useStage();
  const equip = useStore((s) => s.equip);
  const nextMoment = useStore((s) => s.nextMoment);
  const equipped = useStore((s) => s.save.equipped);
  const [shown, setShown] = useState(false);
  const item = ITEM_BY_ID[moment.itemId];

  useEffect(() => {
    stage.playUnearth(item.id, RARITY_LIGHT[item.rarity]);
    sfx.dig();
    const reveal = window.setTimeout(() => sfx.reveal(), 1050);
    const words = window.setTimeout(() => setShown(true), Unearth.REVEAL_SECONDS * 1000);
    return () => {
      clearTimeout(reveal);
      clearTimeout(words);
      stage.endUnearth();
    };
  }, [stage, item.id, item.rarity]);

  if (!shown) return <div className="below" onClick={() => setShown(true)} />;

  const wearing = equipped[item.slot] === item.id;

  return (
    <div className="below reveal">
      <span className={`label rarity-${item.rarity}`}>
        {moment.fresh ? 'Unearthed' : 'Found again'} · {item.rarity} {item.slot}
      </span>
      <h2 className="display found-name">{item.name}</h2>
      <p className="italic dim">{moment.fresh ? item.lore : `You already carry one, so it becomes +${moment.echoXp} XP.`}</p>
      <div className="spacer" />
      <div style={{ display: 'flex', gap: 10 }}>
        {moment.fresh && !wearing && (
          <button
            className="btn plate primary"
            style={{ flex: 1 }}
            onClick={() => {
              sfx.done();
              equip(item.slot, item.id);
              nextMoment();
            }}
          >
            Wear it
          </button>
        )}
        <button
          className={`btn plate ${moment.fresh && !wearing ? '' : 'primary'}`}
          style={{ flex: 1 }}
          onClick={() => {
            sfx.tap();
            nextMoment();
          }}
        >
          {moment.fresh && !wearing ? 'Stow it' : 'Keep digging'}
        </button>
      </div>
    </div>
  );
}

/** A new level. Tap anywhere to carry on. */
export function LevelUp({ moment }: { moment: Extract<Moment, { type: 'level' }> }) {
  const stage = useStage();
  const nextMoment = useStore((s) => s.nextMoment);

  useEffect(() => {
    stage.burst();
    sfx.level();
  }, [stage, moment.level]);

  return (
    <button className="levelup reveal" onClick={nextMoment} aria-label="Continue">
      <span className="label dim">Level</span>
      <span className="display levelup-number">{moment.level}</span>
      <span style={{ fontSize: 22 }}>{moment.rank ? `New rank: ${moment.rank}` : rankFor(moment.level)}</span>
      <span className="label faint" style={{ paddingTop: 22 }}>
        Tap to carry on
      </span>
    </button>
  );
}

/** Small notices that slide in at the top and leave on their own. */
export function Toasts() {
  const toasts = useStore((s) => s.toasts);
  return (
    <div className="toasts">
      {toasts.slice(0, 3).map((toast) => (
        <ToastRow key={toast.id} toast={toast} />
      ))}
    </div>
  );
}

function ToastRow({ toast }: { toast: Toast }) {
  const dropToast = useStore((s) => s.dropToast);

  useEffect(() => {
    if (toast.kind === 'feat') sfx.feat();
    const timer = window.setTimeout(() => dropToast(toast.id), 3200);
    return () => clearTimeout(timer);
  }, [toast.id, toast.kind, dropToast]);

  if (toast.kind === 'clear') {
    return (
      <div className="toast plate" style={{ ['--edge' as string]: 'var(--lantern)' }}>
        <Icon kind="prop" id="flame" size={30} res={20} />
        <div className="toast-main">
          <div>Lantern full</div>
          <div className="label faint" style={{ marginTop: 4 }}>
            Every quest today
          </div>
        </div>
        <span className="xp" style={{ color: 'var(--lantern)' }}>
          +{DAILY_CLEAR_XP}
        </span>
      </div>
    );
  }

  const feat = toast.ref ? FEAT_BY_ID[toast.ref] : undefined;
  if (!feat) return null;
  return (
    <div className="toast plate">
      <Icon kind="prop" id="feat" size={30} res={22} />
      <div className="toast-main">
        <div>{feat.name}</div>
        <div className="label faint" style={{ marginTop: 4 }}>
          Feat earned
        </div>
      </div>
      <span className="xp">+{feat.xp}</span>
    </div>
  );
}
