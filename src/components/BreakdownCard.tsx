import { cn, formatTimestamp, formatRelativeTime } from '@/lib/utils'
import { Clock, Wrench, CheckCircle, AlertCircle } from 'lucide-react'
import type { BreakdownRow } from '@/lib/monitoring'
import type { BreakdownStatus } from '@/lib/supabase'

export const STATUS_META = {
  open:        { label:'Terbuka',    color:'text-accent-red',    bg:'bg-accent-red/10',    icon: AlertCircle },
  in_progress: { label:'Dikerjakan', color:'text-accent-yellow', bg:'bg-accent-yellow/10', icon: Wrench      },
  resolved:    { label:'Selesai',    color:'text-status-good',   bg:'bg-status-good/10',   icon: CheckCircle },
}

export const CAT_LABELS: Record<string,string> = {
  lightning:'Petir', mechanical:'Mekanik', electrical:'Listrik',
  communication:'Komunikasi', flood:'Banjir', maintenance:'Perawatan', other:'Lainnya',
}

export type BdReport = BreakdownRow

export function BreakdownCard({ r, canEdit, onStatus, updating }: {
  r: BdReport; canEdit: boolean
  onStatus: (id: string, s: BreakdownStatus) => Promise<void>; updating: boolean
}) {
  const meta = STATUS_META[r.status as keyof typeof STATUS_META] ?? STATUS_META.open
  const SI = meta.icon
  return (
    <div className="bg-surface border border-border rounded-card p-4">
      <div className="flex items-start gap-3">
        <div className={cn('p-2 rounded-lg flex-shrink-0', meta.bg)}>
          <SI className={cn('w-4 h-4', meta.color)} />
        </div>
        <div className="flex-1 min-w-0">
          <div className="flex items-start justify-between gap-2 flex-wrap">
            <div>
                <p className="text-sm font-semibold text-text-primary">{r.cause}</p>
              <p className="text-[10px] text-text-secondary mt-0.5">
                {CAT_LABELS[r.cause_category] ?? r.cause_category} · {formatTimestamp(r.outage_start ?? r.event_date,'dd MMM HH:mm')}
              </p>
            </div>
            <span className={cn('text-[10px] font-bold px-2 py-0.5 rounded-full border',
              meta.color, meta.bg, 'border-current/30')}>{meta.label}</span>
          </div>
          {r.corrective_action && <p className="text-xs text-text-secondary mt-2 line-clamp-2">{r.corrective_action}</p>}
          <div className="flex flex-wrap gap-x-4 mt-2 text-[10px] text-text-secondary">
            {r.duration_hours != null && (
              <span className="flex items-center gap-1"><Clock className="w-3 h-3" />{r.duration_hours} jam</span>
            )}
            {r.outage_end && <span>Selesai: {formatRelativeTime(r.outage_end)}</span>}
            {r.affected_devices.length > 0 && (
              <span>Perangkat: {r.affected_devices.join(', ')}</span>
            )}
          </div>
          {canEdit && r.status !== 'resolved' && (
            <div className="flex gap-2 mt-3">
              {r.status === 'open' && (
                <button onClick={() => { void onStatus(r.id,'in_progress') }} disabled={updating}
                  className="text-[10px] px-2.5 py-1 border border-accent-yellow/50 text-accent-yellow rounded hover:bg-accent-yellow/10 disabled:opacity-50">
                  Mulai Kerjakan
                </button>
              )}
              <button onClick={() => { void onStatus(r.id,'resolved') }} disabled={updating}
                className="text-[10px] px-2.5 py-1 border border-status-good/50 text-status-good rounded hover:bg-status-good/10 disabled:opacity-50">
                Tandai Selesai
              </button>
            </div>
          )}
        </div>
      </div>
    </div>
  )
}
