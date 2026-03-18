export function formatMoney(value: number) {
  return new Intl.NumberFormat('en-GH', {
    style: 'currency',
    currency: 'GHS',
    maximumFractionDigits: 0,
  }).format(value || 0)
}

export function formatDateTime(value: string) {
  if (!value) {
    return 'TBD'
  }

  const date = new Date(value)
  if (Number.isNaN(date.getTime())) {
    return 'TBD'
  }

  return new Intl.DateTimeFormat('en-GH', {
    weekday: 'short',
    month: 'short',
    day: 'numeric',
    hour: 'numeric',
    minute: '2-digit',
  }).format(date)
}

export function titleCaseStatus(value: string) {
  if (value === 'active') {
    return 'Live'
  }
  return value
    .replace(/_/g, ' ')
    .replace(/\b\w/g, (letter) => letter.toUpperCase())
}
