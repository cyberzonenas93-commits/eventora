import { useEffect, useMemo, useState, type ChangeEvent } from 'react'
import { Link } from 'react-router-dom'
import { httpsCallable } from 'firebase/functions'
import { doc, onSnapshot } from 'firebase/firestore'
import { getDownloadURL, ref, uploadBytes } from 'firebase/storage'
import {
  Download,
  ImagePlus,
  Palette,
  RefreshCw,
  Save,
  Sparkles,
  Wand2,
  X,
} from 'lucide-react'

import { db } from '../firebaseDb'
import { functions } from '../firebaseFunctions'
import { storage } from '../firebaseStorage'
import { formatDateTime, formatMoney } from '../lib/formatters'
import { getErrorMessage } from '../lib/errorMessages'
import { listCreativeSessions } from '../lib/portalData'
import { usePortalSession } from '../lib/portalSession'
import type { CreativeSession } from '../lib/types'

type BrandConfig = {
  brandName: string
  tagline: string
  brandStyle: string
  brandColor: string
  logoUrl: string
  phones: string[]
  instagram: string
  website: string
}

type Tier = {
  name: string
  price: string
  itemsText: string
}

type JobView = {
  jobId: string
  status: string
  currentStep?: string
  progress?: number
  imageUrl?: string
  sessionId?: string
  error?: string
}

const getCreativeServicesConfig = httpsCallable<
  { organizationId?: string },
  {
    organizationId: string
    brand: BrandConfig
    pricing: { flyerGhs: number; tablePackageFlyerGhs: number; includedMinorEdits: number; includedRedesigns: number }
  }
>(functions, 'getCreativeServicesConfig')

const saveCreativeBrandConfig = httpsCallable<
  Partial<BrandConfig> & { organizationId?: string },
  { success: boolean; brand: BrandConfig }
>(functions, 'saveCreativeBrandConfig')

const submitCreativeFlyerJob = httpsCallable<Record<string, unknown>, { jobId: string; priceChargedGhs: number; quotaCovered: boolean }>(
  functions,
  'submitCreativeFlyerJob',
)

function emptyBrand(): BrandConfig {
  return {
    brandName: '',
    tagline: '',
    brandStyle: '',
    brandColor: '#7dd3fc',
    logoUrl: '',
    phones: [],
    instagram: '',
    website: '',
  }
}

function tierPayload(tier: Tier) {
  return {
    name: tier.name.trim(),
    price: tier.price.trim(),
    items: tier.itemsText
      .split(/\n|,/)
      .map((item) => item.trim())
      .filter(Boolean),
  }
}

export function CreativeServicesPage() {
  const session = usePortalSession()
  const { organizationId } = session
  const [brand, setBrand] = useState<BrandConfig>(emptyBrand)
  const [pricing, setPricing] = useState({ flyerGhs: 50, tablePackageFlyerGhs: 50, includedMinorEdits: 10, includedRedesigns: 2 })
  const [sessions, setSessions] = useState<CreativeSession[]>([])
  const [selectedSessionId, setSelectedSessionId] = useState('')
  const [loading, setLoading] = useState(true)
  const [savingBrand, setSavingBrand] = useState(false)
  const [submitting, setSubmitting] = useState(false)
  const [job, setJob] = useState<JobView | null>(null)
  const [error, setError] = useState<string | null>(null)

  const [serviceType, setServiceType] = useState<'event_flyer' | 'table_package_flyer'>('event_flyer')
  const [eventName, setEventName] = useState('')
  const [date, setDate] = useState('')
  const [time, setTime] = useState('')
  const [venue, setVenue] = useState('')
  const [djs, setDjs] = useState('')
  const [creativeDescription, setCreativeDescription] = useState('')
  const [editInstruction, setEditInstruction] = useState('')
  const [uploadedFlyerUrl, setUploadedFlyerUrl] = useState('')
  const [referenceMedia, setReferenceMedia] = useState<{ url: string; name: string }[]>([])
  const [sourceUploading, setSourceUploading] = useState(false)
  const [tiers, setTiers] = useState<Tier[]>([
    { name: 'VIP Table', price: 'GHS 2,500', itemsText: '1 premium bottle\n4 mixers\nPriority entry' },
  ])

  const selectedSession = useMemo(
    () => sessions.find((item) => item.id === selectedSessionId) ?? sessions[0] ?? null,
    [selectedSessionId, sessions],
  )

  useEffect(() => {
    let cancelled = false
    async function run() {
      if (!organizationId) return
      setLoading(true)
      setError(null)
      try {
        const config = await getCreativeServicesConfig({ organizationId }).then((r) => r.data)
        const recent = await listCreativeSessions(organizationId, 18).catch(() => [])
        if (cancelled) return
        setBrand(config.brand)
        setPricing(config.pricing)
        setSessions(recent)
        setSelectedSessionId((current) => current || recent[0]?.id || '')
      } catch (e) {
        if (!cancelled) setError(getErrorMessage(e, 'Creative services could not load.'))
      } finally {
        if (!cancelled) setLoading(false)
      }
    }
    void run()
    return () => {
      cancelled = true
    }
  }, [organizationId])

  useEffect(() => {
    if (!job?.jobId) return
    const unsubscribe = onSnapshot(doc(db, 'flyer_jobs', job.jobId), (snap) => {
      const data = snap.data()
      if (!data) return
      setJob({
        jobId: snap.id,
        status: String(data.status ?? 'pending'),
        currentStep: String(data.currentStep ?? ''),
        progress: Number(data.progress ?? 0),
        imageUrl: data.imageUrl ? String(data.imageUrl) : undefined,
        sessionId: data.sessionId ? String(data.sessionId) : undefined,
        error: data.error ? String(data.error) : undefined,
      })
      if (data.status === 'complete' && organizationId) {
        listCreativeSessions(organizationId, 18).then((recent) => {
          setSessions(recent)
          setSelectedSessionId(String(data.sessionId ?? recent[0]?.id ?? ''))
        }).catch(() => {})
      }
    })
    return () => unsubscribe()
  }, [job?.jobId, organizationId])

  async function uploadCreativeAsset(file: File, folder: 'brand' | 'source') {
    if (!organizationId) return ''
    const extension = file.name.split('.').pop() || 'png'
    const uniqueId = typeof crypto !== 'undefined' && 'randomUUID' in crypto
      ? crypto.randomUUID()
      : `${Date.now()}-${Math.random().toString(36).slice(2)}`
    const path = `creative-brands/${organizationId}/${folder}-${uniqueId}.${extension}`
    const storageRef = ref(storage, path)
    await uploadBytes(storageRef, file, file.type ? { contentType: file.type } : undefined)
    return getDownloadURL(storageRef)
  }

  async function handleLogoUpload(event: ChangeEvent<HTMLInputElement>) {
    const file = event.target.files?.[0]
    event.target.value = ''
    if (!file) return
    setError(null)
    try {
      const logoUrl = await uploadCreativeAsset(file, 'brand')
      setBrand((current) => ({ ...current, logoUrl }))
    } catch (e) {
      setError(getErrorMessage(e, 'Logo upload failed.'))
    }
  }

  async function handleSourceUpload(event: ChangeEvent<HTMLInputElement>) {
    const files = Array.from(event.target.files ?? [])
    event.target.value = ''
    if (files.length === 0) return
    setError(null)
    setSourceUploading(true)
    try {
      const remainingSlots = Math.max(0, 200 - referenceMedia.length)
      const uploads = await Promise.all(
        files.slice(0, remainingSlots).map(async (file) => ({
          url: await uploadCreativeAsset(file, 'source'),
          name: file.name,
        })),
      )
      setReferenceMedia((current) => [...current, ...uploads].slice(0, 200))
      setUploadedFlyerUrl((current) => current || uploads[0]?.url || '')
    } catch (e) {
      setError(getErrorMessage(e, 'Reference upload failed.'))
    } finally {
      setSourceUploading(false)
    }
  }

  function removeReferenceMedia(url: string) {
    const next = referenceMedia.filter((item) => item.url !== url)
    setReferenceMedia(next)
    if (uploadedFlyerUrl === url) {
      setUploadedFlyerUrl(next[0]?.url ?? '')
    }
  }

  async function handleSaveBrand() {
    if (!organizationId) return
    setSavingBrand(true)
    setError(null)
    try {
      const result = await saveCreativeBrandConfig({ organizationId, ...brand })
      setBrand(result.data.brand)
    } catch (e) {
      setError(getErrorMessage(e, 'Brand profile could not be saved.'))
    } finally {
      setSavingBrand(false)
    }
  }

  async function submitJob(extra: Record<string, unknown> = {}) {
    if (!organizationId) return
    if (!eventName.trim() && !extra.sourceSessionId) {
      setError('Enter the event name first.')
      return
    }
    setSubmitting(true)
    setError(null)
    setJob(null)
    try {
      const result = await submitCreativeFlyerJob({
        organizationId,
        serviceType,
        eventName: eventName.trim(),
        date: date.trim(),
        time: time.trim(),
        venue: venue.trim(),
        djs: djs.trim(),
        creativeDescription: creativeDescription.trim(),
        uploadedFlyerUrl: uploadedFlyerUrl || referenceMedia[0]?.url || undefined,
        customBgUrl: uploadedFlyerUrl || referenceMedia[0]?.url || undefined,
        referenceImageUrls: referenceMedia.map((item) => item.url),
        tiers: tiers.map(tierPayload).filter((tier) => tier.name),
        ...extra,
      })
      setJob({ jobId: result.data.jobId, status: 'pending', currentStep: 'Queued', progress: 0 })
    } catch (e) {
      setError(getErrorMessage(e, 'Could not start generation. Check your wallet balance and try again.'))
    } finally {
      setSubmitting(false)
    }
  }

  async function submitMinorEdit() {
    if (!selectedSession || !editInstruction.trim()) {
      setError('Choose a flyer and describe the small edit.')
      return
    }
    await submitJob({
      serviceType: selectedSession.serviceType,
      editMode: 'minor',
      sourceSessionId: selectedSession.id,
      sourceFlyerUrl: selectedSession.imageUrl,
      editInstruction: editInstruction.trim(),
      eventName: selectedSession.eventName,
    })
  }

  async function submitRedesign() {
    if (!selectedSession) {
      setError('Choose a flyer to redesign.')
      return
    }
    await submitJob({
      serviceType: selectedSession.serviceType,
      editMode: 'redesign',
      sourceSessionId: selectedSession.id,
      eventName: selectedSession.eventName,
      creativeDescription: creativeDescription.trim() || selectedSession.prompt,
    })
  }

  if (loading) {
    return <div className="page-loader">Loading…</div>
  }

  return (
    <div className="dashboard-stack">
      <section className="page-hero page-hero--events page-hero--creative">
        <div className="page-hero__content">
          <p className="eyebrow">Creative services</p>
          <h2>Generate premium event flyers and table-package flyers.</h2>
          <div className="hero-chip-row">
            <span>{formatMoney(pricing.flyerGhs)} flyer</span>
            <span>{formatMoney(pricing.tablePackageFlyerGhs)} table package flyer</span>
            <span>{pricing.includedMinorEdits} minor edits · {pricing.includedRedesigns} redesigns included</span>
          </div>
        </div>
        <div className="page-hero__panel">
          <Link className="button button--secondary" to="/studio/payments">Load wallet</Link>
          <Link className="button button--secondary" to="/studio/promote">Promote event</Link>
        </div>
      </section>

      {error ? <p className="form-error">{error}</p> : null}

      <section className="content-grid">
        <article className="panel">
          <div className="panel__header">
            <div>
              <p className="eyebrow"><Palette size={14} aria-hidden /> Brand profile</p>
              <h3>Your flyer brand</h3>
            </div>
          </div>
          <div className="form-grid" style={{ padding: '1.25rem 1.5rem' }}>
            <label className="field">
              <span>Brand name</span>
              <input value={brand.brandName} onChange={(e) => setBrand((b) => ({ ...b, brandName: e.target.value }))} />
            </label>
            <label className="field">
              <span>Brand color</span>
              <input type="color" value={brand.brandColor || '#7dd3fc'} onChange={(e) => setBrand((b) => ({ ...b, brandColor: e.target.value }))} />
            </label>
            <label className="field field--wide">
              <span>Brand style</span>
              <textarea rows={3} value={brand.brandStyle} onChange={(e) => setBrand((b) => ({ ...b, brandStyle: e.target.value }))} placeholder="Luxury nightlife, clean corporate, Afrobeats energy, fashion editorial..." />
            </label>
            <label className="field">
              <span>Instagram</span>
              <input value={brand.instagram} onChange={(e) => setBrand((b) => ({ ...b, instagram: e.target.value }))} />
            </label>
            <label className="field">
              <span>Website</span>
              <input value={brand.website} onChange={(e) => setBrand((b) => ({ ...b, website: e.target.value }))} />
            </label>
            <label className="field field--wide">
              <span>Logo</span>
              <div className="creative-logo-row">
                {brand.logoUrl ? <img src={brand.logoUrl} alt="Brand logo" /> : <span>No logo uploaded</span>}
                <label className="button button--secondary">
                  <ImagePlus size={16} aria-hidden />
                  Upload logo
                  <input type="file" accept="image/*" onChange={(e) => void handleLogoUpload(e)} />
                </label>
              </div>
            </label>
            <button type="button" className="button button--primary" onClick={() => void handleSaveBrand()} disabled={savingBrand}>
              <Save size={16} aria-hidden />
              {savingBrand ? 'Saving…' : 'Save brand'}
            </button>
          </div>
        </article>

        <article className="panel">
          <div className="panel__header">
            <div>
              <p className="eyebrow"><Wand2 size={14} aria-hidden /> Generator</p>
              <h3>{serviceType === 'event_flyer' ? 'Event flyer' : 'Table package flyer'}</h3>
            </div>
          </div>
          <div className="creative-service-tabs">
            <button className={serviceType === 'event_flyer' ? 'active' : ''} onClick={() => setServiceType('event_flyer')} type="button">Event flyer</button>
            <button className={serviceType === 'table_package_flyer' ? 'active' : ''} onClick={() => setServiceType('table_package_flyer')} type="button">Table packages</button>
          </div>
          <div className="form-grid" style={{ padding: '1.25rem 1.5rem' }}>
            <label className="field">
              <span>Event name</span>
              <input value={eventName} onChange={(e) => setEventName(e.target.value)} placeholder="Night Lights" />
            </label>
            <label className="field">
              <span>Venue</span>
              <input value={venue} onChange={(e) => setVenue(e.target.value)} placeholder="Venue or city" />
            </label>
            <label className="field">
              <span>Date</span>
              <input value={date} onChange={(e) => setDate(e.target.value)} placeholder="Friday, 26 June" />
            </label>
            <label className="field">
              <span>Time</span>
              <input value={time} onChange={(e) => setTime(e.target.value)} placeholder="8 PM" />
            </label>
            <label className="field field--wide">
              <span>DJs / performers</span>
              <input value={djs} onChange={(e) => setDjs(e.target.value)} placeholder="DJ names, performers, hosts" />
            </label>
            <label className="field field--wide">
              <span>Creative direction</span>
              <textarea rows={4} value={creativeDescription} onChange={(e) => setCreativeDescription(e.target.value)} placeholder="Describe the mood, subject, colors, audience, and any must-have details." />
            </label>
            {serviceType === 'table_package_flyer' ? (
              <div className="field field--wide">
                <span>Table packages</span>
                <div className="creative-tier-list">
                  {tiers.map((tier, index) => (
                    <div className="creative-tier-row" key={index}>
                      <input value={tier.name} onChange={(e) => setTiers((list) => list.map((item, i) => i === index ? { ...item, name: e.target.value } : item))} placeholder="Tier name" />
                      <input value={tier.price} onChange={(e) => setTiers((list) => list.map((item, i) => i === index ? { ...item, price: e.target.value } : item))} placeholder="Price" />
                      <textarea rows={3} value={tier.itemsText} onChange={(e) => setTiers((list) => list.map((item, i) => i === index ? { ...item, itemsText: e.target.value } : item))} placeholder="One item per line" />
                    </div>
                  ))}
                </div>
                <button type="button" className="button button--secondary" onClick={() => setTiers((list) => [...list, { name: '', price: '', itemsText: '' }])}>Add tier</button>
              </div>
            ) : null}
            <label className="field field--wide">
              <span>Reference images</span>
              <div className="creative-logo-row">
                {referenceMedia.length > 0 ? <span>{referenceMedia.length} images ready</span> : <span>Optional source images for table-package overlays or event style references</span>}
                <label className="button button--secondary">
                  <ImagePlus size={16} aria-hidden />
                  {sourceUploading ? 'Uploading…' : 'Upload images'}
                  <input type="file" accept="image/*" multiple onChange={(e) => void handleSourceUpload(e)} />
                </label>
              </div>
              {referenceMedia.length > 0 ? (
                <div className="creative-reference-grid">
                  {referenceMedia.map((item) => (
                    <div className="creative-reference-thumb" key={item.url}>
                      <img src={item.url} alt={item.name} />
                      <button type="button" onClick={() => removeReferenceMedia(item.url)} aria-label={`Remove ${item.name}`}>
                        <X size={14} aria-hidden />
                      </button>
                    </div>
                  ))}
                </div>
              ) : null}
            </label>
            <button type="button" className="button button--primary" onClick={() => void submitJob()} disabled={submitting}>
              <Sparkles size={16} aria-hidden />
              {submitting ? 'Starting…' : `Generate for ${formatMoney(serviceType === 'table_package_flyer' ? pricing.tablePackageFlyerGhs : pricing.flyerGhs)}`}
            </button>
          </div>
        </article>
      </section>

      {job ? (
        <article className="panel creative-job-panel">
          <div>
            <p className="eyebrow">Generation status</p>
            <h3>{job.status === 'complete' ? 'Flyer ready' : job.status === 'error' ? 'Generation failed' : job.currentStep || 'Working'}</h3>
            <p className="text-subtle">{job.error || `${Math.round(job.progress ?? 0)}% complete`}</p>
          </div>
          {job.imageUrl ? (
            <a className="button button--primary" href={job.imageUrl} target="_blank" rel="noreferrer">
              <Download size={16} aria-hidden />
              Open result
            </a>
          ) : null}
        </article>
      ) : null}

      <section className="content-grid">
        <article className="panel">
          <div className="panel__header">
            <div>
              <p className="eyebrow">Recent creative assets</p>
              <h3>Projects</h3>
            </div>
          </div>
          <div className="creative-session-grid">
            {sessions.length === 0 ? (
              <div className="empty-card">
                <h4>No flyers yet</h4>
                <p>Generate your first paid flyer from this page.</p>
              </div>
            ) : sessions.map((item) => (
              <button type="button" className={item.id === selectedSession?.id ? 'creative-session-card creative-session-card--active' : 'creative-session-card'} key={item.id} onClick={() => setSelectedSessionId(item.id)}>
                {item.imageUrl ? <img src={item.imageUrl} alt={item.eventName} /> : null}
                <strong>{item.eventName || 'Creative asset'}</strong>
                <small>{item.serviceType === 'table_package_flyer' ? 'Table packages' : 'Event flyer'} · {formatDateTime(item.createdAt)}</small>
              </button>
            ))}
          </div>
        </article>

        <aside className="setup-side-panel">
          <div className="setup-side-panel__card">
            <span className="eyebrow"><RefreshCw size={14} aria-hidden /> Included edits</span>
            <p>
              {selectedSession
                ? `${selectedSession.minorEditsRemaining ?? 0} minor edits and ${selectedSession.redesignsRemaining ?? 0} redesigns remaining for the selected paid flyer.`
                : 'Select a generated flyer to use included edits.'}
            </p>
          </div>
          {selectedSession ? (
            <div className="setup-side-panel__card">
              <img className="creative-selected-preview" src={selectedSession.imageUrl} alt={selectedSession.eventName} />
              <label className="field">
                <span>Minor edit request</span>
                <textarea rows={3} value={editInstruction} onChange={(e) => setEditInstruction(e.target.value)} placeholder="Make the date brighter, remove the extra glow, change venue text..." />
              </label>
              <button className="button button--secondary button--full" type="button" onClick={() => void submitMinorEdit()} disabled={submitting}>
                Minor edit
              </button>
              <button className="button button--ghost button--full" type="button" onClick={() => void submitRedesign()} disabled={submitting}>
                Use redesign
              </button>
              <a className="button button--primary button--full" href={selectedSession.imageUrl} target="_blank" rel="noreferrer">
                <Download size={16} aria-hidden />
                Download
              </a>
            </div>
          ) : null}
        </aside>
      </section>
    </div>
  )
}
