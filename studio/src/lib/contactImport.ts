export type AudienceImportContact = {
  displayName?: string
  email?: string
  phone?: string
  marketingConsent: boolean
  smsConsent?: boolean
  tags?: string[]
}

export type AudienceImportField = 'displayName' | 'email' | 'phone' | 'marketingConsent' | 'smsConsent' | 'tags' | 'skip'

export type AudienceImportMapping = {
  displayName: number
  email: number
  phone: number
  marketingConsent: number
  smsConsent: number
  tags: number
}

export type AudienceImportPreview = {
  contacts: AudienceImportContact[]
  rowCount: number
  invalidCount: number
  duplicateCount: number
  clippedCount: number
  invalidSamples: string[]
  fieldLabels: string[]
  mapping: AudienceImportMapping
  rows: string[][]
}

export const emptyImportMapping: AudienceImportMapping = {
  displayName: -1,
  email: -1,
  phone: -1,
  marketingConsent: -1,
  smsConsent: -1,
  tags: -1,
}

export function parseBooleanFlag(value: string | undefined, fallback: boolean) {
  if (value == null || value.trim() === '') return fallback
  return ['yes', 'true', '1', 'y', 'optedin', 'optin', 'subscribed'].includes(
    value.trim().toLowerCase().replace(/[^a-z0-9]/g, ''),
  )
}

function detectDelimiter(input: string) {
  const sampleRows = input
    .split(/\r?\n/)
    .map((line) => line.trim())
    .filter(Boolean)
    .slice(0, 5)
  const candidates = [',', '\t', ';', '|']
  return candidates.reduce((best, candidate) => {
    const bestScore = sampleRows.reduce((sum, row) => sum + row.split(best).length, 0)
    const candidateScore = sampleRows.reduce((sum, row) => sum + row.split(candidate).length, 0)
    return candidateScore > bestScore ? candidate : best
  }, ',')
}

export function parseDelimitedRows(input: string) {
  const rows: string[][] = []
  let row: string[] = []
  let cell = ''
  let quoted = false
  const delimiter = detectDelimiter(input)
  for (let index = 0; index < input.length; index += 1) {
    const char = input[index]
    const next = input[index + 1]
    if (char === '"' && quoted && next === '"') {
      cell += '"'
      index += 1
      continue
    }
    if (char === '"') {
      quoted = !quoted
      continue
    }
    if (char === delimiter && !quoted) {
      row.push(cell.trim())
      cell = ''
      continue
    }
    if ((char === '\n' || char === '\r') && !quoted) {
      if (char === '\r' && next === '\n') index += 1
      row.push(cell.trim())
      if (row.some(Boolean)) rows.push(row)
      row = []
      cell = ''
      continue
    }
    cell += char
  }
  row.push(cell.trim())
  if (row.some(Boolean)) rows.push(row)
  return rows
}

export function normalizeHeader(value: string) {
  return value.trim().toLowerCase().replace(/[^a-z0-9]/g, '')
}

export function cleanImportValue(value: string | undefined) {
  const trimmed = value?.trim()
  return trimmed || undefined
}

export function normalizeImportPhone(value: string | undefined) {
  return cleanImportValue(value)?.replace(/[^\d+]/g, '')
}

export function getImportDedupKey(contact: AudienceImportContact) {
  const email = cleanImportValue(contact.email)?.toLowerCase()
  if (email) return `email:${email}`
  const phone = normalizeImportPhone(contact.phone)
  return phone ? `phone:${phone}` : ''
}

export function normalizeImportTags(value: string | undefined) {
  return (value ?? '')
    .split(/[|,;]/)
    .map((tag) => tag.trim())
    .filter(Boolean)
    .slice(0, 12)
}

function findIndex(header: string[], names: string[]) {
  return header.findIndex((cell) => names.includes(cell))
}

export function inferAudienceImportMapping(fieldLabels: string[]): AudienceImportMapping {
  const header = fieldLabels.map(normalizeHeader)
  return {
    displayName: findIndex(header, ['name', 'fullname', 'displayname', 'contactname']),
    email: findIndex(header, ['email', 'emailaddress']),
    phone: findIndex(header, ['phone', 'phonenumber', 'mobile', 'mobilephone', 'whatsapp']),
    marketingConsent: findIndex(header, ['consent', 'marketingconsent', 'marketingoptin', 'optin']),
    smsConsent: findIndex(header, ['smsconsent', 'smsoptin']),
    tags: findIndex(header, ['tag', 'tags', 'list', 'segment']),
  }
}

function rowValue(row: string[], index: number) {
  return index >= 0 ? row[index] : undefined
}

function isProbablyHeader(row: string[]) {
  const knownHeaders = new Set([
    'name',
    'fullname',
    'displayname',
    'contactname',
    'firstname',
    'lastname',
    'email',
    'emailaddress',
    'phone',
    'phonenumber',
    'mobile',
    'mobilephone',
    'whatsapp',
    'consent',
    'marketingconsent',
    'marketingoptin',
    'optin',
    'smsconsent',
    'smsoptin',
    'tag',
    'tags',
    'list',
    'segment',
  ])
  return row.map(normalizeHeader).some((cell) => knownHeaders.has(cell))
}

export function createAudienceImportPreviewFromRows(
  sourceRows: string[][],
  mapping?: AudienceImportMapping,
  options: { extraTags?: string[]; markAllConsented?: boolean } = {},
): AudienceImportPreview {
  if (sourceRows.length === 0) {
    const emptyLabels: string[] = []
    return {
      contacts: [],
      rowCount: 0,
      invalidCount: 0,
      duplicateCount: 0,
      clippedCount: 0,
      invalidSamples: [],
      fieldLabels: emptyLabels,
      mapping: emptyImportMapping,
      rows: [],
    }
  }
  const hasHeader = isProbablyHeader(sourceRows[0])
  const dataRows = hasHeader ? sourceRows.slice(1) : sourceRows
  const width = Math.max(...sourceRows.map((row) => row.length), 0)
  const fieldLabels = hasHeader
    ? Array.from({ length: width }, (_, index) => sourceRows[0][index] || `Column ${index + 1}`)
    : Array.from({ length: width }, (_, index) => `Column ${index + 1}`)
  const resolvedMapping = mapping ?? (hasHeader ? inferAudienceImportMapping(fieldLabels) : {
    ...emptyImportMapping,
    displayName: 0,
    email: 1,
    phone: 2,
  })
  const contacts: AudienceImportContact[] = []
  const seen = new Set<string>()
  const invalidSamples: string[] = []
  let invalidCount = 0
  let duplicateCount = 0

  dataRows.forEach((row) => {
    const tags = [
      ...normalizeImportTags(rowValue(row, resolvedMapping.tags)),
      ...(options.extraTags ?? []),
    ].filter(Boolean)
    const contact = {
      displayName: cleanImportValue(rowValue(row, resolvedMapping.displayName)),
      email: cleanImportValue(rowValue(row, resolvedMapping.email)),
      phone: cleanImportValue(rowValue(row, resolvedMapping.phone)),
      marketingConsent: options.markAllConsented
        ? true
        : parseBooleanFlag(rowValue(row, resolvedMapping.marketingConsent), false),
      smsConsent: parseBooleanFlag(rowValue(row, resolvedMapping.smsConsent), false),
      tags,
    }
    const key = getImportDedupKey(contact)
    if (!key) {
      invalidCount += 1
      if (invalidSamples.length < 4) invalidSamples.push(row.filter(Boolean).join(' | '))
      return
    }
    if (seen.has(key)) {
      duplicateCount += 1
      return
    }
    seen.add(key)
    contacts.push(contact)
  })

  return {
    contacts: contacts.slice(0, 500),
    rowCount: dataRows.length,
    invalidCount,
    duplicateCount,
    clippedCount: Math.max(contacts.length - 500, 0),
    invalidSamples,
    fieldLabels,
    mapping: resolvedMapping,
    rows: sourceRows,
  }
}

export function parseLooseAudienceContacts(input: string, options: { extraTags?: string[]; markAllConsented?: boolean } = {}) {
  const emailPattern = /[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}/gi
  const phonePattern = /(?:\+?\d[\d\s().-]{7,}\d)/g
  const rows = input
    .split(/\r?\n/)
    .map((line) => {
      const trimmed = line.trim()
      if (!trimmed) return []
      const email = trimmed.match(emailPattern)?.[0] ?? ''
      const phone = trimmed.match(phonePattern)?.[0] ?? ''
      const name = trimmed
        .replace(emailPattern, ' ')
        .replace(phonePattern, ' ')
        .replace(/\b(yes|no|true|false|opted?\s*in|subscribed|marketing|consent|sms)\b/gi, ' ')
        .replace(/[|,;:\t]+/g, ' ')
        .replace(/\s{2,}/g, ' ')
        .trim()
      const consent = /\b(marketing\s*)?(yes|true|opted?\s*in|subscribed)\b/i.test(trimmed) ? 'yes' : ''
      return [name, email, phone, consent, consent]
    })
    .filter((row) => row.length > 0)
  return createAudienceImportPreviewFromRows(
    [['Name', 'Email', 'Phone', 'Marketing consent', 'SMS consent'], ...rows],
    undefined,
    options,
  )
}

export function parseAudienceTextImport(input: string, options: { extraTags?: string[]; markAllConsented?: boolean } = {}) {
  const rows = parseDelimitedRows(input)
  const parsed = createAudienceImportPreviewFromRows(rows, undefined, options)
  return parsed.contacts.length > 0 ? parsed : parseLooseAudienceContacts(input, options)
}
