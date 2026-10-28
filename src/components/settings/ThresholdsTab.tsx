import { useEffect, useMemo, useState } from 'react'
import { Save, Search } from 'lucide-react'
import { toast } from 'sonner'
import { cn } from '@/lib/utils'
import { supabase, STATION_ID } from '@/lib/supabase'

const DEFAULT_ROWS = [
  { tag_id:'HYDRO.WATER_LEVEL',   name:'Muka Air',    unit:'m',    hh:2.5,  hi:2.0,  lo:0.8, ll:0.5  },
  { tag_id:'HYDRO.FLOW_RATE',     name:'Debit',       unit:'m³/s', hh:9.0,  hi:7.5,  lo:0.5, ll:0.2  },
  { tag_id:'POWER.ACTIVE_POWER',  name:'Daya Aktif',  unit:'kW',   hh:90,   hi:80,   lo:5,   ll:0    },
  { tag_id:'SYS.BATTERY_VOLTAGE', name:'Baterai',     unit:'V',    hh:14.5, hi:14.0, lo:11.5,ll:11.0 },
  { tag_id:'TURBINE.RPM',         name:'RPM Turbin',  unit:'rpm',  hh:1550, hi:1500, lo:800, ll:700  },
]
type ThRow = (typeof DEFAULT_ROWS)[number]
type Field = 'hh'|'hi'|'lo'|'ll'

const FIELD_LABELS: Record<Field, string> = { hh:'High-High', hi:'High', lo:'Low', ll:'Low-Low' }
const FIELD_COLORS: Record<Field, string> = {
  hh:'text-accent-red', hi:'text-accent-yellow', lo:'text-accent-blue', ll:'text-accent-purple'
}

export function ThresholdsTab() {
  const [rows, setRows]     = useState<ThRow[]>(DEFAULT_ROWS)
  const [saving, setSaving] = useState<string | null>(null)
  const [search, setSearch] = useState('')

  useEffect(() => {
    void supabase.from('tags')
      .select('tag_id,name,unit,alarm_high_high,alarm_high,alarm_low,alarm_low_low')
      .eq('station_id', STATION_ID)
      .order('tag_id')
      .then(({ data, error }) => {
        if (error) { toast.error(`Gagal memuat threshold: ${error.message}`); return }
        if (data?.length) setRows(data.map((r) => ({
          tag_id: r.tag_id, name: r.name, unit: r.unit ?? '',
          hh: r.alarm_high_high ?? 0, hi: r.alarm_high ?? 0,
          lo: r.alarm_low ?? 0, ll: r.alarm_low_low ?? 0,
        })))
      })
  }, [])

  function update(tag_id: string, f: Field, val: string) {
    setRows((prev) => prev.map((r) => r.tag_id === tag_id ? { ...r, [f]: Number(val) } : r))
  }

  const visibleRows = useMemo(() => rows.filter((row) => `${row.name} ${row.tag_id}`.toLowerCase().includes(search.trim().toLowerCase())), [rows, search])

  async function save(row: ThRow) {
    if (![row.hh, row.hi, row.lo, row.ll].every(Number.isFinite)) {
      toast.error(`Threshold ${row.name} harus berupa angka`); return
    }
    setSaving(row.tag_id)
    const { error } = await supabase.from('tags').update({
      alarm_high_high: row.hh, alarm_high: row.hi,
      alarm_low: row.lo, alarm_low_low: row.ll,
    }).eq('tag_id', row.tag_id).eq('station_id', STATION_ID)
    if (error) { setSaving(null); toast.error(`Gagal menyimpan threshold: ${error.message}`); return }
    setSaving(null)
    toast.success(`Threshold ${row.name} disimpan`)
  }

  return (
    <div className="space-y-4">
      <p className="text-xs text-text-secondary">
        Atur batas alarm High-High, High, Low, Low-Low untuk setiap tag sensor.
      </p>
      <label className="relative block max-w-md"><Search className="absolute left-3 top-1/2 h-3.5 w-3.5 -translate-y-1/2 text-text-secondary" aria-hidden="true" /><input value={search} onChange={(e) => setSearch(e.target.value)} placeholder="Cari nama atau tag…" className="scada-input pl-9" /></label>
      {rows.length === 0 && <p className="rounded-card border border-border bg-surface p-4 text-xs text-text-secondary">Belum ada tag pada stasiun ini.</p>}
      {rows.length > 0 && visibleRows.length === 0 && <p className="rounded-card border border-border bg-surface p-4 text-xs text-text-secondary">Tag tidak ditemukan.</p>}
      {visibleRows.map((row) => (
        <div key={row.tag_id} className="bg-surface border border-border rounded-card p-4">
          <div className="flex items-center justify-between mb-3">
            <div>
              <p className="text-sm font-semibold text-text-primary">{row.name}</p>
              <p className="text-[10px] text-text-secondary font-mono">{row.tag_id} · {row.unit}</p>
            </div>
            <button
              onClick={() => { void save(row) }}
              disabled={saving === row.tag_id}
              className="flex items-center gap-1.5 text-xs px-3 py-1.5 bg-accent-blue/10 border border-accent-blue/30 text-accent-blue rounded-input hover:bg-accent-blue/20 transition-colors disabled:opacity-50">
              <Save className="w-3 h-3" />
              {saving === row.tag_id ? 'Simpan…' : 'Simpan'}
            </button>
          </div>
          <div className="grid grid-cols-2 sm:grid-cols-4 gap-3">
            {(['hh','hi','lo','ll'] as Field[]).map((f) => (
              <div key={f}>
                <label className={cn('text-[10px] font-medium mb-1 block', FIELD_COLORS[f])}>
                  {FIELD_LABELS[f]}
                </label>
                <input
                  type="number" step="0.1" value={row[f]}
                  onChange={(e) => update(row.tag_id, f, e.target.value)}
                  aria-label={`${FIELD_LABELS[f]} ${row.name}`}
                  className="scada-input text-sm w-full" />
                <span className="text-[10px] text-text-secondary">{row.unit}</span>
              </div>
            ))}
          </div>
        </div>
      ))}
    </div>
  )
}
