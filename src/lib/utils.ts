import { clsx, type ClassValue } from 'clsx'
import { twMerge } from 'tailwind-merge'
import { format, formatDistanceToNowStrict, differenceInSeconds } from 'date-fns'
import { id as idLocale } from 'date-fns/locale'

/** Gabungkan className dengan dukungan conditional + dedupe Tailwind. */
export function cn(...inputs: ClassValue[]): string {
  return twMerge(clsx(inputs))
}

/**
 * Format timestamp ISO/Date ke string yang mudah dibaca.
 * Default: "dd MMM yyyy HH:mm:ss"
 */
export function formatTimestamp(
  ts: string | number | Date | null | undefined,
  fmt = 'dd MMM yyyy HH:mm:ss',
): string {
  if (!ts) return '-'
  try {
    const date = typeof ts === 'string' || typeof ts === 'number' ? new Date(ts) : ts
    if (Number.isNaN(date.getTime())) return '-'
    return format(date, fmt, { locale: idLocale })
  } catch {
    return '-'
  }
}

/** Format timestamp relatif, misal "5 menit lalu". */
export function formatRelativeTime(ts: string | number | Date | null | undefined): string {
  if (!ts) return '-'
  try {
    const date = typeof ts === 'string' || typeof ts === 'number' ? new Date(ts) : ts
    if (Number.isNaN(date.getTime())) return '-'
    return formatDistanceToNowStrict(date, { addSuffix: true, locale: idLocale })
  } catch {
    return '-'
  }
}

/** Format nilai numerik dengan satuan dan presisi tertentu. */
export function formatValue(
  value: number | null | undefined,
  unit?: string | null,
  precision = 2,
): string {
  if (value === null || value === undefined || Number.isNaN(value)) {
    return unit ? `-- ${unit}` : '--'
  }
  const rounded = value.toFixed(precision)
  return unit ? `${rounded} ${unit}` : rounded
}

/** Warna CSS berdasarkan quality measurement. */
export function getQualityColor(quality?: string | null): string {
  switch (quality) {
    case 'good':
      return '#22c55e'
    case 'stale':
      return '#f59e0b'
    case 'bad':
    case 'comm_failure':
      return '#ef4444'
    case 'uncertain':
      return '#8b5cf6'
    default:
      return '#6b7280'
  }
}

/** Warna CSS berdasarkan prioritas alarm. */
export function getAlarmColor(priority?: string | null): string {
  switch (priority) {
    case 'critical':
      return '#f85149'
    case 'high':
      return '#e3b341'
    case 'medium':
      return '#d29922'
    case 'low':
      return '#58a6ff'
    case 'info':
      return '#8b949e'
    default:
      return '#6b7280'
  }
}

/** Icon emoji berdasarkan prioritas alarm, dipakai saat ikon SVG tidak tersedia. */
export function getPriorityIcon(priority?: string | null): string {
  switch (priority) {
    case 'critical':
      return '🔴'
    case 'high':
      return '🟠'
    case 'medium':
      return '🟡'
    case 'low':
      return '🔵'
    case 'info':
      return 'ℹ️'
    default:
      return '⚪'
  }
}

/** Cek apakah timestamp sudah "stale" (lebih tua dari maxAgeSeconds). */
export function isStale(
  timestamp: string | number | Date | null | undefined,
  maxAgeSeconds: number,
): boolean {
  if (!timestamp) return true
  const date = typeof timestamp === 'string' || typeof timestamp === 'number' ? new Date(timestamp) : timestamp
  if (Number.isNaN(date.getTime())) return true
  return differenceInSeconds(new Date(), date) > maxAgeSeconds
}

/** Hitung durasi antara dua timestamp dalam format "Xh Ym Zs". */
export function calculateDuration(
  start: string | number | Date | null | undefined,
  end: string | number | Date | null | undefined = new Date(),
): string {
  if (!start) return '-'
  const startDate = typeof start === 'string' || typeof start === 'number' ? new Date(start) : start
  const endDate = end == null ? new Date() : typeof end === 'string' || typeof end === 'number' ? new Date(end) : end
  if (Number.isNaN(startDate.getTime()) || Number.isNaN(endDate.getTime())) return '-'

  let totalSeconds = differenceInSeconds(endDate, startDate)
  if (totalSeconds < 0) totalSeconds = 0

  const hours = Math.floor(totalSeconds / 3600)
  const minutes = Math.floor((totalSeconds % 3600) / 60)
  const seconds = totalSeconds % 60

  const parts: string[] = []
  if (hours > 0) parts.push(`${hours}h`)
  if (minutes > 0 || hours > 0) parts.push(`${minutes}m`)
  parts.push(`${seconds}s`)
  return parts.join(' ')
}

/** Format ukuran byte menjadi string human-readable (KB, MB, GB). */
export function formatBytes(bytes: number): string {
  if (bytes === 0) return '0 B'
  const units = ['B', 'KB', 'MB', 'GB', 'TB']
  const exponent = Math.floor(Math.log(bytes) / Math.log(1024))
  const size = bytes / Math.pow(1024, exponent)
  return `${size.toFixed(exponent === 0 ? 0 : 1)} ${units[exponent]}`
}

/** Debounce generik untuk input/search handler. */
export function debounce<Args extends unknown[]>(
  fn: (...args: Args) => void,
  delay: number,
): (...args: Args) => void {
  let timeoutId: ReturnType<typeof setTimeout> | undefined
  return (...args: Args) => {
    if (timeoutId) clearTimeout(timeoutId)
    timeoutId = setTimeout(() => fn(...args), delay)
  }
}
