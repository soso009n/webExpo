import { cn } from '@/lib/utils'
import { Save, Eye, EyeOff } from 'lucide-react'

export function Section({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <div className="bg-surface border border-border rounded-card p-5 space-y-4">
      <h3 className="text-sm font-semibold text-text-primary border-b border-border pb-2">{title}</h3>
      {children}
    </div>
  )
}

export function Field({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <div className="space-y-1">
      <label className="block text-xs text-text-secondary font-medium">{label}</label>
      {children}
    </div>
  )
}

export function InfoRow({ label, value, valueClass }: { label: string; value: string; valueClass?: string }) {
  return (
    <div className="flex justify-between items-center py-2 border-b border-border last:border-0">
      <span className="text-xs text-text-secondary">{label}</span>
      <span className={cn('text-xs text-text-primary font-medium', valueClass)}>{value}</span>
    </div>
  )
}

export function SaveBtn({ saving, label = 'Simpan Perubahan', onClick }: {
  saving: boolean; label?: string; onClick: () => void
}) {
  return (
    <button type="button" onClick={onClick} disabled={saving}
      className="flex items-center gap-2 px-4 py-2 bg-accent-blue text-white text-sm rounded-input font-medium hover:bg-accent-blue/80 transition-colors disabled:opacity-50">
      <Save className="w-3.5 h-3.5" />
      {saving ? 'Menyimpan…' : label}
    </button>
  )
}

export function Toggle({ value, onToggle }: { value: boolean; onToggle: () => void }) {
  return (
    <button type="button" role="switch" aria-checked={value} aria-label="Toggle pengaturan" onClick={onToggle}
      className={cn('w-9 h-5 rounded-full transition-colors relative flex-shrink-0 ml-4',
        value ? 'bg-accent-blue' : 'bg-surface-2 border border-border')}>
      <span className={cn('absolute top-0.5 w-4 h-4 bg-white rounded-full shadow transition-all duration-200',
        value ? 'left-4' : 'left-0.5')} />
    </button>
  )
}

export function PwInput({ value, onChange, show, onToggle }: {
  value: string; onChange: (v: string) => void; show: boolean; onToggle: () => void
}) {
  return (
    <div className="relative">
      <input type={show ? 'text' : 'password'} value={value}
        onChange={(e) => onChange(e.target.value)}
        className="scada-input pr-9" placeholder="••••••••" />
      <button type="button" aria-label={show ? 'Sembunyikan password' : 'Tampilkan password'} onClick={onToggle}
        className="absolute right-2.5 top-1/2 -translate-y-1/2 text-text-secondary hover:text-text-primary">
        {show ? <EyeOff className="w-3.5 h-3.5" /> : <Eye className="w-3.5 h-3.5" />}
      </button>
    </div>
  )
}
