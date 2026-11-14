import { useEffect, useRef, useState } from 'react';
import { setSoundEnabled, unlockAudio } from '../audio/sfx';
import { monthProgress, weekDays, weekdayIndex } from '../game/periods';
import { levelInfo, rankFor } from '../game/rewards';
import { useStore } from '../game/store';
import { Stage, type View } from '../three/Stage';
import { Feats } from './Feats';
import { Guide } from './Guide';
import { HeroScreen } from './HeroScreen';
import { Found, LevelUp, Title, Toasts } from './Moments';
import { QuestBoard } from './QuestBoard';
import { Satchel } from './Satchel';
import { Settings } from './Settings';
import { feedback } from './feedback';
import { formatNumber, prefersReducedMotion, requestPersistence, setHapticsEnabled, watchKeyboard } from './platform';
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
  // Screens are built the first time their tab is opened and then kept, so each
  // one remembers where it was scrolled to, the way tabs do in iPhone apps.
  const [opened, setOpened] = useState<Tab[]>(['quests']);
  const [settingsOpen, setSettingsOpen] = useState(false);
  const [guideOpen, setGuideOpen] = useState(false);

  const save = useStore((s) => s.save);
  const now = useStore((s) => s.now);
  const moment = useStore((s) => s.moments[0]);
  const sync = useStore((s) => s.sync);
  const setSettings = useStore((s) => s.setSettings);

  // Which camera shot the 3D stage should be on.
  const view: View = !save.onboarded ? 'title' : moment?.type === 'item' ? 'dig' : tab;
  const playing = save.onboarded && !moment;

  // Create the 3D stage once the canvas exists.
  useEffect(() => {
    const created = new Stage(canvasRef.current!);
    created.setReducedMotion(prefersReducedMotion());
    created.start();
    setStage(created);
    return () => created.dispose();
  }, []);

  // One-time wiring to the phone itself.
  useEffect(() => {
    const stopKeyboard = watchKeyboard();
    // iPhones only show a button's "pressed" look if something is listening for touches.
    const noop = () => {};
    document.addEventListener('touchstart', noop, { passive: true });
    // Phones only allow sound once the player has touched the screen.
    const unlockOn = ['touchend', 'pointerup', 'click'] as const;
    unlockOn.forEach((name) => window.addEventListener(name, unlockAudio, { passive: true }));
    return () => {
      stopKeyboard();
      document.removeEventListener('touchstart', noop);
      unlockOn.forEach((name) => window.removeEventListener(name, unlockAudio));
    };
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

  // Once there is progress worth keeping, ask the phone not to clear it.
  useEffect(() => {
    if (save.onboarded) requestPersistence();
  }, [save.onboarded]);

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
    setHapticsEnabled(save.settings.haptics);
  }, [save.settings.sound, save.settings.haptics]);

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

  // New players get a short explanation once the first dig is out of the way.
  useEffect(() => {
    if (playing && !save.settings.guideSeen) setGuideOpen(true);
  }, [playing, save.settings.guideSeen]);

  const pickTab = (next: Tab) => {
    feedback.select();
    if (next === tab) {
      // Tapping the tab you are already on jumps its list back to the top.
      document.querySelector('.screen:not([hidden]) .sheet-body')?.scrollTo({ top: 0, behavior: prefersReducedMotion() ? 'auto' : 'smooth' });
      return;
    }
    if (!opened.includes(next)) setOpened([...opened, next]);
    setTab(next);
  };

  const closeGuide = () => {
    setGuideOpen(false);
    if (!save.settings.guideSeen) setSettings({ guideSeen: true });
  };

  const { level, into, need } = levelInfo(save.xp);

  return (
    <div className="app">
      <canvas ref={canvasRef} className="stage" aria-hidden="true" />

      {stage && (
        <StageContext.Provider value={stage}>
          {!save.onboarded && <Title />}

          {save.onboarded && (
            <>
              <div className="hud" hidden={!!moment}>
                <div className="hud-plate plate" aria-label={`Level ${level}, ${rankFor(level)}`}>
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
                      feedback.tap();
                      setSettingsOpen(true);
                    }}
                  >
                    <Icon kind="prop" id="gear" size={24} res={20} />
                  </button>
                </div>
              </div>

              <div className="sheet" hidden={!playing}>
                <div style={{ padding: '0 var(--margin)' }}>
                  <div
                    className="gauge"
                    role="progressbar"
                    aria-label={`Experience toward level ${level + 1}`}
                    aria-valuemin={0}
                    aria-valuemax={need}
                    aria-valuenow={into}
                  >
                    {into > 0 && <div className="gauge-fill" style={{ width: `${(into / need) * 100}%` }} />}
                    <div className="gauge-ticks" />
                  </div>
                  <div className="gauge-row">
                    <span className="label faint">
                      {formatNumber(into)} / {formatNumber(need)} XP
                    </span>
                    <span className="label faint">Level {level + 1} next</span>
                  </div>
                </div>

                {opened.includes('quests') && (
                  <div className="screen" hidden={tab !== 'quests'}>
                    <QuestBoard />
                  </div>
                )}
                {opened.includes('hero') && (
                  <div className="screen" hidden={tab !== 'hero'}>
                    <HeroScreen />
                  </div>
                )}
                {opened.includes('satchel') && (
                  <div className="screen" hidden={tab !== 'satchel'}>
                    <Satchel />
                  </div>
                )}
                {opened.includes('feats') && (
                  <div className="screen" hidden={tab !== 'feats'}>
                    <Feats />
                  </div>
                )}

                <div className="edge-fade" aria-hidden="true">
                  <i />
                  <i />
                  <i />
                  <i />
                </div>

                <nav className="dock plate" role="tablist" aria-label="Sections">
                  {TABS.map((t) => (
                    <button key={t.id} role="tab" aria-selected={tab === t.id} className="tab plate" onClick={() => pickTab(t.id)}>
                      {t.id === 'hero' ? (
                        <Portrait hero={save.hero} gear={gearOf(save)} size={28} />
                      ) : (
                        <Icon kind="prop" id={t.icon} size={28} res={22} />
                      )}
                      <span className="label">{t.name}</span>
                    </button>
                  ))}
                </nav>
              </div>

              {moment?.type === 'item' && <Found key={`${moment.itemId}-${moment.from}`} moment={moment} />}
              {moment?.type === 'level' && <LevelUp key={moment.level} moment={moment} />}
              <Toasts />
              {settingsOpen && (
                <Settings
                  onClose={() => setSettingsOpen(false)}
                  onGuide={() => {
                    setSettingsOpen(false);
                    setGuideOpen(true);
                  }}
                />
              )}
              {guideOpen && playing && <Guide onClose={closeGuide} />}
            </>
          )}
        </StageContext.Provider>
      )}

      <div className="turn-notice" aria-live="polite">
        <span className="display" style={{ fontSize: 48 }}>
          Spade
        </span>
        <span className="italic dim">Turn your phone upright to keep digging.</span>
      </div>
    </div>
  );
}
