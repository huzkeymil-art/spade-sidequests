import { useEffect, useRef, useState } from 'react';
import { setSoundEnabled, sfx, unlockAudio } from '../audio/sfx';
import { monthProgress, weekDays, weekdayIndex } from '../game/periods';
import { levelInfo, rankFor } from '../game/rewards';
import { useStore } from '../game/store';
import { Stage, type View } from '../three/Stage';
import { Feats } from './Feats';
import { HeroScreen } from './HeroScreen';
import { Found, LevelUp, Title, Toasts } from './Moments';
import { QuestBoard } from './QuestBoard';
import { Satchel } from './Satchel';
import { Settings } from './Settings';
import { Icon, Portrait, StageContext, gearOf, lookOf } from './stage';

type Tab = 'quests' | 'hero' | 'satchel' | 'feats';

const TABS: { id: Tab; name: string; icon: string }[] = [
  { id: 'quests', name: 'Quests', icon: 'scroll' },
  { id: 'hero', name: 'Hero', icon: '' },
  { id: 'satchel', name: 'Satchel', icon: 'satchel' },
  { id: 'feats', name: 'Feats', icon: 'feat' },
];

export function App() {
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const [stage, setStage] = useState<Stage | null>(null);
  const [tab, setTab] = useState<Tab>('quests');
  const [settingsOpen, setSettingsOpen] = useState(false);

  const save = useStore((s) => s.save);
  const now = useStore((s) => s.now);
  const moment = useStore((s) => s.moments[0]);
  const sync = useStore((s) => s.sync);

  // Which camera shot the 3D stage should be on.
  const view: View = !save.onboarded ? 'title' : moment?.type === 'item' ? 'dig' : tab;

  // Create the 3D stage once the canvas exists.
  useEffect(() => {
    const created = new Stage(canvasRef.current!);
    created.start();
    setStage(created);
    return () => created.dispose();
  }, []);

  // Keep the boards in step with the clock: on launch, every half minute, and on returning to the app.
  useEffect(() => {
    sync();
    const timer = window.setInterval(sync, 30000);
    const onShow = () => !document.hidden && sync();
    document.addEventListener('visibilitychange', onShow);
    return () => {
      clearInterval(timer);
      document.removeEventListener('visibilitychange', onShow);
    };
  }, [sync]);

  // Phones only allow sound once the player has touched the screen.
  useEffect(() => {
    const events = ['touchend', 'pointerup', 'click'] as const;
    events.forEach((name) => window.addEventListener(name, unlockAudio, { passive: true }));
    return () => events.forEach((name) => window.removeEventListener(name, unlockAudio));
  }, []);

  // Push the game's state into the scene.
  const firstView = useRef(true);
  useEffect(() => {
    if (!stage) return;
    if (firstView.current) stage.snapView(view);
    else stage.setView(view);
    firstView.current = false;
  }, [stage, view]);

  useEffect(() => {
    stage?.setHero(lookOf(save.hero), gearOf(save));
  }, [stage, save.hero, save.equipped]); // eslint-disable-line react-hooks/exhaustive-deps

  useEffect(() => {
    stage?.setRetro(save.settings.retro);
  }, [stage, save.settings.retro]);

  useEffect(() => {
    setSoundEnabled(save.settings.sound);
  }, [save.settings.sound]);

  useEffect(() => {
    if (!stage) return;
    const today = new Date(now);
    const days = weekDays(today);
    const daily = save.boards.daily.quests;
    stage.setProgress({
      dailyDone: daily.filter((q) => q.done).length,
      dailyTotal: daily.length,
      streak: save.streak.count,
      week: days.map((d) => save.activeDays.includes(d)),
      today: weekdayIndex(today),
      month: monthProgress(today),
    });
  }, [stage, now, save.boards.daily, save.streak.count, save.activeDays]);

  const { level, into, need } = levelInfo(save.xp);
  const playing = save.onboarded && !moment;

  return (
    <div className="app">
      <canvas ref={canvasRef} className="stage" />

      {stage && (
        <StageContext.Provider value={stage}>
          {!save.onboarded && <Title />}

          {save.onboarded && (
            <>
              <div className="hud" hidden={!!moment}>
                <div className="hud-plate plate">
                  <span className="label faint">Lv</span>
                  <span className="display hud-level">{level}</span>
                  <span className="label">{rankFor(level)}</span>
                </div>
                <div className="hud-right">
                  <div className="hud-plate plate" aria-label={`${save.streak.count} day streak`}>
                    <Icon kind="prop" id={save.streak.count > 0 ? 'flame' : 'flame_out'} size={26} res={20} />
                    <span className="hud-streak" style={{ color: save.streak.count > 0 ? 'var(--lantern)' : 'var(--faint)' }}>
                      {save.streak.count}
                    </span>
                  </div>
                  <button
                    className="hud-plate plate"
                    aria-label="Settings"
                    onClick={() => {
                      sfx.tap();
                      setSettingsOpen(true);
                    }}
                  >
                    <Icon kind="prop" id="gear" size={24} res={20} />
                  </button>
                </div>
              </div>

              <div className="sheet" hidden={!playing}>
                <div style={{ padding: '0 18px' }}>
                  <div className="gauge">
                    {into > 0 && <div className="gauge-fill" style={{ width: `${(into / need) * 100}%` }} />}
                    <div className="gauge-ticks" />
                  </div>
                  <div className="gauge-row">
                    <span className="label faint">
                      {into} / {need} XP
                    </span>
                    <span className="label faint">Level {level + 1} next</span>
                  </div>
                </div>

                {tab === 'quests' && <QuestBoard />}
                {tab === 'hero' && <HeroScreen />}
                {tab === 'satchel' && <Satchel />}
                {tab === 'feats' && <Feats />}

                <nav className="tabbar" role="tablist">
                  {TABS.map((t) => (
                    <button
                      key={t.id}
                      role="tab"
                      aria-selected={tab === t.id}
                      className="tab"
                      onClick={() => {
                        sfx.tap();
                        setTab(t.id);
                      }}
                    >
                      {t.id === 'hero' ? (
                        <Portrait hero={save.hero} gear={gearOf(save)} size={30} />
                      ) : (
                        <Icon kind="prop" id={t.icon} size={30} res={22} />
                      )}
                      <span className="label">{t.name}</span>
                    </button>
                  ))}
                </nav>
              </div>

              {moment?.type === 'item' && <Found key={`${moment.itemId}-${moment.from}`} moment={moment} />}
              {moment?.type === 'level' && <LevelUp key={moment.level} moment={moment} />}
              <Toasts />
              {settingsOpen && <Settings onClose={() => setSettingsOpen(false)} />}
            </>
          )}
        </StageContext.Provider>
      )}
    </div>
  );
}
