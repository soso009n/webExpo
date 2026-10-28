import { useEffect, useState } from 'react'
import { toast } from 'sonner'
import { useAuth } from '@/lib/auth'
import { Section, Field, InfoRow, SaveBtn } from './atoms'

function normalizePhone(value: string) {
  return value.replace(/[^\d+\s()-]/g, '').slice(0, 24)
}

export function ProfileTab() {
  const { profile, user, updateProfile } = useAuth()
  const [fullName, setFullName] = useState(profile?.full_name ?? '')
  const [phone, setPhone]       = useState(profile?.phone ?? '')
  const [saving, setSaving]     = useState(false)

  useEffect(() => {
    setFullName(profile?.full_name ?? '')
    setPhone(profile?.phone ?? '')
  }, [profile?.full_name, profile?.phone])

  async function handleSave() {
    setSaving(true)
    const cleanName = fullName.trim()
    const cleanPhone = phone.trim()
    if (cleanName.length < 2) { setSaving(false); toast.error('Nama lengkap minimal 2 karakter'); return }
    if (cleanPhone && cleanPhone.replace(/\D/g, '').length < 8) { setSaving(false); toast.error('Nomor telepon tidak valid'); return }
    const { error } = await updateProfile({ full_name: cleanName, phone: cleanPhone || undefined })
    setSaving(false)
    if (error) toast.error(error); else toast.success('Profil berhasil disimpan')
  }

  return (
    <div className="max-w-lg space-y-6">
      <Section title="Informasi Akun">
        <InfoRow label="Email" value={user?.email ?? '—'} />
        <InfoRow label="Role" value={profile?.role ?? '—'} valueClass="capitalize" />
        <InfoRow
          label="Status"
          value={profile?.is_active ? 'Aktif' : 'Non-aktif'}
          valueClass={profile?.is_active ? 'text-status-good' : 'text-status-bad'}
        />
        <InfoRow label="Login Terakhir" value={profile?.last_login
          ? new Date(profile.last_login).toLocaleString('id-ID') : '—'} />
      </Section>
      <Section title="Edit Profil">
        <Field label="Nama Lengkap">
            <input value={fullName} maxLength={80} onChange={(e) => setFullName(e.target.value)}
            placeholder="Masukkan nama lengkap" className="scada-input" />
        </Field>
        <Field label="Nomor Telepon">
            <input value={phone} inputMode="tel" maxLength={24} onChange={(e) => setPhone(normalizePhone(e.target.value))}
            placeholder="+62 8xx-xxxx-xxxx" className="scada-input" />
        </Field>
        <SaveBtn saving={saving} onClick={() => { void handleSave() }} />
      </Section>
    </div>
  )
}
