import { cn, formatRelativeTime } from '@/lib/utils'
import type { Alarm } from '@/lib/supabase'
import { AlertTriangle, Check, Clock3, Gauge, MessageSquare } from 'lucide-react'

const PRIORITY_STYLE: Record<string, string> = {
  critical: 'border-l-accent-red bg-accent-red/5 text-accent-red',
  high:     'border-l-accent-orange bg-accent-orange/5 text-accent-orange',
  medium:   'border-l-accent-yellow bg-accent-yellow/5 text-accent-yellow',
  low:      'border-l-accent-blue bg-accent-blue/5 text-accent-blue',
  info:     'border-l-border bg-surface-2 text-text-secondary',
}

const PRIORITY_LABEL: Record<string, string> = {
  critical: 'CRITICAL', high: 'HIGH', medium: 'MED', low: 'LOW', info: 'INFO',
}

const ALARM_TYPE_LABEL: Record<string, string> = {
  high_high: 'High-high', high: 'High', low: 'Low', low_low: 'Low-low',
  comm_failure: 'Komunikasi', data_stale: 'Data stale', device_offline: 'Perangkat offline', system: 'Sistem', manual: 'Manual',
}

interface AlarmRowProps {
  alarm: Alarm
  onAck?: (id: string) => void
  acking?: boolean
  canAck?: boolean
}

export function AlarmRow({ alarm, onAck, acking, canAck }: AlarmRowProps) {
  const style = PRIORITY_STYLE[alarm.priority] ?? PRIORITY_STYLE['info']!
  const label = PRIORITY_LABEL[alarm.priority] ?? alarm.priority.toUpperCase()

  return (
    <div className={cn(
      'flex items-start gap-3 p-3 border-l-2 rounded-r-card border border-border',
      style,
    )}>
      <div className="flex flex-shrink-0 flex-col items-center gap-1 mt-0.5">
        <AlertTriangle className="h-4 w-4" aria-hidden="true" />
        <span className="text-[10px] font-bold bg-current/10 px-1.5 py-0.5 rounded leading-none">{label}</span>
      </div>

      {/* Message */}
      <div className="flex-1 min-w-0">
        <p className="text-sm font-medium text-text-primary leading-snug">{alarm.message}</p>
        <div className="mt-1 flex flex-wrap items-center gap-x-2 gap-y-1 text-[10px] text-text-secondary">
          <span>{alarm.tag_id ?? 'Sistem'}</span>
          <span aria-hidden="true">·</span>
          <span>{ALARM_TYPE_LABEL[alarm.alarm_type] ?? alarm.alarm_type}</span>
          <span aria-hidden="true">·</span>
          <span className="inline-flex items-center gap-1"><Clock3 className="h-3 w-3" aria-hidden="true" />{formatRelativeTime(alarm.active_at)}</span>
          {alarm.status === 'acknowledged' && (
            <span className="inline-flex items-center gap-1 text-status-good"><Check className="h-3 w-3" aria-hidden="true" />Sudah diakui</span>
          )}
        </div>
        {(alarm.value_at_alarm != null || alarm.threshold_value != null || alarm.ack_comment) && (
          <div className="mt-2 flex flex-wrap items-center gap-2 text-[10px] text-text-secondary">
            {alarm.value_at_alarm != null && <span className="inline-flex items-center gap-1 rounded bg-surface-2 px-1.5 py-1"><Gauge className="h-3 w-3" aria-hidden="true" />Nilai {alarm.value_at_alarm}</span>}
            {alarm.threshold_value != null && <span className="rounded bg-surface-2 px-1.5 py-1">Batas {alarm.threshold_value}</span>}
            {alarm.ack_comment && <span className="inline-flex items-center gap-1 italic"><MessageSquare className="h-3 w-3" aria-hidden="true" />{alarm.ack_comment}</span>}
          </div>
        )}
      </div>

      {/* Ack button */}
      {canAck && alarm.status === 'active' && onAck && (
        <button
          disabled={acking}
          onClick={() => onAck(alarm.id)}
          aria-label={`Akui alarm: ${alarm.message}`}
          className="flex-shrink-0 text-[10px] px-2 py-1 border border-current/30 rounded hover:bg-current/10 transition-colors disabled:opacity-50"
        >
          {acking ? '…' : 'Ack'}
        </button>
      )}
    </div>
  )
}

interface AlarmListProps {
  alarms: Alarm[]
  loading?: boolean
  onAck?: (id: string) => void
  ackingId?: string | null
  canAck?: boolean
  maxRows?: number
  emptyMessage?: string
}

export function AlarmList({
  alarms,
  loading = false,
  onAck,
  ackingId,
  canAck,
  maxRows,
  emptyMessage = 'Tidak ada alarm aktif.',
}: AlarmListProps) {
  if (loading) {
    return (
      <div className="space-y-2">
        {[1, 2, 3].map((i) => (
          <div key={i} className="skeleton h-14 w-full rounded" />
        ))}
      </div>
    )
  }

  const displayed = maxRows ? alarms.slice(0, maxRows) : alarms

  if (displayed.length === 0) {
    return (
      <div className="text-center py-8 text-text-secondary text-sm">{emptyMessage}</div>
    )
  }

  return (
    <div className="space-y-2">
      {displayed.map((alarm) => (
        <AlarmRow
          key={alarm.id}
          alarm={alarm}
          onAck={onAck}
          acking={ackingId === alarm.id}
          canAck={canAck}
        />
      ))}
    </div>
  )
}
