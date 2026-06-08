import { useEffect, useMemo, useState, type ChangeEvent, type DragEvent } from 'react'
import { Link, useNavigate } from 'react-router-dom'
import { httpsCallable } from 'firebase/functions'
import type { PDFPageProxy } from 'pdfjs-dist'
import {
  Bell,
  CheckCircle2,
  Copy,
  Download,
  Filter,
  Mail,
  MessageSquareText,
  Phone,
  Search,
  Send,
  Save,
  ShieldCheck,
  Sparkles,
  Star,
  TicketCheck,
  UploadCloud,
  UserCheck,
  Users,
  WalletCards,
  X,
  type LucideIcon,
} from 'lucide-react'

import { functions } from '../firebaseFunctions'
import { copy } from '../lib/copy'
import { formatDateTime, formatMoney } from '../lib/formatters'
import { getErrorMessage } from '../lib/errorMessages'
import { listOrganizerContacts } from '../lib/portalData'
import { usePortalSession } from '../lib/portalSession'
import type { PortalContact } from '../lib/types'
import {
  createAudienceImportPreviewFromRows,
  parseAudienceTextImport,
  type AudienceImportMapping,
  type AudienceImportPreview,
} from '../lib/contactImport'

const importAudienceContacts = httpsCallable<
  {
    organizationId: string
    sourceName?: string
    contacts: Array<{
      displayName?: string
      email?: string
      phone?: string
      marketingConsent: boolean
      smsConsent?: boolean
      tags?: string[]
    }>
    duplicateMode?: 'merge' | 'update' | 'skip'
  },
  {
    importedCount: number
    skippedCount: number
    pushMatchedCount: number
    smsEligibleCount: number
  }
>(functions, 'importAudienceContacts')

const saveCrmContact = httpsCallable<
  {
    organizationId: string
    displayName?: string
    email?: string
    phone?: string
    userId?: string
    marketingConsent: boolean
    smsConsent: boolean
    tags?: string[]
    notes?: string
    sourceName?: string
  },
  { success: boolean; contactId: string }
>(functions, 'saveCrmContact')

type SegmentKey =
  | 'all'
  | 'buyers'
  | 'rsvps'
  | 'uploaded'
  | 'vip'
  | 'reachable'
  | 'sms'
  | 'quiet'

const segmentLabels: Record<SegmentKey, string> = {
  all: 'All',
  buyers: 'Buyers',
  rsvps: 'RSVPs',
  uploaded: 'Imported',
  vip: 'VIP',
  reachable: 'Marketable',
  sms: 'SMS-ready',
  quiet: 'No consent',
}

function contactKey(contact: PortalContact) {
  return contact.email || contact.phone || contact.userId || contact.displayName
}

function escapeCsv(value: string | number | boolean | undefined) {
  let text = String(value ?? '')
  // Neutralise CSV/Excel formula injection (=, +, -, @, tab, CR).
  if (/^[=+\-@\t\r]/.test(text)) text = `'${text}`
  return `"${text.replace(/"/g, '""')}"`
}

function downloadContactsCsv(contacts: PortalContact[], filename: string) {
  const headers = [
    'Name',
    'Email',
    'Phone',
    'Sources',
    'Orders',
    'RSVPs',
    'Lifetime spend',
    'Marketing consent',
    'SMS consent',
    'Last activity',
    'Last event',
  ]
  const rows = contacts.map((contact) => [
    contact.displayName,
    contact.email,
    contact.phone,
    contact.sources.join('|'),
    contact.orderCount,
    contact.rsvpCount,
    contact.totalSpent,
    contact.marketingConsent,
    contact.smsConsent,
    contact.lastActivityAt,
    contact.lastEventTitle,
  ])
  const csv = [headers, ...rows].map((row) => row.map(escapeCsv).join(',')).join('\n')
  const blob = new Blob([csv], { type: 'text/csv;charset=utf-8' })
  const url = URL.createObjectURL(blob)
  const anchor = document.createElement('a')
  anchor.href = url
  anchor.download = filename
  anchor.click()
  URL.revokeObjectURL(url)
}

function downloadContactImportTemplate() {
  const headers = ['Name', 'Email', 'Phone', 'Marketing consent', 'SMS consent']
  const examples = [
    ['Ama Mensah', 'ama@example.com', '+233241234567', 'yes', 'yes'],
    ['Kojo Boateng', 'kojo@example.com', '+233501112222', 'no', 'no'],
  ]
  const csv = [headers, ...examples].map((row) => row.map(escapeCsv).join(',')).join('\n')
  const blob = new Blob([csv], { type: 'text/csv;charset=utf-8' })
  const url = URL.createObjectURL(blob)
  const anchor = document.createElement('a')
  anchor.href = url
  anchor.download = 'vennuzo-contact-import-template.csv'
  anchor.click()
  URL.revokeObjectURL(url)
}

async function extractPdfText(file: File, onProgress?: (status: string) => void) {
  const [{ getDocument, GlobalWorkerOptions }, { default: pdfWorkerUrl }] = await Promise.all([
    import('pdfjs-dist'),
    import('pdfjs-dist/build/pdf.worker.mjs?url'),
  ])
  GlobalWorkerOptions.workerSrc = pdfWorkerUrl
  const loadingTask = getDocument({ data: await file.arrayBuffer() })
  const pdf = await loadingTask.promise
  const pageTexts: string[] = []
  try {
    for (let pageNumber = 1; pageNumber <= pdf.numPages; pageNumber += 1) {
      onProgress?.(`Reading PDF page ${pageNumber} of ${pdf.numPages}...`)
      const page = await pdf.getPage(pageNumber)
      const content = await page.getTextContent()
      const text = content.items
        .map((item) => ('str' in item ? item.str : ''))
        .filter(Boolean)
        .join('\n')
      pageTexts.push(text.trim() || (await recognizePdfPage(page, pageNumber, onProgress)))
    }
  } finally {
    await loadingTask.destroy()
  }
  return pageTexts.join('\n')
}

async function recognizePdfPage(page: PDFPageProxy, pageNumber?: number, onProgress?: (status: string) => void) {
  onProgress?.(`Running OCR on scanned PDF page ${pageNumber ?? ''}...`.trim())
  const { createWorker } = await import('tesseract.js')
  const viewport = page.getViewport({ scale: 2 })
  const canvas = document.createElement('canvas')
  const canvasContext = canvas.getContext('2d')
  if (!canvasContext) return ''
  canvas.width = Math.ceil(viewport.width)
  canvas.height = Math.ceil(viewport.height)
  await page.render({ canvas, canvasContext, viewport }).promise
  const worker = await createWorker('eng')
  try {
    const result = await worker.recognize(canvas)
    return result.data.text
  } finally {
    await worker.terminate()
  }
}

async function extractContactFileText(file: File, onProgress?: (status: string) => void) {
  const isPdf = file.type === 'application/pdf' || file.name.toLowerCase().endsWith('.pdf')
  if (isPdf) return extractPdfText(file, onProgress)
  return file.text()
}

function parseImportTags(value: string) {
  return value
    .split(/[|,;]/)
    .map((tag) => tag.trim())
    .filter(Boolean)
    .slice(0, 12)
}

async function extractContactRowsFromExcel(file: File) {
  const XLSX = await import('xlsx')
  const workbook = XLSX.read(await file.arrayBuffer(), { type: 'array' })
  const sheetName = workbook.SheetNames[0]
  const sheet = sheetName ? workbook.Sheets[sheetName] : undefined
  if (!sheet) return []
  return XLSX.utils
    .sheet_to_json<unknown[]>(sheet, { header: 1, blankrows: false })
    .map((row) => row.map((cell) => String(cell ?? '').trim()))
    .filter((row) => row.some(Boolean))
}

async function extractContactImportPreview(
  file: File,
  options: { extraTags?: string[]; markAllConsented?: boolean; onProgress?: (status: string) => void },
) {
  const fileName = file.name.toLowerCase()
  const isExcel = /\.(xlsx|xls)$/i.test(fileName)
  if (isExcel) {
    options.onProgress?.('Reading spreadsheet...')
    return createAudienceImportPreviewFromRows(await extractContactRowsFromExcel(file), undefined, options)
  }
  options.onProgress?.(fileName.endsWith('.pdf') ? 'Reading PDF...' : 'Reading file...')
  const text = await extractContactFileText(file, options.onProgress)
  return parseAudienceTextImport(text, options)
}

function getSegment(contact: PortalContact) {
  if (contact.totalSpent >= 500 || contact.orderCount >= 3) return 'VIP'
  if (contact.orderCount > 0) return 'Buyer'
  if (contact.rsvpCount > 0) return 'RSVP'
  return 'Imported'
}

function matchesSegment(contact: PortalContact, segment: SegmentKey) {
  if (segment === 'all') return true
  if (segment === 'buyers') return contact.orderCount > 0
  if (segment === 'rsvps') return contact.rsvpCount > 0
  if (segment === 'uploaded') return contact.sources.includes('uploaded')
  if (segment === 'vip') return contact.totalSpent >= 500 || contact.orderCount >= 3
  if (segment === 'reachable') return contact.marketingConsent && Boolean(contact.email || contact.userId)
  if (segment === 'sms') return contact.smsConsent && Boolean(contact.phone)
  if (segment === 'quiet') return !contact.marketingConsent && !contact.smsConsent
  return true
}

export function ContactsPage() {
  const session = usePortalSession()
  const navigate = useNavigate()
  const { organizationId } = session
  const [contacts, setContacts] = useState<PortalContact[]>([])
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [query, setQuery] = useState('')
  const [segment, setSegment] = useState<SegmentKey>('all')
  const [selectedKeys, setSelectedKeys] = useState<Set<string>>(new Set())
  const [activeContactKey, setActiveContactKey] = useState('')
  const [savingContact, setSavingContact] = useState(false)
  const [campaignHandoffLoading, setCampaignHandoffLoading] = useState(false)
  const [toast, setToast] = useState<string | null>(null)
  const [contactDraft, setContactDraft] = useState({
    displayName: '',
    email: '',
    phone: '',
    tags: '',
    notes: '',
    marketingConsent: false,
    smsConsent: false,
  })
  const [audienceImporting, setAudienceImporting] = useState(false)
  const [audienceImportDragging, setAudienceImportDragging] = useState(false)
  const [audienceImportFileName, setAudienceImportFileName] = useState('')
  const [audienceImportSourceName, setAudienceImportSourceName] = useState('')
  const [audienceImportTags, setAudienceImportTags] = useState('')
  const [audienceImportDuplicateMode, setAudienceImportDuplicateMode] = useState<'merge' | 'update' | 'skip'>('merge')
  const [audienceImportConsentConfirmed, setAudienceImportConsentConfirmed] = useState(false)
  const [audienceImportMarkAllConsented, setAudienceImportMarkAllConsented] = useState(false)
  const [audienceImportStatus, setAudienceImportStatus] = useState('')
  const [audienceImportPreview, setAudienceImportPreview] = useState<AudienceImportPreview | null>(null)
  const [audienceImportResult, setAudienceImportResult] = useState<{
    importedCount: number
    skippedCount: number
    pushMatchedCount: number
    smsEligibleCount: number
  } | null>(null)

  async function refreshContacts() {
    if (!organizationId) return
    setLoading(true)
    setError(null)
    try {
      const next = await listOrganizerContacts(organizationId)
      setContacts(next)
      setSelectedKeys(new Set())
      setActiveContactKey((current) => current || (next[0] ? contactKey(next[0]) : ''))
    } catch (e) {
      setError(getErrorMessage(e, copy.contactsLoadFailed))
    } finally {
      setLoading(false)
    }
  }

  useEffect(() => {
    void refreshContacts()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [organizationId])

  const stats = useMemo(() => {
    const totalOrders = contacts.reduce((sum, contact) => sum + contact.orderCount, 0)
    const totalRsvps = contacts.reduce((sum, contact) => sum + contact.rsvpCount, 0)
    const totalSpent = contacts.reduce((sum, contact) => sum + contact.totalSpent, 0)
    const marketable = contacts.filter((contact) => contact.marketingConsent && (contact.email || contact.userId)).length
    const smsReady = contacts.filter((contact) => contact.smsConsent && contact.phone).length
    const vip = contacts.filter((contact) => contact.totalSpent >= 500 || contact.orderCount >= 3).length
    return { totalOrders, totalRsvps, totalSpent, marketable, smsReady, vip }
  }, [contacts])

  const segmentCounts = useMemo(
    () =>
      (Object.keys(segmentLabels) as SegmentKey[]).reduce(
        (acc, key) => ({
          ...acc,
          [key]: contacts.filter((contact) => matchesSegment(contact, key)).length,
        }),
        {} as Record<SegmentKey, number>,
      ),
    [contacts],
  )

  const filtered = useMemo(() => {
    const q = query.trim().toLowerCase()
    return contacts.filter((contact) => {
      if (!matchesSegment(contact, segment)) return false
      if (!q) return true
      return [
        contact.displayName,
        contact.email,
        contact.phone,
        contact.lastEventTitle,
        contact.sources.join(' '),
        contact.sourceNames.join(' '),
      ]
        .join(' ')
        .toLowerCase()
        .includes(q)
    })
  }, [contacts, query, segment])

  const selectedContacts = useMemo(
    () => contacts.filter((contact) => selectedKeys.has(contactKey(contact))),
    [contacts, selectedKeys],
  )
  const visibleKeys = useMemo(() => filtered.map(contactKey), [filtered])
  const allVisibleSelected =
    visibleKeys.length > 0 && visibleKeys.every((key) => selectedKeys.has(key))

  const activeContact = useMemo(
    () =>
      filtered.find((contact) => contactKey(contact) === activeContactKey) ??
      filtered[0] ??
      contacts[0] ??
      null,
    [activeContactKey, contacts, filtered],
  )

  useEffect(() => {
    if (!activeContact) return
    setContactDraft({
      displayName: activeContact.displayName,
      email: activeContact.email,
      phone: activeContact.phone,
      tags: activeContact.tags.join(', '),
      notes: activeContact.notes,
      marketingConsent: activeContact.marketingConsent,
      smsConsent: activeContact.smsConsent,
    })
  }, [activeContact])

  function toggleSelected(key: string) {
    setSelectedKeys((current) => {
      const next = new Set(current)
      if (next.has(key)) next.delete(key)
      else next.add(key)
      return next
    })
  }

  function toggleVisibleSelection() {
    setSelectedKeys((current) => {
      const next = new Set(current)
      for (const key of visibleKeys) {
        if (allVisibleSelected) next.delete(key)
        else next.add(key)
      }
      return next
    })
  }

  async function copySelectedContacts() {
    const lines = selectedContacts.map((contact) =>
      [contact.displayName, contact.email, contact.phone].filter(Boolean).join(' | '),
    )
    await navigator.clipboard.writeText(lines.join('\n'))
    setToast(`Copied ${selectedContacts.length} contact${selectedContacts.length === 1 ? '' : 's'}.`)
  }

  async function saveActiveContact() {
    if (!organizationId || !activeContact) return
    setSavingContact(true)
    setError(null)
    setToast(null)
    try {
      await saveCrmContact({
        organizationId,
        userId: activeContact.userId,
        displayName: contactDraft.displayName.trim(),
        email: contactDraft.email.trim(),
        phone: contactDraft.phone.trim(),
        marketingConsent: contactDraft.marketingConsent,
        smsConsent: contactDraft.smsConsent,
        tags: contactDraft.tags
          .split(',')
          .map((tag) => tag.trim())
          .filter(Boolean),
        notes: contactDraft.notes.trim(),
        sourceName: 'CRM',
      })
      setToast('Contact saved.')
      await refreshContacts()
    } catch (e: unknown) {
      setError(getErrorMessage(e, 'Could not save contact.'))
    } finally {
      setSavingContact(false)
    }
  }

  async function startSelectedCampaign() {
    if (!organizationId) return
    const marketableContacts = selectedContacts.filter(
      (contact) => contact.marketingConsent && (contact.email || contact.phone || contact.userId),
    )
    if (marketableContacts.length === 0) {
      setError('Select contacts with explicit marketing consent before creating a campaign.')
      return
    }
    setCampaignHandoffLoading(true)
    setError(null)
    setToast(null)
    try {
      const sourceName = `CRM selection ${new Date().toISOString().slice(0, 16).replace('T', ' ')}`
      const result = await importAudienceContacts({
        organizationId,
        sourceName,
        contacts: marketableContacts.map((contact) => ({
          displayName: contact.displayName,
          email: contact.email,
          phone: contact.phone,
          marketingConsent: contact.marketingConsent,
          smsConsent: contact.smsConsent,
        })),
      })
      if (result.data.importedCount === 0) {
        setError('No selected contacts could be prepared for campaign delivery.')
        return
      }
      window.sessionStorage.setItem(
        'vennuzo:crmCampaignHandoff',
        JSON.stringify({
          sourceName,
          count: result.data.importedCount,
          createdAt: new Date().toISOString(),
        }),
      )
      navigate(`/studio/promote?audienceSourceName=${encodeURIComponent(sourceName)}&audience=crm`)
    } catch (e: unknown) {
      setError(getErrorMessage(e, 'Could not prepare the selected contacts for a campaign.'))
    } finally {
      setCampaignHandoffLoading(false)
    }
  }

  async function prepareAudienceImportFile(file: File) {
    if (!file || !organizationId) return
    setError(null)
    setAudienceImportResult(null)
    setAudienceImportPreview(null)
    setAudienceImportStatus('Preparing import...')
    try {
      const parsed = await extractContactImportPreview(file, {
        extraTags: parseImportTags(audienceImportTags),
        markAllConsented: audienceImportMarkAllConsented,
        onProgress: setAudienceImportStatus,
      })
      if (parsed.contacts.length === 0) {
        setError('No usable contacts were found. Use columns like name, email, phone, consent, or smsConsent.')
        return
      }
      setAudienceImportPreview(parsed)
      setAudienceImportFileName(file.name)
      setAudienceImportSourceName(file.name.replace(/\.[^/.]+$/, '') || file.name)
      setToast(`Prepared ${parsed.contacts.length} contact${parsed.contacts.length === 1 ? '' : 's'} from ${file.name}.`)
    } catch (e: unknown) {
      setError(getErrorMessage(e, 'Contact import failed. Check the file and try again.'))
    } finally {
      setAudienceImportStatus('')
    }
  }

  function updateAudienceImportMapping(field: keyof AudienceImportMapping, value: number) {
    setAudienceImportPreview((current) =>
      current
        ? createAudienceImportPreviewFromRows(
            current.rows,
            { ...current.mapping, [field]: value },
            {
              extraTags: parseImportTags(audienceImportTags),
              markAllConsented: audienceImportMarkAllConsented,
            },
          )
        : current,
    )
  }

  function rebuildAudienceImportPreviewFromOptions(next?: { tags?: string; markAllConsented?: boolean }) {
    setAudienceImportPreview((current) =>
      current
        ? createAudienceImportPreviewFromRows(current.rows, current.mapping, {
            extraTags: parseImportTags(next?.tags ?? audienceImportTags),
            markAllConsented: next?.markAllConsented ?? audienceImportMarkAllConsented,
          })
        : current,
    )
  }

  async function handleAudienceUpload(event: ChangeEvent<HTMLInputElement>) {
    const file = event.target.files?.[0]
    event.target.value = ''
    if (!file) return
    await prepareAudienceImportFile(file)
  }

  async function handleAudienceDrop(event: DragEvent<HTMLLabelElement>) {
    event.preventDefault()
    setAudienceImportDragging(false)
    const file = event.dataTransfer.files?.[0]
    if (!file) return
    await prepareAudienceImportFile(file)
  }

  async function confirmAudienceImport() {
    if (!organizationId || !audienceImportPreview) return
    setError(null)
    setToast(null)
    setAudienceImportResult(null)
    setAudienceImporting(true)
    try {
      if (!audienceImportConsentConfirmed) {
        setError('Confirm that the imported contacts gave marketing/SMS consent before importing.')
        return
      }
      const result = await importAudienceContacts({
        organizationId,
        sourceName: audienceImportSourceName.trim() || audienceImportFileName || 'Uploaded contact file',
        duplicateMode: audienceImportDuplicateMode,
        contacts: audienceImportPreview.contacts,
      })
      setAudienceImportResult(result.data)
      setAudienceImportPreview(null)
      setAudienceImportFileName('')
      setAudienceImportSourceName('')
      await refreshContacts()
    } catch (e: unknown) {
      setError(getErrorMessage(e, 'Contact import failed. Check the file and try again.'))
    } finally {
      setAudienceImporting(false)
    }
  }

  function clearAudienceImportPreview() {
    setAudienceImportPreview(null)
    setAudienceImportFileName('')
    setAudienceImportSourceName('')
    setAudienceImportConsentConfirmed(false)
    setAudienceImportResult(null)
  }

  if (loading && contacts.length === 0) {
    return <div className="page-loader">{copy.loading}</div>
  }

  return (
    <div className="crm-shell">
      <section className="crm-command-band">
        <div className="crm-command-band__title">
          <p className="eyebrow">CRM</p>
          <h2>Contacts</h2>
          <span>{contacts.length} people across ticket sales, RSVPs, and imported lists</span>
        </div>
        <div className="crm-command-band__actions">
          <label className="button button--secondary crm-file-button">
            <UploadCloud size={16} aria-hidden />
            Upload file
            <input
              type="file"
              accept=".csv,.tsv,.txt,.pdf,.xlsx,.xls,text/csv,text/tab-separated-values,text/plain,application/pdf"
              disabled={audienceImporting}
              onChange={(event) => void handleAudienceUpload(event)}
            />
          </label>
          <button className="button button--secondary" type="button" onClick={downloadContactImportTemplate}>
            <Download size={16} aria-hidden />
            Template
          </button>
          <button
            className="button button--secondary"
            type="button"
            onClick={() => {
              downloadContactsCsv(filtered, 'vennuzo-contacts.csv')
              setToast(`Exported ${filtered.length} contact${filtered.length === 1 ? '' : 's'}.`)
            }}
            disabled={filtered.length === 0}
          >
            <Download size={16} aria-hidden />
            Export
          </button>
          <Link className="button" to="/studio/promote">
            <Send size={16} aria-hidden />
            Promote
          </Link>
        </div>
      </section>

      <section className="crm-import-panel">
        <div className="crm-import-panel__copy">
          <p className="eyebrow">Contact file import</p>
          <h3>Upload a contact list</h3>
          <p>
            Drop in CSV, TSV, TXT, PDF, or Excel files with name, email, phone, marketing consent, and SMS consent.
          </p>
        </div>
        <label
          className={`crm-import-dropzone${audienceImportDragging ? ' crm-import-dropzone--dragging' : ''}`}
          onDragEnter={() => setAudienceImportDragging(true)}
          onDragLeave={() => setAudienceImportDragging(false)}
          onDragOver={(event) => event.preventDefault()}
          onDrop={(event) => void handleAudienceDrop(event)}
        >
          <UploadCloud size={24} aria-hidden />
          <strong>{audienceImportFileName || 'Choose a file or drop it here'}</strong>
          <span>Supports CSV, TSV, TXT, PDF, XLS, and XLSX. Up to 500 contacts per upload.</span>
          <input
            type="file"
            accept=".csv,.tsv,.txt,.pdf,.xlsx,.xls,text/csv,text/tab-separated-values,text/plain,application/pdf"
            disabled={audienceImporting}
            onChange={(event) => void handleAudienceUpload(event)}
          />
        </label>

        {audienceImportPreview ? (
          <div className="crm-import-preview">
            <div className="crm-import-preview__header">
              <div>
                <strong>{audienceImportPreview.contacts.length} contacts ready</strong>
                <span>
                  {audienceImportPreview.invalidCount} missing email or phone, {audienceImportPreview.duplicateCount} duplicates removed
                  {audienceImportPreview.clippedCount ? `, ${audienceImportPreview.clippedCount} over the 500-contact limit` : ''}
                </span>
              </div>
              <input
                aria-label="Import source name"
                value={audienceImportSourceName}
                onChange={(event) => setAudienceImportSourceName(event.target.value)}
                placeholder="Source name"
              />
            </div>
            <div className="crm-import-mapping">
              <ImportMappingSelect label="Name" value={audienceImportPreview.mapping.displayName} labels={audienceImportPreview.fieldLabels} onChange={(value) => updateAudienceImportMapping('displayName', value)} />
              <ImportMappingSelect label="Email" value={audienceImportPreview.mapping.email} labels={audienceImportPreview.fieldLabels} onChange={(value) => updateAudienceImportMapping('email', value)} />
              <ImportMappingSelect label="Phone" value={audienceImportPreview.mapping.phone} labels={audienceImportPreview.fieldLabels} onChange={(value) => updateAudienceImportMapping('phone', value)} />
              <ImportMappingSelect label="Consent" value={audienceImportPreview.mapping.marketingConsent} labels={audienceImportPreview.fieldLabels} onChange={(value) => updateAudienceImportMapping('marketingConsent', value)} />
              <ImportMappingSelect label="SMS" value={audienceImportPreview.mapping.smsConsent} labels={audienceImportPreview.fieldLabels} onChange={(value) => updateAudienceImportMapping('smsConsent', value)} />
              <ImportMappingSelect label="Tags" value={audienceImportPreview.mapping.tags} labels={audienceImportPreview.fieldLabels} onChange={(value) => updateAudienceImportMapping('tags', value)} />
            </div>
            <div className="crm-import-options">
              <label>
                <span>List tags</span>
                <input
                  value={audienceImportTags}
                  onChange={(event) => {
                    setAudienceImportTags(event.target.value)
                    rebuildAudienceImportPreviewFromOptions({ tags: event.target.value })
                  }}
                  placeholder="VIP, sponsors, December leads"
                />
              </label>
              <label>
                <span>Duplicates</span>
                <select
                  value={audienceImportDuplicateMode}
                  onChange={(event) => setAudienceImportDuplicateMode(event.target.value as 'merge' | 'update' | 'skip')}
                >
                  <option value="merge">Merge tags and source</option>
                  <option value="update">Update existing contact</option>
                  <option value="skip">Skip existing contact</option>
                </select>
              </label>
              <label className="checkbox crm-import-option-check">
                <input
                  checked={audienceImportMarkAllConsented}
                  type="checkbox"
                  onChange={(event) => {
                    setAudienceImportMarkAllConsented(event.target.checked)
                    rebuildAudienceImportPreviewFromOptions({ markAllConsented: event.target.checked })
                  }}
                />
                <span>Mark all rows as consented</span>
              </label>
            </div>
            <div className="crm-import-preview__sample" aria-label="Import preview">
              {audienceImportPreview.contacts.slice(0, 4).map((contact, index) => (
                <span key={`${contact.email || contact.phone}-${index}`}>
                  <strong>{contact.displayName || contact.email || contact.phone}</strong>
                  <small>{[contact.email, contact.phone, contact.marketingConsent ? 'consented' : 'no marketing consent'].filter(Boolean).join(' / ')}</small>
                </span>
              ))}
            </div>
            {audienceImportPreview.invalidSamples.length ? (
              <div className="crm-import-warning">
                <strong>Needs review</strong>
                <span>{audienceImportPreview.invalidSamples.join(' · ')}</span>
              </div>
            ) : null}
            <label className="checkbox crm-import-consent">
              <input
                checked={audienceImportConsentConfirmed}
                type="checkbox"
                onChange={(event) => setAudienceImportConsentConfirmed(event.target.checked)}
              />
              <span>I confirm these contacts gave consent for the selected marketing/SMS channels.</span>
            </label>
            <div className="crm-import-preview__actions">
              <button
                className="button"
                type="button"
                disabled={audienceImporting || !audienceImportConsentConfirmed}
                onClick={() => void confirmAudienceImport()}
              >
                <UploadCloud size={16} aria-hidden />
                {audienceImporting ? 'Importing...' : 'Import contacts'}
              </button>
              <button className="button button--ghost" type="button" disabled={audienceImporting} onClick={clearAudienceImportPreview}>
                Clear
              </button>
            </div>
          </div>
        ) : (
          <div className="crm-import-hints">
            <span>Name, Email, Phone, Marketing consent, SMS consent</span>
            <button className="button button--ghost" type="button" onClick={downloadContactImportTemplate}>
              <Download size={16} aria-hidden />
              Download template
            </button>
            {audienceImportStatus ? <small>{audienceImportStatus}</small> : null}
          </div>
        )}
      </section>

      {error ? (
        <div className="crm-alert crm-alert--error">
          <X size={16} aria-hidden />
          <span>{error}</span>
        </div>
      ) : null}

      {audienceImportResult ? (
        <div className="crm-alert">
          <CheckCircle2 size={16} aria-hidden />
          <span>
            Imported {audienceImportResult.importedCount}. SMS-ready {audienceImportResult.smsEligibleCount}.
            Push-matched {audienceImportResult.pushMatchedCount}. Skipped {audienceImportResult.skippedCount}.
          </span>
        </div>
      ) : null}

      {toast ? (
        <div className="crm-alert">
          <CheckCircle2 size={16} aria-hidden />
          <span>{toast}</span>
        </div>
      ) : null}

      <section className="stats-grid stats-grid--compact">
        <MetricCard icon={Users} label="Contacts" value={String(contacts.length)} />
        <MetricCard icon={WalletCards} label="Lifetime" value={formatMoney(stats.totalSpent)} />
        <MetricCard icon={Mail} label="Marketable" value={String(stats.marketable)} />
        <MetricCard icon={Phone} label="SMS-ready" value={String(stats.smsReady)} />
        <MetricCard icon={Star} label="VIP" value={String(stats.vip)} />
      </section>

      <section className="crm-workspace">
        <aside className="crm-segment-rail" aria-label="Contact segments">
          <div className="crm-segment-rail__header">
            <Filter size={16} aria-hidden />
            <strong>Segments</strong>
          </div>
          {(Object.keys(segmentLabels) as SegmentKey[]).map((key) => (
            <button
              className={`crm-segment-button${segment === key ? ' crm-segment-button--active' : ''}`}
              key={key}
              type="button"
              onClick={() => setSegment(key)}
            >
              <span>{segmentLabels[key]}</span>
              <strong>{segmentCounts[key] ?? 0}</strong>
            </button>
          ))}
        </aside>

        <article className="crm-list-panel">
          <div className="crm-toolbar">
            <label className="crm-search">
              <Search size={16} aria-hidden />
              <input
                onChange={(event) => setQuery(event.target.value)}
                placeholder="Search name, email, phone, event, or source"
                value={query}
              />
            </label>
            <button className="button button--ghost" type="button" onClick={toggleVisibleSelection}>
              <CheckCircle2 size={16} aria-hidden />
              {allVisibleSelected ? 'Clear visible' : 'Select visible'}
            </button>
          </div>

          {selectedContacts.length ? (
            <div className="crm-selection-bar">
              <strong>{selectedContacts.length} selected</strong>
              <button className="button button--secondary" type="button" onClick={() => void copySelectedContacts()}>
                <Copy size={16} aria-hidden />
                Copy
              </button>
              <button
                className="button button--secondary"
                type="button"
                onClick={() => {
                  downloadContactsCsv(selectedContacts, 'vennuzo-selected-contacts.csv')
                  setToast(`Exported ${selectedContacts.length} selected contact${selectedContacts.length === 1 ? '' : 's'}.`)
                }}
              >
                <Download size={16} aria-hidden />
                Export
              </button>
              <button
                className="button button--secondary"
                disabled={campaignHandoffLoading}
                onClick={() => void startSelectedCampaign()}
                type="button"
              >
                <MessageSquareText size={16} aria-hidden />
                {campaignHandoffLoading ? 'Preparing...' : 'Campaign'}
              </button>
            </div>
          ) : null}

          <div className="crm-table" role="table">
            <div className="crm-table__head" role="row">
              <span>Contact</span>
              <span>Segment</span>
              <span>Reach</span>
              <span>Value</span>
              <span>Last touch</span>
            </div>
            {filtered.length === 0 ? (
              <div className="empty-card crm-empty">
                <h4>No matching contacts</h4>
                <p>Try another segment, search term, or import a CSV list.</p>
              </div>
            ) : (
              filtered.map((contact) => {
                const key = contactKey(contact)
                const selected = selectedKeys.has(key)
                const active = activeContact ? contactKey(activeContact) === key : false
                return (
                  <div
                    className={`crm-contact-row${active ? ' crm-contact-row--active' : ''}`}
                    key={key}
                    onClick={() => setActiveContactKey(key)}
                    onKeyDown={(event) => {
                      if (event.key === 'Enter' || event.key === ' ') {
                        event.preventDefault()
                        setActiveContactKey(key)
                      }
                    }}
                    role="row"
                    tabIndex={0}
                  >
                    <span className="crm-contact-row__person">
                      <input
                        aria-label={`Select ${contact.displayName || contact.email || contact.phone}`}
                        checked={selected}
                        onChange={() => toggleSelected(key)}
                        onClick={(event) => event.stopPropagation()}
                        type="checkbox"
                      />
                      <span className="contact-avatar" aria-hidden>
                        {(contact.displayName || contact.email || contact.phone).trim().slice(0, 1).toUpperCase() || 'V'}
                      </span>
                      <span>
                        <strong>{contact.displayName || contact.email || contact.phone || 'Unknown contact'}</strong>
                        <small>{contact.email || contact.phone || 'No direct channel'}</small>
                      </span>
                    </span>
                    <span>
                      <span className={`crm-chip crm-chip--${getSegment(contact).toLowerCase()}`}>{getSegment(contact)}</span>
                    </span>
                    <span className="crm-reach-icons">
                      <ReachIcon active={Boolean(contact.email || contact.userId)} icon={Mail} label="Email or push" />
                      <ReachIcon active={Boolean(contact.phone && contact.smsConsent)} icon={Phone} label="SMS" />
                      <ReachIcon active={contact.marketingConsent} icon={ShieldCheck} label="Consent" />
                    </span>
                    <span className="crm-value-cell">
                      <strong>{formatMoney(contact.totalSpent)}</strong>
                      <small>{contact.orderCount} orders / {contact.rsvpCount} RSVPs</small>
                    </span>
                    <span className="crm-last-touch">
                      <strong>{contact.lastEventTitle || 'Imported list'}</strong>
                      <small>{formatDateTime(contact.lastActivityAt)}</small>
                    </span>
                  </div>
                )
              })
            )}
          </div>
        </article>

        <aside className="crm-detail-panel">
          {activeContact ? (
            <>
              <div className="crm-detail-panel__identity">
                <span className="contact-avatar contact-avatar--large" aria-hidden>
                  {(activeContact.displayName || activeContact.email || activeContact.phone).trim().slice(0, 1).toUpperCase() || 'V'}
                </span>
                <div>
                  <p className="eyebrow">{getSegment(activeContact)}</p>
                  <h3>{activeContact.displayName || activeContact.email || activeContact.phone || 'Unknown contact'}</h3>
                  <span>{activeContact.email || 'No email'} {activeContact.phone ? `/ ${activeContact.phone}` : ''}</span>
                </div>
              </div>

              <div className="crm-next-action">
                <Sparkles size={16} aria-hidden />
                <div>
                  <strong>{getNextAction(activeContact)}</strong>
                  <span>{getNextActionDetail(activeContact)}</span>
                </div>
              </div>

              <div className="crm-detail-grid">
                <DetailStat label="Spend" value={formatMoney(activeContact.totalSpent)} />
                <DetailStat label="Orders" value={String(activeContact.orderCount)} />
                <DetailStat label="RSVPs" value={String(activeContact.rsvpCount)} />
                <DetailStat label="Sources" value={activeContact.sources.length.toString()} />
              </div>

              <div className="crm-channel-list">
                <ChannelStatus icon={Mail} label="Email or push" active={Boolean(activeContact.email || activeContact.userId)} />
                <ChannelStatus icon={Phone} label="SMS" active={Boolean(activeContact.phone && activeContact.smsConsent)} />
                <ChannelStatus icon={Bell} label="Marketing consent" active={activeContact.marketingConsent} />
                <ChannelStatus icon={UserCheck} label="Matched account" active={Boolean(activeContact.userId)} />
              </div>

              <div className="crm-edit-form">
                <label>
                  <span>Name</span>
                  <input
                    value={contactDraft.displayName}
                    onChange={(event) => setContactDraft((current) => ({ ...current, displayName: event.target.value }))}
                  />
                </label>
                <label>
                  <span>Email</span>
                  <input
                    type="email"
                    value={contactDraft.email}
                    onChange={(event) => setContactDraft((current) => ({ ...current, email: event.target.value }))}
                  />
                </label>
                <label>
                  <span>Phone</span>
                  <input
                    value={contactDraft.phone}
                    onChange={(event) => setContactDraft((current) => ({ ...current, phone: event.target.value }))}
                  />
                </label>
                <label>
                  <span>Tags</span>
                  <input
                    placeholder="VIP, sponsor, table lead"
                    value={contactDraft.tags}
                    onChange={(event) => setContactDraft((current) => ({ ...current, tags: event.target.value }))}
                  />
                </label>
                <label className="crm-edit-form__wide">
                  <span>Notes</span>
                  <textarea
                    rows={3}
                    value={contactDraft.notes}
                    onChange={(event) => setContactDraft((current) => ({ ...current, notes: event.target.value }))}
                  />
                </label>
                <label className="checkbox">
                  <input
                    checked={contactDraft.marketingConsent}
                    type="checkbox"
                    onChange={(event) => setContactDraft((current) => ({ ...current, marketingConsent: event.target.checked }))}
                  />
                  <span>Marketing consent</span>
                </label>
                <label className="checkbox">
                  <input
                    checked={contactDraft.smsConsent}
                    type="checkbox"
                    onChange={(event) => setContactDraft((current) => ({ ...current, smsConsent: event.target.checked }))}
                  />
                  <span>SMS consent</span>
                </label>
                <button
                  className="button button--secondary crm-edit-form__wide"
                  disabled={savingContact}
                  onClick={() => void saveActiveContact()}
                  type="button"
                >
                  <Save size={16} aria-hidden />
                  {savingContact ? 'Saving...' : 'Save contact'}
                </button>
              </div>

              <div className="crm-source-cloud">
                {activeContact.sources.map((source) => (
                  <span className="crm-source-pill" key={source}>{source}</span>
                ))}
                {activeContact.tags.map((tag) => (
                  <span className="crm-source-pill crm-source-pill--soft" key={tag}>{tag}</span>
                ))}
                {activeContact.sourceNames.slice(0, 3).map((source) => (
                  <span className="crm-source-pill crm-source-pill--soft" key={source}>{source}</span>
                ))}
              </div>

              <div className="crm-timeline">
                <div className="crm-timeline__header">
                  <TicketCheck size={16} aria-hidden />
                  <strong>Activity</strong>
                </div>
                {activeContact.events.length === 0 ? (
                  <p className="text-subtle">No activity yet.</p>
                ) : (
                  activeContact.events.map((event) => (
                    <div className="crm-timeline__item" key={event.id}>
                      <span className={`crm-timeline__dot crm-timeline__dot--${event.type}`} />
                      <div>
                        <strong>{event.type === 'order' ? 'Ticket order' : event.type === 'rsvp' ? 'RSVP' : 'List import'}</strong>
                        <span>{event.eventTitle || event.sourceName || 'Imported list'}</span>
                      </div>
                      <small>{event.amount ? formatMoney(event.amount) : formatDateTime(event.occurredAt)}</small>
                    </div>
                  ))
                )}
              </div>
            </>
          ) : (
            <div className="empty-card crm-empty">
              <h4>No contact selected</h4>
              <p>Import contacts or wait for ticket buyers and RSVPs to appear here.</p>
            </div>
          )}
        </aside>
      </section>
    </div>
  )
}

function getNextAction(contact: PortalContact) {
  if (contact.totalSpent >= 500 || contact.orderCount >= 3) return 'Invite to VIP access'
  if (contact.rsvpCount > 0 && contact.orderCount === 0) return 'Convert RSVP to buyer'
  if (contact.smsConsent && contact.phone) return 'Send timed SMS offer'
  if (contact.marketingConsent) return 'Add to next campaign'
  return 'Request opt-in'
}

function getNextActionDetail(contact: PortalContact) {
  if (contact.totalSpent >= 500 || contact.orderCount >= 3) return 'Best fit for tables, early access, and premium drops.'
  if (contact.rsvpCount > 0 && contact.orderCount === 0) return 'Follow up before price changes or capacity updates.'
  if (contact.smsConsent && contact.phone) return 'Use a short message tied to the latest event.'
  if (contact.marketingConsent) return 'Ready for email, push, or audience promotion flows.'
  return 'Keep only operational messages until they consent.'
}

function MetricCard({
  icon: Icon,
  label,
  value,
}: {
  icon: LucideIcon
  label: string
  value: string
}) {
  return (
    <article className="metric-card metric-card--plain metric-card--with-icon">
      <Icon size={18} aria-hidden />
      <span>{label}</span>
      <strong>{value}</strong>
    </article>
  )
}

function ReachIcon({ active, icon: Icon, label }: { active: boolean; icon: LucideIcon; label: string }) {
  return (
    <span className={`crm-reach-icon${active ? ' crm-reach-icon--active' : ''}`} title={label}>
      <Icon size={14} aria-hidden />
    </span>
  )
}

function DetailStat({ label, value }: { label: string; value: string }) {
  return (
    <div className="crm-detail-stat">
      <span>{label}</span>
      <strong>{value}</strong>
    </div>
  )
}

function ImportMappingSelect({
  label,
  labels,
  onChange,
  value,
}: {
  label: string
  labels: string[]
  onChange: (value: number) => void
  value: number
}) {
  return (
    <label>
      <span>{label}</span>
      <select value={value} onChange={(event) => onChange(Number(event.target.value))}>
        <option value={-1}>Ignore</option>
        {labels.map((fieldLabel, index) => (
          <option key={`${fieldLabel}-${index}`} value={index}>
            {fieldLabel}
          </option>
        ))}
      </select>
    </label>
  )
}

function ChannelStatus({
  active,
  icon: Icon,
  label,
}: {
  active: boolean
  icon: LucideIcon
  label: string
}) {
  return (
    <div className="crm-channel-status">
      <Icon size={15} aria-hidden />
      <span>{label}</span>
      <strong>{active ? 'Ready' : 'Missing'}</strong>
    </div>
  )
}
