import type { ReactNode } from 'react'
import { cn } from '@/lib/utils'

interface PageHeaderProps {
  title: string
  subtitle?: string
  actions?: ReactNode
  className?: string
}

export function PageHeader({ title, subtitle, actions, className }: PageHeaderProps) {
  return (
    <header className={cn('sticky top-0 z-10 flex flex-wrap items-start justify-between gap-3 border-b border-border bg-surface/90 py-4 pl-14 pr-4 shadow-sm backdrop-blur-md sm:items-center sm:px-6 lg:px-8 lg:pl-8', className)}>
      <div className="min-w-0">
        <p className="mb-1 flex items-center gap-2 text-[10px] font-semibold uppercase tracking-[0.18em] text-accent-blue"><span className="h-1.5 w-1.5 rounded-full bg-accent-blue shadow-[0_0_0_3px_hsl(var(--accent-blue)/0.15)]" />River Flow Guardian</p>
        <h1 className="text-xl font-bold tracking-tight text-text-primary sm:text-2xl">{title}</h1>
        {subtitle && <p className="mt-1 text-xs text-text-secondary">{subtitle}</p>}
      </div>
      {actions && <div className="flex w-full flex-wrap items-center justify-end gap-2 sm:w-auto">{actions}</div>}
    </header>
  )
}
