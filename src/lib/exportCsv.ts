/**
 * Utility: export array-of-objects ke file CSV dan trigger download di browser.
 */
export function exportCsv<T extends Record<string, unknown>>(
  rows: T[],
  filename = 'export.csv',
): void {
  if (rows.length === 0) return
  const headers = Object.keys(rows[0]!)
  const csvLines = [
    headers.join(','),
    ...rows.map((row) =>
      headers.map((h) => {
        const val = row[h]
        if (val === null || val === undefined) return ''
        const str = String(val)
        // escape quotes and wrap if contains comma/newline/quote
        if (str.includes(',') || str.includes('"') || str.includes('\n')) {
          return `"${str.replace(/"/g, '""')}"`
        }
        return str
      }).join(','),
    ),
  ]
  const blob = new Blob([csvLines.join('\n')], { type: 'text/csv;charset=utf-8;' })
  const url  = URL.createObjectURL(blob)
  const link = document.createElement('a')
  link.href     = url
  link.download = filename
  document.body.appendChild(link)
  link.click()
  document.body.removeChild(link)
  URL.revokeObjectURL(url)
}
