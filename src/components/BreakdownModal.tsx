import { useState } from 'react'
import { X } from 'lucide-react'
import { toast } from 'sonner'
import type { BreakdownFormData } from '@/lib/monitoring'
import { CAT_LABELS } from './BreakdownCard'
import type { CauseCategory } from '@/lib/supabase'

export function BreakdownModal({ onClose, onCreate, pending }: {
  onClose: () => void
  onCreate: (d: BreakdownFormData) => Promise<void>
  pending: boolean
}) {
  const [cause,    setCause]    = useState('')
  const [cat,      setCat]      = useState<CauseCategory>('mechanical')
  const [action,   setAction]   = useState('')
  const [opName,   setOpName]   = useState('')
  const [techName, setTechName] = useState('')
  const [devices,  setDevices]  = useState('')
  const [started,  setStarted]  = useState(new Date().toISOString().slice(0,16))
  const [ended,    setEnded]    = useState('')

  async function handleSubmit() {
    if (!cause.trim()) { toast.error('Penyebab gangguan wajib diisi'); return }
    const start = new Date(started)
    const end = ended ? new Date(ended) : null
    if (Number.isNaN(start.getTime())) { toast.error('Waktu mulai tidak valid'); return }
    if (end && (Number.isNaN(end.getTime()) || end < start)) {
      toast.error('Waktu selesai harus setelah waktu mulai'); return
    }
    await onCreate({
      event_date:        start.toISOString().slice(0,10),
      cause:             cause.trim(),
      cause_category:    cat,
      outage_start:      start.toISOString(),
      outage_end:        end ? end.toISOString() : null,
      duration_hours:    end ? (end.getTime() - start.getTime()) / 3600000 : null,
      affected_devices:  devices.split(',').map((v) => v.trim()).filter(Boolean),
      corrective_action: action || null,
      operator_name:     opName || null,
      technician_name:   techName || null,
    })
  }

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center p-4 bg-background/80 backdrop-blur-sm">
      <div className="bg-surface border border-border rounded-card w-full max-w-lg shadow-xl">
        <div className="flex items-center justify-between px-5 py-4 border-b border-border">
          <h2 className="text-sm font-semibold text-text-primary">Buat Laporan Gangguan</h2>
          <button type="button" aria-label="Tutup" onClick={onClose} className="text-text-secondary hover:text-text-primary">
            <X className="w-4 h-4" />
          </button>
        </div>
        <div className="p-5 space-y-4">
          <Fld label="Penyebab Gangguan *">
            <input value={cause} onChange={(e) => setCause(e.target.value)}
              placeholder="Contoh: Kabel sensor putus akibat banjir" className="scada-input" />
          </Fld>
          <div className="grid grid-cols-2 gap-3">
            <Fld label="Kategori Penyebab">
              <select value={cat} onChange={(e) => setCat(e.target.value as CauseCategory)} className="scada-input">
                {Object.entries(CAT_LABELS).map(([k,v]) => <option key={k} value={k}>{v}</option>)}
              </select>
            </Fld>
            <Fld label="Waktu Mulai Gangguan">
              <input type="datetime-local" value={started}
                onChange={(e) => setStarted(e.target.value)} className="scada-input" />
            </Fld>
          </div>
          <Fld label="Waktu Selesai (opsional)">
            <input type="datetime-local" value={ended}
              onChange={(e) => setEnded(e.target.value)} className="scada-input" />
          </Fld>
          <Fld label="Tindakan Korektif">
            <textarea value={action} onChange={(e) => setAction(e.target.value)}
              rows={2} placeholder="Langkah perbaikan yang dilakukan..."
              className="scada-input resize-none" />
          </Fld>
          <div className="grid grid-cols-2 gap-3">
            <Fld label="Nama Operator">
              <input value={opName} onChange={(e) => setOpName(e.target.value)}
                placeholder="Nama petugas lapangan" className="scada-input" />
            </Fld>
            <Fld label="Nama Teknisi">
              <input value={techName} onChange={(e) => setTechName(e.target.value)}
                placeholder="Teknisi penanganan" className="scada-input" />
            </Fld>
          </div>
          <Fld label="Perangkat Terdampak (pisahkan dengan koma)">
            <input value={devices} onChange={(e) => setDevices(e.target.value)}
              placeholder="Contoh: Radar Flowmeter, Gateway" className="scada-input" />
          </Fld>
        </div>
        <div className="flex justify-end gap-2 px-5 py-4 border-t border-border">
          <button onClick={onClose}
            className="text-sm px-4 py-2 border border-border rounded-input text-text-secondary hover:text-text-primary transition-colors">
            Batal
          </button>
          <button onClick={() => { void handleSubmit() }} disabled={pending}
            className="text-sm px-4 py-2 bg-accent-blue text-white rounded-input font-medium hover:bg-accent-blue/80 transition-colors disabled:opacity-50">
            {pending ? 'Menyimpan…' : 'Buat Laporan'}
          </button>
        </div>
      </div>
    </div>
  )
}

function Fld({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <div className="space-y-1">
      <label className="text-xs text-text-secondary font-medium">{label}</label>
      {children}
    </div>
  )
}
