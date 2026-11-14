import { Sheet } from './Sheet';
import { feedback } from './feedback';
import { Icon } from './stage';

const ROWS: { icon: string; title: string; text: string }[] = [
  { icon: 'seal', title: 'Hold to seal', text: 'Press and hold a quest until its square fills. A quick tap does nothing, so nothing gets sealed by accident.' },
  { icon: 'flame', title: 'The lantern is today', text: 'It burns brighter with each daily quest you finish. Keep a streak going and the flame changes colour.' },
  { icon: 'feat', title: 'The runes are your week', text: 'Monday is at the bottom of the stone. A rune lights for every day you finish at least one daily.' },
  { icon: 'moon', title: 'The moon is your month', text: 'A thin sliver on the 1st, full on the last day. Monthly quests reset when it starts over.' },
  { icon: 'satchel', title: 'Quests dig things up', text: 'Weekly and monthly quests always unearth an item. Daily quests sometimes do.' },
];

/** A short welcome sheet that explains how to play and how to read the scene. */
export function Guide({ onClose }: { onClose: () => void }) {
  return (
    <Sheet
      title="How Spade works"
      onClose={onClose}
      footer={
        <button
          className="btn plate primary block"
          onClick={() => {
            feedback.tap();
            onClose();
          }}
        >
          Start digging
        </button>
      }
    >
      <ul>
        {ROWS.map((row) => (
          <li key={row.title} className="guide-row">
            <Icon kind="prop" id={row.icon} size={46} res={24} />
            <div>
              <div>{row.title}</div>
              <p>{row.text}</p>
            </div>
          </li>
        ))}
      </ul>
    </Sheet>
  );
}
