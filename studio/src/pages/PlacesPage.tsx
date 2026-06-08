import { useCallback, useEffect, useId, useMemo, useRef, useState, type ChangeEvent, type FormEvent } from 'react'
import { httpsCallable } from 'firebase/functions'
import { Clock, MapPin, ShieldCheck, Utensils } from 'lucide-react'

import { functions } from '../firebaseFunctions'
import { getErrorMessage } from '../lib/errorMessages'
import { formatMoney } from '../lib/formatters'
import {
  listOrganizerPlaces,
  listPlaceMenuItems,
  listPlaceMenuSections,
  listPlaceReservations,
  uploadPlaceMediaFile,
  uploadPlaceVerificationFile,
} from '../lib/portalData'
import { usePortalSession } from '../lib/portalSession'
import type {
  PortalPlace,
  PortalPlaceMenuItem,
  PortalPlaceMenuSection,
  PortalPlaceReservation,
} from '../lib/types'
import { ClaimPanel } from './places/ClaimPanel'
import { MediaPanel } from './places/MediaPanel'
import { MenuTab } from './places/MenuTab'
import { ProfileTab } from './places/ProfileTab'
import { ReservationsTab } from './places/ReservationsTab'
import { SubscribersTab } from './places/SubscribersTab'
import { VerificationTab } from './places/VerificationTab'
import { slugify, verificationLabel } from './places/helpers'
import { VerificationBadge } from './places/VerificationBadge'

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
    coverUrl?: string
    logoUrl?: string
    galleryUrls?: string[]
  },
  { ok: boolean; placeId: string; verificationStatus?: string }
>(functions, 'upsertPlaceProfile')

const claimOrCreatePlace = httpsCallable<
  {
    googlePlaceId?: string
    name?: string
    address?: string
    latitude?: number
    longitude?: number
    phone?: string
    website?: string
  },
  { ok: boolean; placeId: string; verificationStatus?: string; canVerifyByPhone?: boolean }
>(functions, 'claimOrCreatePlace')

const startPlaceVerification = httpsCallable<
  { placeId: string; method: 'phone' },
  { ok: boolean; method: string; target: string; expiresInSeconds: number }
>(functions, 'startPlaceVerification')

const confirmPlaceVerification = httpsCallable<
  { placeId: string; code: string },
  { ok: boolean; verificationStatus: string }
>(functions, 'confirmPlaceVerification')

const autocompleteEventPlaces = httpsCallable<
  { query: string },
  { suggestions: Array<{ placeId: string; title: string; subtitle: string; fullText: string }> }
>(functions, 'autocompleteEventPlaces')

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

  // Claim a place from Google
  const [claimQuery, setClaimQuery] = useState('')
  const [claimSuggestions, setClaimSuggestions] = useState<
    Array<{ placeId: string; title: string; subtitle: string; fullText: string }>
  >([])
  const [claimSearching, setClaimSearching] = useState(false)
  const [claimingId, setClaimingId] = useState('')

  // Phone OTP verification
  const [otpSending, setOtpSending] = useState(false)
  const [otpTarget, setOtpTarget] = useState('')
  const [otpCode, setOtpCode] = useState('')
  const [otpConfirming, setOtpConfirming] = useState(false)

  // Media upload (cover + gallery)
  const [coverUploading, setCoverUploading] = useState(false)
  const [galleryUploading, setGalleryUploading] = useState(false)
  const coverInputId = useId()
  const coverReplaceId = useId()
  const galleryInputId = useId()

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
  const selectedPlaceVerified = Boolean(selectedPlace?.verified)
  const canVerifyByPhone = Boolean(selectedPlace && !selectedPlaceVerified && selectedPlace.verifiablePhone)
  const selectedGalleryUrls = selectedPlace?.galleryUrls ?? []
  const visibleReservations = reservations
    .filter((reservation) => reservationStatusFilter === 'all' || reservation.status === reservationStatusFilter)
    .sort((a, b) => new Date(a.requestedAt).getTime() - new Date(b.requestedAt).getTime())

  useEffect(() => {
    selectedPlaceIdRef.current = selectedPlaceId
  }, [selectedPlaceId])

  // Reset the phone OTP flow whenever the selected place changes.
  useEffect(() => {
    setOtpTarget('')
    setOtpCode('')
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

  async function searchPlacesToClaim(e: FormEvent) {
    e.preventDefault()
    const term = claimQuery.trim()
    if (!term || claimSearching) return
    setClaimSearching(true)
    setError(null)
    try {
      const result = await autocompleteEventPlaces({ query: term })
      setClaimSuggestions(result.data.suggestions ?? [])
    } catch (err) {
      setError(getErrorMessage(err, 'Could not search Google places.'))
    } finally {
      setClaimSearching(false)
    }
  }

  async function claimPlace(googlePlaceId: string) {
    if (!googlePlaceId || claimingId) return
    setClaimingId(googlePlaceId)
    setError(null)
    setMessage(null)
    try {
      const result = await claimOrCreatePlace({ googlePlaceId })
      setClaimQuery('')
      setClaimSuggestions([])
      await refresh(result.data.placeId)
      setMessage(
        result.data.canVerifyByPhone
          ? 'Place claimed. Verify by phone to unlock paid tools.'
          : 'Place claimed. Document verification is required to unlock paid tools.',
      )
    } catch (err) {
      setError(getErrorMessage(err, 'Could not claim this place.'))
    } finally {
      setClaimingId('')
    }
  }

  async function sendPhoneOtp() {
    if (!selectedPlace || otpSending) return
    setOtpSending(true)
    setError(null)
    setMessage(null)
    try {
      const result = await startPlaceVerification({ placeId: selectedPlace.id, method: 'phone' })
      setOtpTarget(result.data.target)
      setOtpCode('')
      setMessage(`We sent a 6-digit code to ${result.data.target}.`)
    } catch (err) {
      setError(getErrorMessage(err, 'Could not start phone verification.'))
    } finally {
      setOtpSending(false)
    }
  }

  async function confirmPhoneOtp(e: FormEvent) {
    e.preventDefault()
    if (!selectedPlace || otpConfirming) return
    const code = otpCode.trim()
    if (code.length !== 6) return
    setOtpConfirming(true)
    setError(null)
    setMessage(null)
    try {
      await confirmPlaceVerification({ placeId: selectedPlace.id, code })
      setOtpTarget('')
      setOtpCode('')
      await refresh(selectedPlace.id)
      setMessage('Phone verified. This place is now verified.')
    } catch (err) {
      setError(getErrorMessage(err, 'Could not confirm the code.'))
    } finally {
      setOtpConfirming(false)
    }
  }

  async function handleCoverUpload(e: ChangeEvent<HTMLInputElement>) {
    const file = e.target.files?.[0]
    e.target.value = ''
    if (!file || !selectedPlace || !organizationId || coverUploading) return
    setCoverUploading(true)
    setError(null)
    setMessage(null)
    try {
      const coverUrl = await uploadPlaceMediaFile(selectedPlace.id, 'cover', file)
      await savePlaceMedia({ coverUrl })
      setMessage('Cover image updated.')
    } catch (err) {
      setError(getErrorMessage(err, 'Could not upload cover image.'))
    } finally {
      setCoverUploading(false)
    }
  }

  async function handleGalleryUpload(e: ChangeEvent<HTMLInputElement>) {
    const files = Array.from(e.target.files ?? [])
    e.target.value = ''
    if (files.length === 0 || !selectedPlace || !organizationId || galleryUploading) return
    setGalleryUploading(true)
    setError(null)
    setMessage(null)
    try {
      const uploaded = await Promise.all(
        files.map((file) => uploadPlaceMediaFile(selectedPlace.id, 'gallery', file)),
      )
      await savePlaceMedia({ galleryUrls: [...selectedGalleryUrls, ...uploaded] })
      setMessage(`Added ${uploaded.length} photo${uploaded.length === 1 ? '' : 's'} to the gallery.`)
    } catch (err) {
      setError(getErrorMessage(err, 'Could not upload gallery images.'))
    } finally {
      setGalleryUploading(false)
    }
  }

  async function removeGalleryImage(url: string) {
    if (!selectedPlace || !organizationId) return
    setError(null)
    setMessage(null)
    try {
      await savePlaceMedia({ galleryUrls: selectedGalleryUrls.filter((item) => item !== url) })
      setMessage('Photo removed from gallery.')
    } catch (err) {
      setError(getErrorMessage(err, 'Could not update gallery.'))
    }
  }

  /**
   * Persist place media via upsertPlaceProfile alongside the existing profile
   * fields. The backend only accepts Firebase Storage URLs for coverUrl/galleryUrls.
   */
  async function savePlaceMedia(media: { coverUrl?: string; galleryUrls?: string[] }) {
    if (!selectedPlace || !organizationId) return
    const result = await upsertPlaceProfile({
      placeId: selectedPlace.id,
      organizationId,
      name: selectedPlace.name,
      description: selectedPlace.description,
      city: selectedPlace.city || 'Accra',
      address: selectedPlace.address,
      phone: selectedPlace.phone,
      website: selectedPlace.website,
      coverUrl: media.coverUrl ?? selectedPlace.coverUrl,
      galleryUrls: media.galleryUrls ?? selectedPlace.galleryUrls,
    })
    await refresh(result.data.placeId)
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
            {selectedPlace ? <VerificationBadge place={selectedPlace} /> : <span>{verificationState}</span>}
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
          {selectedPlace ? (
            <VerificationBadge place={selectedPlace} />
          ) : (
            <span className="status-pill status-pill--draft">New</span>
          )}
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
          <ClaimPanel
            claimQuery={claimQuery}
            setClaimQuery={setClaimQuery}
            searchPlacesToClaim={searchPlacesToClaim}
            claimSearching={claimSearching}
            claimSuggestions={claimSuggestions}
            claimingId={claimingId}
            claimPlace={claimPlace}
          />
        ) : null}

        {activePlacesTab === 'profile' ? (
          <ProfileTab
            selectedPlace={selectedPlace}
            profileName={profileName}
            setProfileName={setProfileName}
            profileCity={profileCity}
            setProfileCity={setProfileCity}
            profileAddress={profileAddress}
            setProfileAddress={setProfileAddress}
            profilePhone={profilePhone}
            setProfilePhone={setProfilePhone}
            profileWebsite={profileWebsite}
            setProfileWebsite={setProfileWebsite}
            profileDescription={profileDescription}
            setProfileDescription={setProfileDescription}
            saving={saving}
            saveProfile={saveProfile}
          />
        ) : null}

        {activePlacesTab === 'profile' ? (
          <MediaPanel
            selectedPlace={selectedPlace}
            selectedGalleryUrls={selectedGalleryUrls}
            coverUploading={coverUploading}
            galleryUploading={galleryUploading}
            coverInputId={coverInputId}
            coverReplaceId={coverReplaceId}
            galleryInputId={galleryInputId}
            handleCoverUpload={handleCoverUpload}
            handleGalleryUpload={handleGalleryUpload}
            removeGalleryImage={removeGalleryImage}
            savePlaceMedia={savePlaceMedia}
          />
        ) : null}

        {activePlacesTab === 'verification' ? (
          <VerificationTab
            selectedPlace={selectedPlace}
            selectedPlaceVerified={selectedPlaceVerified}
            canVerifyByPhone={canVerifyByPhone}
            otpTarget={otpTarget}
            otpCode={otpCode}
            setOtpCode={setOtpCode}
            otpConfirming={otpConfirming}
            otpSending={otpSending}
            confirmPhoneOtp={confirmPhoneOtp}
            sendPhoneOtp={sendPhoneOtp}
            verificationMethod={verificationMethod}
            setVerificationMethod={setVerificationMethod}
            verificationEmail={verificationEmail}
            setVerificationEmail={setVerificationEmail}
            verificationPhone={verificationPhone}
            setVerificationPhone={setVerificationPhone}
            verificationMapsUrl={verificationMapsUrl}
            setVerificationMapsUrl={setVerificationMapsUrl}
            verificationWebsiteUrl={verificationWebsiteUrl}
            setVerificationWebsiteUrl={setVerificationWebsiteUrl}
            verificationSocialUrl={verificationSocialUrl}
            setVerificationSocialUrl={setVerificationSocialUrl}
            verificationNotes={verificationNotes}
            setVerificationNotes={setVerificationNotes}
            verificationFile={verificationFile}
            setVerificationFile={setVerificationFile}
            saving={saving}
            requestVerification={requestVerification}
          />
        ) : null}

        {activePlacesTab === 'subscribers' ? (
          <SubscribersTab
            selectedPlace={selectedPlace}
            selectedPlaceVerified={selectedPlaceVerified}
            pushTitle={pushTitle}
            setPushTitle={setPushTitle}
            pushMessage={pushMessage}
            setPushMessage={setPushMessage}
            saving={saving}
            sendPlacePush={sendPlacePush}
          />
        ) : null}
      </section>

      <section className="content-grid">
        {activePlacesTab === 'menu' ? (
          <MenuTab
            sections={sections}
            items={items}
            selectedPlaceId={selectedPlaceId}
            saving={saving}
            sectionName={sectionName}
            setSectionName={setSectionName}
            sectionDescription={sectionDescription}
            setSectionDescription={setSectionDescription}
            createSection={createSection}
            itemSectionId={itemSectionId}
            setItemSectionId={setItemSectionId}
            itemName={itemName}
            setItemName={setItemName}
            itemPrice={itemPrice}
            setItemPrice={setItemPrice}
            itemDescription={itemDescription}
            setItemDescription={setItemDescription}
            itemFeatured={itemFeatured}
            setItemFeatured={setItemFeatured}
            createItem={createItem}
          />
        ) : null}

        {activePlacesTab === 'reservations' ? (
          <ReservationsTab
            selectedPlace={selectedPlace}
            reservationStatusFilter={reservationStatusFilter}
            setReservationStatusFilter={setReservationStatusFilter}
            visibleReservations={visibleReservations}
            changeReservationStatus={changeReservationStatus}
          />
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
