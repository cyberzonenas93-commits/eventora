import { useCallback, useEffect, useMemo, useRef, useState, type FormEvent } from 'react'
import { httpsCallable } from 'firebase/functions'
import {
  Bell,
  CheckCircle2,
  Clock,
  FileText,
  Lock,
  MapPin,
  Plus,
  Send,
  ShieldCheck,
  Star,
  Store,
  UploadCloud,
  Utensils,
  Users,
  XCircle,
  type LucideIcon,
} from 'lucide-react'

import { functions } from '../firebaseFunctions'
import { getErrorMessage } from '../lib/errorMessages'
import { formatDateTime, formatMoney } from '../lib/formatters'
import {
  listOrganizerPlaces,
  listPlaceMenuItems,
  listPlaceMenuSections,
  listPlaceReservations,
  uploadPlaceVerificationFile,
} from '../lib/portalData'
import { usePortalSession } from '../lib/portalSession'
import type {
  PortalPlace,
  PortalPlaceMenuItem,
  PortalPlaceMenuSection,
  PortalPlaceReservation,
} from '../lib/types'

const upsertPlaceProfile = httpsCallable<
  {
    placeId: string
    organizationId: string
    name: string
    description?: string
    city?: string
    address?: string
    phone?: string
    website?: string
    categories?: string[]
    amenities?: string[]
    openingHours?: string[]
    status?: string
  },
  { ok: boolean; placeId: string; verificationStatus?: string }
>(functions, 'upsertPlaceProfile')

const submitPlaceVerification = httpsCallable<
  {
    placeId: string
    method: string
    contactEmail?: string
    contactPhone?: string
    googleMapsUrl?: string
    websiteUrl?: string
    socialUrl?: string
    documentUrls?: string[]
    notes?: string
  },
  {
    ok: boolean
    requestId: string
    placeId: string
    status: string
    emailContactVerified?: boolean
  }
>(functions, 'submitPlaceVerification')

const upsertPlaceMenuSection = httpsCallable<
  {
    placeId: string
    sectionId?: string
    name: string
    description?: string
    sortOrder?: number
    visible?: boolean
  },
  { ok: boolean; sectionId: string }
>(functions, 'upsertPlaceMenuSection')

const upsertPlaceMenuItem = httpsCallable<
  {
    placeId: string
    sectionId: string
    itemId?: string
    name: string
    description?: string
    price: number
    currency?: string
    featured?: boolean
    status?: string
    sortOrder?: number
  },
  { ok: boolean; itemId: string }
>(functions, 'upsertPlaceMenuItem')

const updatePlaceReservationStatus = httpsCallable<
  { reservationId: string; status: string; internalNote?: string },
  { ok: boolean; reservationId: string; status: string }
>(functions, 'updatePlaceReservationStatus')

const launchPlacePushCampaign = httpsCallable<
  { placeId: string; title: string; message: string; name?: string },
  {
    ok: boolean
    campaignId: string
    subscriberCount: number
    pushAudience: number
    sent: number
    failed: number
    costGhs: number
  }
>(functions, 'launchPlacePushCampaign')

export function PlacesPage() {
  const { organizationId, application, profile, user } = usePortalSession()
  const [places, setPlaces] = useState<PortalPlace[]>([])
  const [sections, setSections] = useState<PortalPlaceMenuSection[]>([])
  const [items, setItems] = useState<PortalPlaceMenuItem[]>([])
  const [reservations, setReservations] = useState<PortalPlaceReservation[]>([])
  const [selectedPlaceId, setSelectedPlaceId] = useState('')
  const selectedPlaceIdRef = useRef('')
  const [loading, setLoading] = useState(true)
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [message, setMessage] = useState<string | null>(null)

  const [profileName, setProfileName] = useState(application?.organizerName || '')
  const [profileDescription, setProfileDescription] = useState('')
  const [profileAddress, setProfileAddress] = useState(application?.businessAddress || '')
  const [profileCity, setProfileCity] = useState(application?.audienceCity || 'Accra')
  const [profilePhone, setProfilePhone] = useState(application?.phone || '')
  const [profileWebsite, setProfileWebsite] = useState(application?.instagram || '')
  const [sectionName, setSectionName] = useState('Bottles')
  const [sectionDescription, setSectionDescription] = useState('')
  const [itemSectionId, setItemSectionId] = useState('')
  const [itemName, setItemName] = useState('')
  const [itemDescription, setItemDescription] = useState('')
  const [itemPrice, setItemPrice] = useState('')
  const [itemFeatured, setItemFeatured] = useState(false)
  const [pushTitle, setPushTitle] = useState('')
  const [pushMessage, setPushMessage] = useState('')
  const [verificationMethod, setVerificationMethod] = useState('email')
  const [verificationEmail, setVerificationEmail] = useState(profile?.email || user?.email || '')
  const [verificationPhone, setVerificationPhone] = useState(application?.phone || profile?.phone || '')
  const [verificationMapsUrl, setVerificationMapsUrl] = useState('')
  const [verificationWebsiteUrl, setVerificationWebsiteUrl] = useState('')
  const [verificationSocialUrl, setVerificationSocialUrl] = useState('')
  const [verificationNotes, setVerificationNotes] = useState('')
  const [verificationFile, setVerificationFile] = useState<File | null>(null)
  const [activePlacesTab, setActivePlacesTab] = useState<'profile' | 'menu' | 'reservations' | 'subscribers' | 'verification'>('profile')
  const [reservationStatusFilter, setReservationStatusFilter] = useState('all')

  const selectedPlace = useMemo(
    () => places.find((place) => place.id === selectedPlaceId) ?? null,
    [places, selectedPlaceId],
  )
  const pendingReservations = reservations.filter((reservation) => reservation.status === 'pending')
  const verifiedCount = places.filter((place) => place.verified || place.verificationStatus === 'verified').length
  const selectedPlaceMenuCount = selectedPlace ? items.filter((item) => item.placeId === selectedPlace.id).length : 0
  const selectedPlaceReservationCount = selectedPlace
    ? reservations.filter((reservation) => reservation.placeId === selectedPlace.id).length
    : 0
  const verificationState = selectedPlace ? verificationLabel(selectedPlace) : 'New place profile'
  const visibleReservations = reservations
    .filter((reservation) => reservationStatusFilter === 'all' || reservation.status === reservationStatusFilter)
    .sort((a, b) => new Date(a.requestedAt).getTime() - new Date(b.requestedAt).getTime())

  useEffect(() => {
    selectedPlaceIdRef.current = selectedPlaceId
  }, [selectedPlaceId])

  const refresh = useCallback(async (placeId?: string) => {
    if (!organizationId) return
    setError(null)
    const placeList = await listOrganizerPlaces(organizationId)
    const nextPlaceId = (placeId ?? selectedPlaceIdRef.current) || placeList[0]?.id || ''
    const [sectionList, itemList, reservationList] = await Promise.all([
      listPlaceMenuSections(nextPlaceId),
      listPlaceMenuItems(nextPlaceId),
      listPlaceReservations(organizationId, nextPlaceId || undefined),
    ])
    setPlaces(placeList)
    setSelectedPlaceId(nextPlaceId)
    setSections(sectionList)
    setItems(itemList)
    setReservations(reservationList)
    setItemSectionId((current) => sectionList.some((section) => section.id === current) ? current : sectionList[0]?.id || '')
    const active = placeList.find((place) => place.id === nextPlaceId)
    if (active) {
      setProfileName(active.name)
      setProfileDescription(active.description)
      setProfileAddress(active.address)
      setProfileCity(active.city)
      setProfilePhone(active.phone)
      setProfileWebsite(active.website || active.mapsUrl)
      setPushTitle(active.name)
      setVerificationEmail((current) => current || profile?.email || user?.email || '')
      setVerificationPhone(active.phone || profile?.phone || application?.phone || '')
      setVerificationMapsUrl(active.mapsUrl)
      setVerificationWebsiteUrl(active.website)
    }
  }, [application?.phone, organizationId, profile?.email, profile?.phone, user?.email])

  useEffect(() => {
    let cancelled = false
    if (!organizationId) {
      setLoading(false)
      return
    }
    async function run() {
      setLoading(true)
      try {
        await refresh()
      } catch (err) {
        if (!cancelled) setError(getErrorMessage(err, 'Could not load places.'))
      } finally {
        if (!cancelled) setLoading(false)
      }
    }
    void run()
    return () => {
      cancelled = true
    }
  }, [organizationId, refresh])

  useEffect(() => {
    if (!selectedPlaceId || !organizationId) return
    let cancelled = false
    async function run() {
      try {
        const [sectionList, itemList, reservationList] = await Promise.all([
          listPlaceMenuSections(selectedPlaceId),
          listPlaceMenuItems(selectedPlaceId),
          listPlaceReservations(organizationId ?? '', selectedPlaceId),
        ])
        if (cancelled) return
        setSections(sectionList)
        setItems(itemList)
        setReservations(reservationList)
        setItemSectionId((current) => sectionList.some((section) => section.id === current) ? current : sectionList[0]?.id || '')
      } catch (err) {
        if (!cancelled) setError(getErrorMessage(err, 'Could not load place workspace.'))
      }
    }
    void run()
    return () => {
      cancelled = true
    }
  }, [organizationId, selectedPlaceId])

  async function saveProfile(e: FormEvent) {
    e.preventDefault()
    if (!organizationId || saving) return
    setSaving(true)
    setError(null)
    setMessage(null)
    try {
      const placeId = selectedPlaceId || slugify(profileName || application?.organizerName || 'place')
      const result = await upsertPlaceProfile({
        placeId,
        organizationId,
        name: profileName.trim(),
        description: profileDescription.trim(),
        city: profileCity.trim() || 'Accra',
        address: profileAddress.trim(),
        phone: profilePhone.trim(),
        website: profileWebsite.trim(),
        categories: ['Venue', application?.businessType || 'Events'].filter(Boolean),
        status: 'active',
      })
      await refresh(result.data.placeId)
      setMessage(
        result.data.verificationStatus === 'verified'
          ? 'Verified place profile saved.'
          : 'Place profile saved. Verification is required before paid push and featured placement.',
      )
    } catch (err) {
      setError(getErrorMessage(err, 'Could not save place profile.'))
    } finally {
      setSaving(false)
    }
  }

  async function createSection(e: FormEvent) {
    e.preventDefault()
    if (!selectedPlaceId || saving) return
    setSaving(true)
    setError(null)
    setMessage(null)
    try {
      await upsertPlaceMenuSection({
        placeId: selectedPlaceId,
        name: sectionName.trim(),
        description: sectionDescription.trim(),
        sortOrder: sections.length + 1,
        visible: true,
      })
      setSectionName('')
      setSectionDescription('')
      await refresh(selectedPlaceId)
      setMessage('Menu section created.')
    } catch (err) {
      setError(getErrorMessage(err, 'Could not create menu section.'))
    } finally {
      setSaving(false)
    }
  }

  async function createItem(e: FormEvent) {
    e.preventDefault()
    if (!selectedPlaceId || !itemSectionId || saving) return
    setSaving(true)
    setError(null)
    setMessage(null)
    try {
      await upsertPlaceMenuItem({
        placeId: selectedPlaceId,
        sectionId: itemSectionId,
        name: itemName.trim(),
        description: itemDescription.trim(),
        price: Number(itemPrice || 0),
        featured: itemFeatured,
        status: 'available',
        sortOrder: items.length + 1,
      })
      setItemName('')
      setItemDescription('')
      setItemPrice('')
      setItemFeatured(false)
      await refresh(selectedPlaceId)
      setMessage('Menu item published.')
    } catch (err) {
      setError(getErrorMessage(err, 'Could not publish menu item.'))
    } finally {
      setSaving(false)
    }
  }

  async function changeReservationStatus(reservationId: string, status: string) {
    setError(null)
    setMessage(null)
    try {
      await updatePlaceReservationStatus({ reservationId, status })
      await refresh(selectedPlaceId)
      setMessage(`Reservation marked ${status}.`)
    } catch (err) {
      setError(getErrorMessage(err, 'Could not update reservation.'))
    }
  }

  async function sendPlacePush(e: FormEvent) {
    e.preventDefault()
    if (!selectedPlace || saving) return
    setSaving(true)
    setError(null)
    setMessage(null)
    try {
      const result = await launchPlacePushCampaign({
        placeId: selectedPlace.id,
        title: pushTitle.trim() || selectedPlace.name,
        message: pushMessage.trim(),
        name: `${selectedPlace.name} subscriber push`,
      })
      setPushMessage('')
      setMessage(`Push sent to ${result.data.sent} subscribers. Cost ${formatMoney(result.data.costGhs)}.`)
      await refresh(selectedPlace.id)
    } catch (err) {
      setError(getErrorMessage(err, 'Could not send place push.'))
    } finally {
      setSaving(false)
    }
  }

  async function requestVerification(e: FormEvent) {
    e.preventDefault()
    if (!selectedPlace || !user || saving) return
    setSaving(true)
    setError(null)
    setMessage(null)
    try {
      const documentUrls: string[] = []
      if (verificationFile) {
        documentUrls.push(await uploadPlaceVerificationFile(user.uid, selectedPlace.id, verificationFile))
      }
      const result = await submitPlaceVerification({
        placeId: selectedPlace.id,
        method: verificationMethod,
        contactEmail: verificationEmail.trim(),
        contactPhone: verificationPhone.trim(),
        googleMapsUrl: verificationMapsUrl.trim(),
        websiteUrl: verificationWebsiteUrl.trim(),
        socialUrl: verificationSocialUrl.trim(),
        documentUrls,
        notes: verificationNotes.trim(),
      })
      setVerificationFile(null)
      setMessage(
        result.data.emailContactVerified
          ? 'Verification request submitted. Your email contact is confirmed and ownership review is pending.'
          : 'Verification request submitted. We will review the ownership evidence.',
      )
      await refresh(selectedPlace.id)
    } catch (err) {
      setError(getErrorMessage(err, 'Could not submit verification.'))
    } finally {
      setSaving(false)
    }
  }

  if (loading) return <div className="page-loader">Loading...</div>

  return (
    <div className="dashboard-stack">
      <section className="page-hero page-hero--events page-hero--wallet-services">
        <div className="page-hero__content">
          <p className="eyebrow">Places</p>
          <h2>Add your location, publish menus, and unlock verified venue tools.</h2>
          <div className="hero-chip-row">
            <span>{places.length} places</span>
            <span>{items.length} menu items</span>
            <span>{pendingReservations.length} pending reservations</span>
            <span>{places.filter((place) => place.verified).length} verified</span>
          </div>
        </div>
        <div className="page-hero__panel">
          <label className="search-field">
            <span>Place</span>
            <select value={selectedPlaceId} onChange={(e) => setSelectedPlaceId(e.target.value)}>
              <option value="">New place profile</option>
              {places.map((place) => (
                <option key={place.id} value={place.id}>{place.name}</option>
              ))}
            </select>
          </label>
          <div className="places-hero-card">
            <strong>{selectedPlace?.name || 'Start a venue profile'}</strong>
            <span>{verificationState}</span>
            <div className="places-hero-card__stats">
              <span>{selectedPlaceMenuCount} menu</span>
              <span>{selectedPlaceReservationCount} reservations</span>
              <span>{selectedPlace?.subscriberCount ?? 0} subscribers</span>
            </div>
          </div>
        </div>
      </section>

      {error && <p className="checkout__error">{error}</p>}
      {message && <p className="checkout__info">{message}</p>}

      <section className="places-command-center">
        <article className="places-command-card places-command-card--primary">
          <div>
            <p className="eyebrow">Venue status</p>
            <h3>{selectedPlace ? selectedPlace.name : 'Create your first place'}</h3>
            <span>{selectedPlace?.address || selectedPlace?.city || 'Self-serve onboarding'}</span>
          </div>
          <span className={`status-pill status-pill--${selectedPlace?.verified ? 'confirmed' : 'pending'}`}>
            {selectedPlace?.verified ? 'verified' : 'unverified'}
          </span>
        </article>
        <article className="places-command-card">
          <ShieldCheck size={20} aria-hidden />
          <strong>{verifiedCount}/{places.length || 1}</strong>
          <span>verified places</span>
        </article>
        <article className="places-command-card">
          <Utensils size={20} aria-hidden />
          <strong>{items.length}</strong>
          <span>menu items</span>
        </article>
        <article className="places-command-card">
          <Clock size={20} aria-hidden />
          <strong>{pendingReservations.length}</strong>
          <span>pending reservations</span>
        </article>
      </section>

      <nav className="places-tabbar" aria-label="Place management sections">
        {[
          ['profile', 'Profile'],
          ['menu', 'Menu'],
          ['reservations', 'Reservations'],
          ['subscribers', 'Subscribers'],
          ['verification', 'Verification'],
        ].map(([id, label]) => (
          <button
            className={activePlacesTab === id ? 'is-active' : ''}
            key={id}
            onClick={() => setActivePlacesTab(id as typeof activePlacesTab)}
            type="button"
          >
            {label}
          </button>
        ))}
      </nav>

      <section className="content-grid">
        {activePlacesTab === 'profile' ? (
        <article className="panel">
          <div className="panel__header">
            <div>
              <p className="eyebrow">Profile</p>
              <h3>{selectedPlace ? selectedPlace.name : 'Create a place'}</h3>
            </div>
            <Store size={22} aria-hidden />
          </div>
          <div className="hero-chip-row">
            <span>{selectedPlace ? verificationLabel(selectedPlace) : 'Self-serve onboarding'}</span>
            {!selectedPlace || selectedPlace.verified ? null : (
              <span>Verification unlocks paid push and featured placement</span>
            )}
          </div>
          <form className="form-grid" onSubmit={saveProfile}>
            <label>
              <span>Name</span>
              <input value={profileName} onChange={(e) => setProfileName(e.target.value)} required />
            </label>
            <label>
              <span>City</span>
              <input value={profileCity} onChange={(e) => setProfileCity(e.target.value)} />
            </label>
            <label className="form-grid__wide">
              <span>Address</span>
              <input value={profileAddress} onChange={(e) => setProfileAddress(e.target.value)} />
            </label>
            <label>
              <span>Phone</span>
              <input value={profilePhone} onChange={(e) => setProfilePhone(e.target.value)} />
            </label>
            <label>
              <span>Website / social</span>
              <input value={profileWebsite} onChange={(e) => setProfileWebsite(e.target.value)} />
            </label>
            <label className="form-grid__wide">
              <span>Description</span>
              <textarea value={profileDescription} onChange={(e) => setProfileDescription(e.target.value)} rows={4} />
            </label>
            <button className="button button--primary" disabled={saving} type="submit">
              <CheckCircle2 size={16} aria-hidden />
              {selectedPlace ? 'Save place' : 'Create unverified place'}
            </button>
          </form>
        </article>
        ) : null}

        {activePlacesTab === 'verification' ? (
        <article className="panel">
          <div className="panel__header">
            <div>
              <p className="eyebrow">Verification</p>
              <h3>{selectedPlace?.verified ? 'Verified owner' : 'Verify this location'}</h3>
            </div>
            <ShieldCheck size={22} aria-hidden />
          </div>
          <div className="order-row">
            <div>
              <strong>{selectedPlace ? verificationLabel(selectedPlace) : 'Create a place first'}</strong>
              <span>
                Anyone can create a profile. Verification unlocks paid subscriber push, official ownership signals, and featured placement requests.
              </span>
            </div>
            {selectedPlace?.verified ? <span className="status-pill status-pill--confirmed">verified</span> : null}
          </div>
          <form className="form-grid" onSubmit={requestVerification}>
            <label>
              <span>Verification method</span>
              <select value={verificationMethod} onChange={(e) => setVerificationMethod(e.target.value)}>
                <option value="email">Regular email</option>
                <option value="phone">Business phone</option>
                <option value="document">Document upload</option>
                <option value="google_maps">Google Maps match</option>
                <option value="website_social">Website / social proof</option>
              </select>
            </label>
            {verificationMethod === 'email' ? (
            <label>
              <span>Contact email</span>
              <input
                inputMode="email"
                type="email"
                value={verificationEmail}
                onChange={(e) => setVerificationEmail(e.target.value)}
                placeholder="Any email you can access"
              />
            </label>
            ) : null}
            {verificationMethod === 'phone' ? (
            <label>
              <span>Phone</span>
              <input value={verificationPhone} onChange={(e) => setVerificationPhone(e.target.value)} />
            </label>
            ) : null}
            {verificationMethod === 'google_maps' ? (
            <label>
              <span>Google Maps link</span>
              <input value={verificationMapsUrl} onChange={(e) => setVerificationMapsUrl(e.target.value)} />
            </label>
            ) : null}
            {verificationMethod === 'website_social' ? (
            <>
            <label>
              <span>Website</span>
              <input value={verificationWebsiteUrl} onChange={(e) => setVerificationWebsiteUrl(e.target.value)} />
            </label>
            <label>
              <span>Social link</span>
              <input value={verificationSocialUrl} onChange={(e) => setVerificationSocialUrl(e.target.value)} />
            </label>
            </>
            ) : null}
            {verificationMethod === 'document' ? (
            <label className="form-grid__wide">
              <span>Proof document</span>
              <input
                accept="image/*,.pdf"
                onChange={(e) => setVerificationFile(e.target.files?.[0] ?? null)}
                type="file"
              />
            </label>
            ) : null}
            <label className="form-grid__wide">
              <span>Notes for reviewer</span>
              <textarea
                value={verificationNotes}
                onChange={(e) => setVerificationNotes(e.target.value)}
                rows={3}
                placeholder="Tell us how you are connected to this location."
              />
            </label>
            <button className="button button--primary" disabled={!selectedPlace || selectedPlace.verified || saving} type="submit">
              {verificationFile ? <UploadCloud size={16} aria-hidden /> : <FileText size={16} aria-hidden />}
              Submit verification
            </button>
          </form>
        </article>
        ) : null}

        {activePlacesTab === 'subscribers' ? (
        <article className="panel">
          <div className="panel__header">
            <div>
              <p className="eyebrow">Subscriber push</p>
              <h3>Paid location alerts</h3>
            </div>
            <Bell size={22} aria-hidden />
          </div>
          <div className="metric-grid">
            <Metric icon={Users} label="Subscribers" value={`${selectedPlace?.subscriberCount ?? 0}`} />
            <Metric icon={Star} label="Rating" value={(selectedPlace?.rating ?? 0).toFixed(1)} />
            <Metric icon={Send} label="Fee estimate" value={formatMoney((selectedPlace?.subscriberCount ?? 0) * 0.02)} />
          </div>
          {!selectedPlace?.verified ? (
            <div className="empty-card">
              <h4><Lock size={16} aria-hidden /> Verification required</h4>
              <p>Paid push is unlocked after this location is verified.</p>
            </div>
          ) : null}
          <form className="form-grid form-grid--single" onSubmit={sendPlacePush}>
            <label>
              <span>Push title</span>
              <input value={pushTitle} onChange={(e) => setPushTitle(e.target.value)} />
            </label>
            <label>
              <span>Message</span>
              <textarea value={pushMessage} onChange={(e) => setPushMessage(e.target.value)} rows={4} required />
            </label>
            <button className="button button--primary" disabled={!selectedPlace?.verified || saving} type="submit">
              <Send size={16} aria-hidden />
              Send paid push
            </button>
          </form>
        </article>
        ) : null}
      </section>

      <section className="content-grid">
        {activePlacesTab === 'menu' ? (
        <article className="panel">
          <div className="panel__header">
            <div>
              <p className="eyebrow">Menu builder</p>
              <h3>Publish menu items</h3>
            </div>
            <Utensils size={22} aria-hidden />
          </div>
          <form className="form-grid" onSubmit={createSection}>
            <label>
              <span>Section name</span>
              <input value={sectionName} onChange={(e) => setSectionName(e.target.value)} required />
            </label>
            <label>
              <span>Description</span>
              <input value={sectionDescription} onChange={(e) => setSectionDescription(e.target.value)} />
            </label>
            <button className="button button--secondary" disabled={!selectedPlaceId || saving} type="submit">
              <Plus size={16} aria-hidden />
              Add section
            </button>
          </form>
          <form className="form-grid" onSubmit={createItem}>
            <label>
              <span>Section</span>
              <select value={itemSectionId} onChange={(e) => setItemSectionId(e.target.value)} required>
                <option value="">Choose section</option>
                {sections.map((section) => (
                  <option key={section.id} value={section.id}>{section.name}</option>
                ))}
              </select>
            </label>
            <label>
              <span>Item name</span>
              <input value={itemName} onChange={(e) => setItemName(e.target.value)} required />
            </label>
            <label>
              <span>Price</span>
              <input inputMode="decimal" value={itemPrice} onChange={(e) => setItemPrice(e.target.value)} required />
            </label>
            <label>
              <span>Description</span>
              <input value={itemDescription} onChange={(e) => setItemDescription(e.target.value)} />
            </label>
            <label className="checkbox-row">
              <input checked={itemFeatured} onChange={(e) => setItemFeatured(e.target.checked)} type="checkbox" />
              <span>Feature item</span>
            </label>
            <button className="button button--primary" disabled={!itemSectionId || saving} type="submit">
              Publish item
            </button>
          </form>
          <div className="partner-feature-grid">
            {items.length === 0 ? (
              <div className="empty-card">
                <h4>No menu items yet</h4>
                <p>Create menu sections and publish drinks, food, bottles, or packages.</p>
              </div>
            ) : (
              items.map((item) => (
                <div className="partner-feature-card" key={item.id}>
                  <strong>{item.name}</strong>
                  <p>{item.description || item.status}</p>
                  <small>{formatMoney(item.price)} · {sections.find((section) => section.id === item.sectionId)?.name || 'Menu'}</small>
                </div>
              ))
            )}
          </div>
        </article>
        ) : null}

        {activePlacesTab === 'reservations' ? (
        <article className="panel">
          <div className="panel__header">
            <div>
              <p className="eyebrow">Reservations</p>
              <h3>Manage requests</h3>
            </div>
            <Clock size={22} aria-hidden />
          </div>
          <div className="places-filter-row">
            <label>
              <span>Status</span>
              <select value={reservationStatusFilter} onChange={(e) => setReservationStatusFilter(e.target.value)}>
                <option value="all">All reservations</option>
                <option value="pending">Pending</option>
                <option value="confirmed">Confirmed</option>
                <option value="cancelled">Cancelled</option>
                <option value="change_requested">Change requested</option>
              </select>
            </label>
          </div>
          <div className="order-list">
            {visibleReservations.length === 0 ? (
              <div className="empty-card">
                <h4>No reservations yet</h4>
                <p>Guestlist, VIP table, and bottle-service requests will appear here.</p>
              </div>
            ) : (
              visibleReservations.map((reservation) => (
                <div className="order-row" key={reservation.id}>
                  <div>
                    <strong>{reservation.guestName}</strong>
                    <span>
                      {reservation.partySize} guests · {reservation.placeName || selectedPlace?.name} · {formatDateTime(reservation.requestedAt)}
                    </span>
                    {reservation.note ? <small>{reservation.note}</small> : null}
                  </div>
                  <div className="order-row__meta">
                    <span className={`status-pill status-pill--${reservation.status}`}>{reservation.status}</span>
                    <button className="button button--secondary" onClick={() => changeReservationStatus(reservation.id, 'confirmed')} type="button">
                      Confirm
                    </button>
                    <button className="button button--ghost" onClick={() => changeReservationStatus(reservation.id, 'cancelled')} type="button">
                      <XCircle size={15} aria-hidden />
                      Cancel
                    </button>
                  </div>
                </div>
              ))
            )}
          </div>
        </article>
        ) : null}
      </section>

      {activePlacesTab === 'profile' && selectedPlace ? (
        <section className="panel">
          <div className="panel__header">
            <div>
              <p className="eyebrow">Location details</p>
              <h3>{selectedPlace.address || selectedPlace.city}</h3>
            </div>
            <MapPin size={22} aria-hidden />
          </div>
          <div className="hero-chip-row">
            {selectedPlace.categories.map((category) => <span key={category}>{category}</span>)}
            {selectedPlace.amenities.slice(0, 6).map((amenity) => <span key={amenity}>{amenity}</span>)}
          </div>
        </section>
      ) : null}
    </div>
  )
}

function Metric({ icon: Icon, label, value }: { icon: LucideIcon; label: string; value: string }) {
  return (
    <div className="metric-card">
      <Icon size={18} aria-hidden />
      <strong>{value}</strong>
      <span>{label}</span>
    </div>
  )
}

function slugify(input: string) {
  return input
    .trim()
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '_')
    .replace(/^_+|_+$/g, '')
    .slice(0, 80) || `place_${Date.now()}`
}

function verificationLabel(place: PortalPlace) {
  if (place.verified || place.verificationStatus === 'verified') return 'Verified location owner'
  if (place.verificationStatus === 'verification_pending') return 'Verification pending'
  if (place.verificationStatus === 'rejected') return 'Verification rejected'
  if (place.verificationStatus === 'suspended') return 'Verification suspended'
  return 'Unverified location'
}
