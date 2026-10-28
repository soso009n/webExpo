import { useState } from 'react'
import { Check } from 'lucide-react'
import { toast } from 'sonner'
import { cn } from '@/lib/utils'
import { supabase } from '@/lib/supabase'
import { Section, Field, SaveBtn, PwInput } from './atoms'

export function PasswordTab() {
  const [current, setCurrent] = useState('')
  const [next,    setNext]    = useState('')
  const [confirm, setConfirm] = useState('')
  const [showCur, setShowCur] = useState(false)
  const [showNew, setShowNew] = useState(false)
  const [saving, setSaving]   = useState(false)

  const strength =
    next.length === 0 ? 0
    : next.length < 6 ? 1
    : next.length < 10 ? 2
    : /[A-Z]/.test(next) && /[0-9]/.test(next) ? 4
    : 3

  const strLabels = ['','Lemah','Sedang','Kuat','Sangat Kuat']
  const strText   = ['','text-status-bad','text-accent-yellow','text-accent-blue','text-status-good']
  const strBar    = ['','bg-status-bad','bg-accent-yellow','bg-accent-blue','bg-status-good']

  async function handleChange() {
    if (!current) { toast.error('Masukkan password saat ini'); return }
    if (next.length < 8) { toast.error('Password baru minimal 8 karakter'); return }
    if (!/[A-Za-z]/.test(next) || !/\d/.test(next)) { toast.error('Password harus mengandung huruf dan angka'); return }
    if (next !== confirm) { toast.error('Konfirmasi password tidak cocok'); return }
    setSaving(true)
    const { error } = await supabase.auth.updateUser({ password: next })
    setSaving(false)
    if (error) toast.error(error.message)
    else { toast.success('Password berhasil diubah'); setCurrent(''); setNext(''); setConfirm('') }
  }

  return (
    <div className="max-w-lg space-y-6">
      <Section title="Ganti Kata Sandi">
        <p className="text-xs text-text-secondary">Gunakan minimal 8 karakter dengan kombinasi huruf dan angka. Setelah berhasil, gunakan password baru pada login berikutnya.</p>
        <Field label="Password Saat Ini">
          <PwInput value={current} onChange={setCurrent} show={showCur} onToggle={() => setShowCur((s) => !s)} />
        </Field>

        <Field label="Password Baru">
          <PwInput value={next} onChange={setNext} show={showNew} onToggle={() => setShowNew((s) => !s)} />
          {next.length > 0 && (
            <div className="mt-1.5 space-y-1">
              <div className="flex gap-1">
                {[1,2,3,4].map((s) => (
                  <div key={s}
                    className={cn('h-1 flex-1 rounded-full transition-colors',
                      strength >= s ? strBar[strength] : 'bg-surface-2')} />
                ))}
              </div>
              <p className={cn('text-[10px]', strText[strength])}>
                Kekuatan: {strLabels[strength]}
              </p>
            </div>
          )}
        </Field>

        <Field label="Konfirmasi Password Baru">
          <input type={showNew ? 'text' : 'password'} value={confirm}
            onChange={(e) => setConfirm(e.target.value)}
            className={cn('scada-input', confirm && next !== confirm ? 'border-status-bad focus:border-status-bad' : '')}
            placeholder="Ulangi password baru" />
          {confirm && next === confirm && (
            <p className="text-[10px] text-status-good mt-1 flex items-center gap-1">
              <Check className="w-3 h-3" /> Password cocok
            </p>
          )}
          {confirm && next !== confirm && confirm.length > 0 && (
            <p className="text-[10px] text-status-bad mt-1">Password tidak cocok</p>
          )}
        </Field>

        <SaveBtn saving={saving} label="Ubah Password" onClick={() => { void handleChange() }} />
      </Section>
    </div>
  )
}
