import { AlertTriangle, Inbox, RefreshCw } from 'lucide-react'

export function LoadingState({ label = 'Memuat data…' }: { label?: string }) {
  return (
    <div className="flex min-h-40 items-center justify-center gap-2 text-sm text-text-secondary" role="status">
      <RefreshCw className="h-4 w-4 animate-spin" aria-hidden="true" />
      {label}
    </div>
  )
}

export function EmptyState({ title = 'Belum ada data', description }: { title?: string; description?: string }) {
  return (
    <div className="flex min-h-40 flex-col items-center justify-center text-center text-text-secondary" role="status">
      <Inbox className="mb-2 h-8 w-8 opacity-40" aria-hidden="true" />
      <p className="text-sm font-medium text-text-primary">{title}</p>
      {description && <p className="mt-1 max-w-sm text-xs">{description}</p>}
    </div>
  )
}

export function ErrorState({ message = 'Data belum dapat dimuat.', onRetry }: { message?: string; onRetry?: () => void }) {
  return (
    <div className="flex min-h-40 flex-col items-center justify-center text-center" role="alert">
      <AlertTriangle className="mb-2 h-8 w-8 text-accent-orange" aria-hidden="true" />
      <p className="text-sm font-medium text-text-primary">Terjadi kendala</p>
      <p className="mt-1 max-w-md text-xs text-text-secondary">{message}</p>
      {onRetry && <button type="button" onClick={onRetry} className="mt-3 scada-button-secondary">Coba lagi</button>}
    </div>
  )
}