import type { Cadence } from './types';

// Time in Spade is chopped into days, weeks and months. Each one gets a short
// name called a "key", like "2026-11-14". Two moments belong to the same day
// exactly when they have the same day key. Everything uses the phone's local
// clock, so "today" means the player's today.

const pad = (n: number, width = 2) => String(n).padStart(width, '0');

/** "2026-11-14" */
export function dayKey(d: Date): string {
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
}

/** "2026-11" */
export function monthKey(d: Date): string {
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}`;
}

/** 0 = Monday ... 6 = Sunday */
export function weekdayIndex(d: Date): number {
  return (d.getDay() + 6) % 7;
}

/**
 * "2026-W46". Weeks start on Monday and follow the international (ISO) rule:
 * a week belongs to the year that holds its Thursday.
 */
export function weekKey(d: Date): string {
  // Work in UTC with just the calendar date, so daylight-saving shifts can't interfere.
  const t = new Date(Date.UTC(d.getFullYear(), d.getMonth(), d.getDate()));
  const weekday = (t.getUTCDay() + 6) % 7;
  t.setUTCDate(t.getUTCDate() - weekday + 3); // this week's Thursday
  const year = t.getUTCFullYear();
  const firstThursday = new Date(Date.UTC(year, 0, 4));
  const firstWeekday = (firstThursday.getUTCDay() + 6) % 7;
  firstThursday.setUTCDate(firstThursday.getUTCDate() - firstWeekday + 3);
  const week = 1 + Math.round((t.getTime() - firstThursday.getTime()) / (7 * 86400000));
  return `${year}-W${pad(week)}`;
}

export function periodKey(cadence: Cadence, d: Date): string {
  return cadence === 'daily' ? dayKey(d) : cadence === 'weekly' ? weekKey(d) : monthKey(d);
}

/** Turns "2026-11-14" back into a date (at local midnight). */
export function parseDay(key: string): Date {
  const [y, m, d] = key.split('-').map(Number);
  return new Date(y, m - 1, d);
}

/** The day key `n` days after (or before, if negative) the given one. */
export function shiftDay(key: string, n: number): string {
  const d = parseDay(key);
  d.setDate(d.getDate() + n);
  return dayKey(d);
}

/** The seven day keys of the week containing `d`, Monday first. */
export function weekDays(d: Date): string[] {
  const monday = new Date(d.getFullYear(), d.getMonth(), d.getDate() - weekdayIndex(d));
  return Array.from({ length: 7 }, (_, i) => dayKey(new Date(monday.getFullYear(), monday.getMonth(), monday.getDate() + i)));
}

/** How far through the month `d` is: just above 0 on the 1st, 1 on the last day. */
export function monthProgress(d: Date): number {
  const daysInMonth = new Date(d.getFullYear(), d.getMonth() + 1, 0).getDate();
  return d.getDate() / daysInMonth;
}

/** The moment the current day, week or month ends and a fresh board is dealt. */
export function nextReset(cadence: Cadence, d: Date): Date {
  if (cadence === 'daily') return new Date(d.getFullYear(), d.getMonth(), d.getDate() + 1);
  if (cadence === 'weekly') return new Date(d.getFullYear(), d.getMonth(), d.getDate() + (7 - weekdayIndex(d)));
  return new Date(d.getFullYear(), d.getMonth() + 1, 1);
}

/** "5h 12m", "3d 4h" or "42m": a short countdown. */
export function formatCountdown(ms: number): string {
  const minutes = Math.max(0, Math.ceil(ms / 60000));
  const days = Math.floor(minutes / 1440);
  const hours = Math.floor((minutes % 1440) / 60);
  const mins = minutes % 60;
  if (days > 0) return `${days}d ${hours}h`;
  if (hours > 0) return `${hours}h ${mins}m`;
  return `${mins}m`;
}
