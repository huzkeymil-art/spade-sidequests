import { useCallback, useEffect, useRef, useState, type ReactNode } from 'react';
import { createPortal } from 'react-dom';
import { feedback } from './feedback';
import { prefersReducedMotion } from './platform';

// Sheets and alerts, shaped the way an iPhone presents them.
//
// A sheet is a panel that slides up over the current screen. It has a small
// "grabber" bar at the top, can be dragged down to dismiss, and the screen
// behind it stays visible but dimmed, so you never lose your place.

/** Everything that floats above the app is drawn into the app's root element. */
function overlayRoot(): Element {
  return document.querySelector('.app') ?? document.body;
}

interface SheetProps {
  title: string;
  /** `large` fills most of the screen. `fit` is only as tall as its content. */
  size?: 'large' | 'fit';
  onClose: () => void;
  /** Stays pinned to the bottom of the sheet, above the keyboard (for the main button). */
  footer?: ReactNode;
  children: ReactNode;
}

const EXIT_MS = 180;

export function Sheet({ title, size = 'large', onClose, footer, children }: SheetProps) {
  const panel = useRef<HTMLDivElement>(null);
  const drag = useRef<{ y: number; at: number; lastY: number; lastAt: number } | null>(null);
  const [leaving, setLeaving] = useState(false);

  /** Plays the slide-down, then tells the owner to remove the sheet. */
  const close = useCallback(() => {
    if (leaving) return;
    setLeaving(true);
    window.setTimeout(onClose, prefersReducedMotion() ? 0 : EXIT_MS);
  }, [leaving, onClose]);

  // A hardware keyboard's Escape key closes the sheet.
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => e.key === 'Escape' && close();
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [close]);

  // Dragging the top of the sheet downward pulls it away.
  const onDown = (e: React.PointerEvent) => {
    if ((e.target as HTMLElement).closest('button')) return;
    drag.current = { y: e.clientY, at: e.timeStamp, lastY: e.clientY, lastAt: e.timeStamp };
    (e.currentTarget as HTMLElement).setPointerCapture(e.pointerId);
    if (panel.current) panel.current.style.transition = 'none';
  };

  const onMove = (e: React.PointerEvent) => {
    const d = drag.current;
    if (!d || !panel.current) return;
    const pulled = Math.max(0, e.clientY - d.y);
    panel.current.style.transform = `translateY(${pulled}px)`;
    d.lastY = e.clientY;
    d.lastAt = e.timeStamp;
  };

  const onUp = (e: React.PointerEvent) => {
    const d = drag.current;
    drag.current = null;
    if (!d || !panel.current) return;
    const pulled = Math.max(0, e.clientY - d.y);
    const speed = pulled / Math.max(1, e.timeStamp - d.at); // pixels per millisecond
    panel.current.style.transition = '';
    panel.current.style.transform = '';
    // Far enough, or flicked fast enough: let go. Otherwise it springs back.
    if (pulled > 110 || (pulled > 30 && speed > 0.7)) close();
  };

  return createPortal(
    <>
      <div className={`scrim ${leaving ? 'leaving' : ''}`} onClick={close} />
      <div ref={panel} className={`modal-sheet ${size} ${leaving ? 'leaving' : ''}`} role="dialog" aria-modal="true" aria-label={title}>
        <div className="sheet-drag" onPointerDown={onDown} onPointerMove={onMove} onPointerUp={onUp} onPointerCancel={onUp}>
          <span className="grabber" />
          <div className="sheet-bar">
            <h2 className="display sheet-title">{title}</h2>
            <button
              className="icon-btn plate"
              aria-label="Close"
              onClick={() => {
                feedback.tap();
                close();
              }}
            >
              <span className="glyph-x" />
            </button>
          </div>
        </div>
        <div className="sheet-scroll">{children}</div>
        {footer && <div className="sheet-foot">{footer}</div>}
      </div>
    </>,
    overlayRoot(),
  );
}

interface ConfirmProps {
  title: string;
  message: string;
  /** The label on the button that goes ahead. */
  action: string;
  /** Marks the action as something that can't be undone. */
  destructive?: boolean;
  onConfirm: () => void;
  onCancel: () => void;
}

/** A small alert that asks before doing something that can't be undone. */
export function Confirm({ title, message, action, destructive, onConfirm, onCancel }: ConfirmProps) {
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => e.key === 'Escape' && onCancel();
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [onCancel]);

  return createPortal(
    <>
      <div className="scrim alert-scrim" onClick={onCancel} />
      <div className="alert plate" role="alertdialog" aria-modal="true" aria-label={title}>
        <h2 className="alert-title">{title}</h2>
        <p className="alert-message">{message}</p>
        <div className="alert-actions">
          <button className="btn plate" onClick={onCancel}>
            Cancel
          </button>
          <button className={`btn plate ${destructive ? 'danger' : 'primary'}`} onClick={onConfirm}>
            {action}
          </button>
        </div>
      </div>
    </>,
    overlayRoot(),
  );
}

/** A row with a label on the left and an on/off switch on the right. The whole row is the button. */
export function ToggleRow({ label, note, checked, onChange }: { label: string; note?: string; checked: boolean; onChange: (next: boolean) => void }) {
  return (
    <button
      className="row"
      role="switch"
      aria-checked={checked}
      onClick={() => {
        feedback.select();
        onChange(!checked);
      }}
    >
      <span className="row-text">
        <span>{label}</span>
        {note && <span className="row-note">{note}</span>}
      </span>
      <span className="toggle plate" data-on={checked} />
    </button>
  );
}
