import {
  type DocumentData,
  type QueryDocumentSnapshot,
  Timestamp,
  collection,
  doc,
  getDoc,
  getDocs,
  limit,
  orderBy,
  query,
  serverTimestamp,
  setDoc,
  where,
} from 'firebase/firestore'
import { getDownloadURL, ref, uploadBytes } from 'firebase/storage'

import { db } from '../firebaseDb'
import { storage } from '../firebaseStorage'
import { DEFAULT_EVENT_CATEGORY_ID, categoryById, inferCategoryId } from './eventTaxonomy'
import type {
  OrganizerApplication,
  OverviewMetrics,
  PortalCampaign,
  PortalContact,
  PortalEvent,
  CreativeSession,
  PortalOrder,
  PortalPlace,
  PortalPlaceMenuItem,
  PortalPlaceMenuSection,
  PortalPlaceReservation,
  PortalTicketTier,
  WalletTransaction,
} from './types'

export async function uploadApplicationFile(
  userId: string,
  kind: 'logo' | 'government-id' | 'selfie',
  file: File,
) {
  const extension = file.name.split('.').pop() || 'bin'
  const storageRef = ref(
    storage,
    `organizer-applications/${userId}/${kind}-${Date.now()}.${extension}`,
  )
  await uploadBytes(storageRef, file)
  const downloadUrl = await getDownloadURL(storageRef)

  return {
    downloadUrl,
    fileName: file.name,
  }
}

export async function uploadEventCoverImage(eventId: string, file: File): Promise<string> {
  const extension = file.name.split('.').pop() || 'jpg'
  const storageRef = ref(storage, `event-covers/${eventId}/cover-${Date.now()}.${extension}`)
  await uploadBytes(storageRef, file)
  return getDownloadURL(storageRef)
}

export async function uploadPlaceVerificationFile(
  userId: string,
  placeId: string,
  file: File,
): Promise<string> {
  const extension = file.name.split('.').pop() || 'bin'
  const storageRef = ref(
    storage,
    `place-verifications/${userId}/${placeId}/proof-${Date.now()}.${extension}`,
  )
  await uploadBytes(storageRef, file)
  return getDownloadURL(storageRef)
}

/**
 * Upload a place cover or gallery image to Firebase Storage and return its
 * download URL. The backend only accepts Firebase Storage URLs for place media.
 */
export async function uploadPlaceMediaFile(
  placeId: string,
  kind: 'cover' | 'gallery',
  file: File,
): Promise<string> {
  const extension = file.name.split('.').pop() || 'jpg'
  const storageRef = ref(
    storage,
    `place-media/${placeId}/${kind}-${Date.now()}-${Math.random().toString(36).slice(2, 8)}.${extension}`,
  )
  await uploadBytes(storageRef, file)
  return getDownloadURL(storageRef)
}

export async function saveOrganizerApplicationDraft(
  userId: string,
  payload: OrganizerApplication,
) {
  const refDoc = doc(db, 'organizer_applications', userId)
  const organizationId = payload.organizationId || `org_${userId}`
  await setDoc(
    refDoc,
    {
      ...payload,
      userId,
      organizationId,
      status: 'active',
      updatedAt: serverTimestamp(),
      createdAt: serverTimestamp(),
    },
    { merge: true },
  )
  await setDoc(
    doc(db, 'users', userId),
    {
      defaultOrganizationId: organizationId,
      organizerApplicationStatus: 'active',
      organizerApplication: {
        status: 'active',
        updatedAt: serverTimestamp(),
      },
      updatedAt: serverTimestamp(),
    },
    { merge: true },
  )
}

export async function submitOrganizerApplication(
  userId: string,
  payload: OrganizerApplication,
) {
  const refDoc = doc(db, 'organizer_applications', userId)
  await setDoc(
    refDoc,
    {
      ...payload,
      userId,
      status: 'submitted',
      submittedAt: serverTimestamp(),
      updatedAt: serverTimestamp(),
      createdAt: serverTimestamp(),
    },
    { merge: true },
  )
  await setDoc(
    doc(db, 'users', userId),
    {
      organizerApplicationStatus: 'submitted',
      organizerApplication: {
        status: 'submitted',
        updatedAt: serverTimestamp(),
      },
      updatedAt: serverTimestamp(),
    },
    { merge: true },
  )
}

export function createEmptyEvent(seed?: Partial<PortalEvent>): PortalEvent {
  return {
    id: seed?.id ?? '',
    organizationId: seed?.organizationId ?? '',
    createdBy: seed?.createdBy ?? '',
    title: seed?.title ?? '',
    description: seed?.description ?? '',
    venue: seed?.venue ?? '',
    city: seed?.city ?? 'Accra',
    visibility: seed?.visibility ?? 'public',
    status: seed?.status ?? 'draft',
    timezone: seed?.timezone ?? 'Africa/Accra',
    startAt: seed?.startAt ?? new Date(Date.now() + 86400000).toISOString().slice(0, 16),
    endAt: seed?.endAt ?? '',
    coverImageUrl: seed?.coverImageUrl ?? '',
    performers: seed?.performers ?? '',
    djs: seed?.djs ?? '',
    mcs: seed?.mcs ?? '',
    categoryId: seed?.categoryId ?? DEFAULT_EVENT_CATEGORY_ID,
    mood: seed?.mood ?? 'night',
    tags: seed?.tags ?? [],
    allowSharing: seed?.allowSharing ?? true,
    sendPushNotification: seed?.sendPushNotification ?? true,
    sendSmsNotification: seed?.sendSmsNotification ?? true,
    ticketingEnabled: seed?.ticketingEnabled ?? true,
    requireTicket: seed?.requireTicket ?? false,
    currency: seed?.currency ?? 'GHS',
    tiers:
      seed?.tiers ??
      [
        {
          tierId: crypto.randomUUID(),
          name: 'General',
          price: 60,
          maxQuantity: 300,
          sold: 0,
          description: 'Standard access for the main event floor.',
        },
      ],
    likesCount: seed?.likesCount ?? 0,
    rsvpCount: seed?.rsvpCount ?? 0,
    ticketCount: seed?.ticketCount ?? 0,
    grossRevenue: seed?.grossRevenue ?? 0,
  }
}

function toTimestamp(value: string) {
  const date = new Date(value)
  return Timestamp.fromDate(date)
}

function dateString(value: unknown): string {
  if (value instanceof Timestamp) return value.toDate().toISOString()
  if (value && typeof (value as { toDate?: () => Date }).toDate === 'function') {
    return (value as { toDate: () => Date }).toDate().toISOString()
  }
  return typeof value === 'string' ? value : ''
}

function stringList(value: unknown): string[] {
  return Array.isArray(value) ? value.map(String).filter(Boolean) : []
}

function normalizeEvent(docId: string, data: Record<string, unknown>): PortalEvent {
  const ticketing = (data.ticketing as Record<string, unknown> | undefined) ?? {}
  const tiers = (ticketing.tiers as PortalTicketTier[] | undefined) ?? []
  const lineup = (data.lineup as Record<string, unknown> | undefined) ?? {}
  const distribution = (data.distribution as Record<string, unknown> | undefined) ?? {}
  const metrics = (data.metrics as Record<string, unknown> | undefined) ?? {}
  const tags = Array.isArray(data.tags) ? data.tags.map(String) : []
  const categoryId = inferCategoryId({
    categoryId: String(data.categoryId ?? ''),
    category: String(data.category ?? data.type ?? ''),
    title: String(data.title ?? ''),
    description: String(data.description ?? ''),
    mood: String(data.mood ?? ''),
    tags,
  })

  return {
    id: docId,
    organizationId: String(data.organizationId ?? ''),
    createdBy: String(data.createdBy ?? ''),
    title: String(data.title ?? ''),
    description: String(data.description ?? ''),
    venue: String(data.venue ?? ''),
    city: String(data.city ?? ''),
    visibility: data.visibility === 'private' ? 'private' : 'public',
    status:
      data.status === 'published' || data.status === 'cancelled'
        ? (data.status as 'published' | 'cancelled')
        : 'draft',
    timezone: String(data.timezone ?? 'Africa/Accra'),
    startAt:
      data.startAt instanceof Timestamp
        ? data.startAt.toDate().toISOString().slice(0, 16)
        : '',
    endAt:
      data.endAt instanceof Timestamp
        ? data.endAt.toDate().toISOString().slice(0, 16)
        : '',
    coverImageUrl: String(data.coverImageUrl ?? ''),
    performers: String(lineup.performers ?? ''),
    djs: String(lineup.djs ?? ''),
    mcs: String(lineup.mcs ?? ''),
    categoryId,
    mood: String(data.mood ?? 'night'),
    tags,
    allowSharing: distribution.allowSharing !== false,
    sendPushNotification: distribution.sendPushNotification !== false,
    sendSmsNotification: distribution.sendSmsNotification !== false,
    ticketingEnabled: ticketing.enabled !== false,
    requireTicket: ticketing.requireTicket === true,
    currency: String(ticketing.currency ?? 'GHS'),
    tiers: Array.isArray(tiers)
      ? tiers.map((tier) => ({
          tierId: String(tier.tierId),
          name: String(tier.name),
          price: Number(tier.price ?? 0),
          maxQuantity: Number(tier.maxQuantity ?? 0),
          sold: Number(tier.sold ?? 0),
          description: String(tier.description ?? ''),
        }))
      : [],
    likesCount: Number(metrics.likesCount ?? 0),
    rsvpCount: Number(metrics.rsvpCount ?? 0),
    ticketCount: Number(metrics.ticketCount ?? 0),
    grossRevenue: Number(metrics.grossRevenue ?? 0),
  }
}

function publicEventIsCurrent(event: PortalEvent) {
  const visibleUntil = event.endAt || event.startAt
  if (!visibleUntil) return false
  return new Date(visibleUntil).getTime() > Date.now()
}

export async function listOrganizerEvents(organizationId: string) {
  const snapshot = await getDocs(
    query(
      collection(db, 'events'),
      where('organizationId', '==', organizationId),
      orderBy('startAt', 'desc'),
    ),
  )
  return snapshot.docs.map((docSnap) => normalizeEvent(docSnap.id, docSnap.data()))
}

/** List events visible to attendees: public and published, soonest first. */
export async function listPublicEvents(limitCount = 50): Promise<PortalEvent[]> {
  const now = Timestamp.fromDate(new Date())
  const base = collection(db, 'events')
  const [upcoming, live] = await Promise.all([
    getDocs(
      query(
        base,
        where('visibility', '==', 'public'),
        where('status', '==', 'published'),
        where('startAt', '>=', now),
        orderBy('startAt', 'asc'),
        limit(limitCount),
      ),
    ),
    getDocs(
      query(
        base,
        where('visibility', '==', 'public'),
        where('status', '==', 'published'),
        where('endAt', '>=', now),
        orderBy('endAt', 'asc'),
        limit(limitCount),
      ),
    ).catch(() => null),
  ])
  const eventsById = new Map<string, PortalEvent>()
  for (const docSnap of [...upcoming.docs, ...(live?.docs ?? [])]) {
    const event = normalizeEvent(docSnap.id, docSnap.data())
    if (publicEventIsCurrent(event)) eventsById.set(event.id, event)
  }
  return [...eventsById.values()]
    .sort((a, b) => new Date(a.startAt).getTime() - new Date(b.startAt).getTime())
    .slice(0, limitCount)
}

/** Get a single event by id for public view; returns null if not public/published or not found. */
export async function getPublicEvent(eventId: string): Promise<PortalEvent | null> {
  const snapshot = await getDoc(doc(db, 'events', eventId))
  if (!snapshot.exists()) return null
  const data = snapshot.data()
  if (data?.visibility !== 'public' || data?.status !== 'published') return null
  const event = normalizeEvent(snapshot.id, data)
  return publicEventIsCurrent(event) ? event : null
}

function normalizeCampaign(docSnap: QueryDocumentSnapshot<DocumentData>): PortalCampaign {
  const d = docSnap.data()
  const createdAt = d.createdAt && typeof (d.createdAt as { toDate?: () => Date }).toDate === 'function'
    ? (d.createdAt as { toDate: () => Date }).toDate().toISOString()
    : typeof d.createdAt === 'string'
      ? d.createdAt
      : ''
  const scheduledAt = d.scheduledAt && typeof (d.scheduledAt as { toDate?: () => Date }).toDate === 'function'
    ? (d.scheduledAt as { toDate: () => Date }).toDate().toISOString()
    : typeof d.scheduledAt === 'string'
      ? d.scheduledAt
      : undefined
  return {
    id: docSnap.id,
    organizationId: String(d.organizationId ?? ''),
    eventId: String(d.eventId ?? ''),
    eventTitle: String(d.eventTitle ?? ''),
    name: String(d.name ?? ''),
    status: String(d.status ?? ''),
    channels: Array.isArray(d.channels) ? d.channels.map(String) : [],
    audienceSources: Array.isArray(d.audienceSources) ? d.audienceSources.map(String) : [],
    pushAudience: Number(d.pushAudience ?? 0),
    smsAudience: Number(d.smsAudience ?? 0),
    uploadedAudience: d.uploadedAudience != null ? Number(d.uploadedAudience) : undefined,
    walletReservationAmount: Number(d.walletReservationAmount ?? 0),
    totalSmsCharged: d.totalSmsCharged != null ? Number(d.totalSmsCharged) : undefined,
    totalPushCharged: d.totalPushCharged != null ? Number(d.totalPushCharged) : undefined,
    createdAt,
    scheduledAt,
  }
}

export async function listPublicPromotionCampaigns(max = 30): Promise<PortalCampaign[]> {
  const snapshot = await getDocs(
    query(
      collection(db, 'promotion_campaigns'),
      where('status', '==', 'live'),
      where('channels', 'array-contains-any', ['featured', 'announcement']),
      limit(max),
    ),
  )
  return snapshot.docs.map(normalizeCampaign)
}

export async function listOrganizerCampaigns(organizationId: string, max = 30): Promise<PortalCampaign[]> {
  const snapshot = await getDocs(
    query(
      collection(db, 'promotion_campaigns'),
      where('organizationId', '==', organizationId),
      orderBy('createdAt', 'desc'),
      limit(max),
    ),
  )
  return snapshot.docs.map(normalizeCampaign)
}

function normalizePlace(docSnap: QueryDocumentSnapshot<DocumentData>): PortalPlace {
  const d = docSnap.data()
  const metrics = (d.metrics as Record<string, unknown> | undefined) ?? {}
  return {
    id: docSnap.id,
    organizationId: String(d.organizationId ?? ''),
    ownerId: String(d.ownerId ?? d.createdBy ?? ''),
    name: String(d.name ?? 'Vennuzo place'),
    description: String(d.description ?? ''),
    city: String(d.city ?? 'Accra'),
    address: String(d.address ?? d.formattedAddress ?? d.addressText ?? ''),
    status: String(d.status ?? 'active'),
    verificationStatus: String(d.verificationStatus ?? 'unverified'),
    verified: d.verified === true || d.verificationStatus === 'verified',
    verifiablePhone: String(d.verifiablePhone ?? ''),
    latestVerificationRequestId: String(d.latestVerificationRequestId ?? ''),
    featured: d.featured === true,
    coverUrl: String(d.coverUrl ?? d.imageUrl ?? ''),
    logoUrl: String(d.logoUrl ?? d.avatarUrl ?? ''),
    galleryUrls: stringList(d.galleryUrls ?? d.gallery),
    mapsUrl: String(d.mapsUrl ?? d.googleMapsUrl ?? ''),
    googlePlaceId: String(d.googlePlaceId ?? ''),
    phone: String(d.phone ?? ''),
    website: String(d.website ?? ''),
    categories: stringList(d.categories),
    amenities: stringList(d.amenities),
    openingHours: stringList(d.openingHours ?? d.hours),
    subscriberCount: Number(metrics.subscriberCount ?? d.subscriberCount ?? 0),
    rating: Number(metrics.rating ?? d.rating ?? 0),
    reviewCount: Number(metrics.reviewCount ?? d.reviewCount ?? 0),
  }
}

export async function listOrganizerPlaces(organizationId: string): Promise<PortalPlace[]> {
  if (!organizationId) return []
  const snapshot = await getDocs(
    query(
      collection(db, 'places'),
      where('organizationId', '==', organizationId),
      orderBy('updatedAt', 'desc'),
      limit(100),
    ),
  )
  return snapshot.docs.map(normalizePlace)
}

export async function listPlaceMenuSections(placeId: string): Promise<PortalPlaceMenuSection[]> {
  if (!placeId) return []
  const snapshot = await getDocs(
    query(
      collection(db, 'place_menu_sections'),
      where('placeId', '==', placeId),
      orderBy('sortOrder', 'asc'),
      limit(100),
    ),
  )
  return snapshot.docs.map((docSnap) => {
    const d = docSnap.data()
    return {
      id: docSnap.id,
      placeId: String(d.placeId ?? ''),
      name: String(d.name ?? 'Menu'),
      description: String(d.description ?? ''),
      sortOrder: Number(d.sortOrder ?? 0),
      visible: d.visible !== false,
    }
  })
}

export async function listPlaceMenuItems(placeId: string): Promise<PortalPlaceMenuItem[]> {
  if (!placeId) return []
  const snapshot = await getDocs(
    query(
      collection(db, 'place_menu_items'),
      where('placeId', '==', placeId),
      orderBy('sortOrder', 'asc'),
      limit(500),
    ),
  )
  return snapshot.docs.map((docSnap) => {
    const d = docSnap.data()
    return {
      id: docSnap.id,
      placeId: String(d.placeId ?? ''),
      sectionId: String(d.sectionId ?? ''),
      name: String(d.name ?? 'Menu item'),
      description: String(d.description ?? ''),
      price: Number(d.price ?? 0),
      currency: String(d.currency ?? 'GHS'),
      imageUrl: String(d.imageUrl ?? ''),
      featured: d.featured === true,
      status: String(d.status ?? 'available'),
      sortOrder: Number(d.sortOrder ?? 0),
    }
  })
}

export async function listPlaceReservations(organizationId: string, placeId?: string): Promise<PortalPlaceReservation[]> {
  if (!organizationId) return []
  const snapshot = await getDocs(
    placeId
      ? query(
          collection(db, 'place_reservations'),
          where('organizationId', '==', organizationId),
          where('placeId', '==', placeId),
          orderBy('requestedAt', 'desc'),
          limit(500),
        )
      : query(
          collection(db, 'place_reservations'),
          where('organizationId', '==', organizationId),
          orderBy('requestedAt', 'desc'),
          limit(500),
        ),
  )
  return snapshot.docs.map((docSnap) => {
    const d = docSnap.data()
    return {
      id: docSnap.id,
      placeId: String(d.placeId ?? ''),
      placeName: String(d.placeName ?? ''),
      organizationId: String(d.organizationId ?? ''),
      userId: String(d.userId ?? ''),
      guestName: String(d.guestName ?? d.name ?? ''),
      phone: String(d.phone ?? ''),
      partySize: Number(d.partySize ?? 1),
      requestedAt: dateString(d.requestedAt),
      reservationType: String(d.reservationType ?? 'table'),
      status: String(d.status ?? 'pending'),
      note: String(d.note ?? ''),
      selectedMenuItemIds: stringList(d.selectedMenuItemIds),
      createdAt: dateString(d.createdAt),
    }
  })
}

export async function listWalletTransactions(walletId: string, max = 25): Promise<WalletTransaction[]> {
  if (!walletId) return []
  const snapshot = await getDocs(
    query(
      collection(db, 'wallet_transactions'),
      where('walletId', '==', walletId),
      orderBy('createdAt', 'desc'),
      limit(max),
    ),
  )
  return snapshot.docs.map((docSnap) => {
    const d = docSnap.data()
    const createdAt = d.createdAt && typeof (d.createdAt as { toDate?: () => Date }).toDate === 'function'
      ? (d.createdAt as { toDate: () => Date }).toDate().toISOString()
      : typeof d.createdAt === 'string'
        ? d.createdAt
        : ''
    return {
      id: docSnap.id,
      walletId: String(d.walletId ?? ''),
      type: (d.type as WalletTransaction['type']) || 'top_up',
      amount: Number(d.amount ?? 0),
      status: String(d.status ?? ''),
      createdAt,
      campaignId: d.campaignId != null ? String(d.campaignId) : undefined,
    }
  })
}

export async function listCreativeSessions(organizationId: string, max = 20): Promise<CreativeSession[]> {
  if (!organizationId) return []
  const snapshot = await getDocs(
    query(
      collection(db, 'flyer_sessions'),
      where('organizationId', '==', organizationId),
      orderBy('createdAt', 'desc'),
      limit(max),
    ),
  )
  return snapshot.docs.map((docSnap) => {
    const d = docSnap.data()
    const createdAt = d.createdAt && typeof (d.createdAt as { toDate?: () => Date }).toDate === 'function'
      ? (d.createdAt as { toDate: () => Date }).toDate().toISOString()
      : typeof d.createdAt === 'string'
        ? d.createdAt
        : ''
    return {
      id: docSnap.id,
      organizationId: String(d.organizationId ?? ''),
      serviceType: d.serviceType === 'table_package_flyer' ? 'table_package_flyer' : 'event_flyer',
      editMode: d.editMode != null ? String(d.editMode) : null,
      eventName: String(d.eventName ?? 'Creative asset'),
      imageUrl: String(d.imageUrl ?? d.downloadUrl ?? ''),
      postUrl: d.postUrl != null ? String(d.postUrl) : null,
      prompt: String(d.prompt ?? ''),
      priceChargedGhs: Number(d.priceChargedGhs ?? 0),
      minorEditsRemaining: d.minorEditsRemaining == null ? null : Number(d.minorEditsRemaining),
      redesignsRemaining: d.redesignsRemaining == null ? null : Number(d.redesignsRemaining),
      createdAt,
    }
  })
}

export async function getOrganizerEvent(eventId: string) {
  const snapshot = await getDoc(doc(db, 'events', eventId))
  if (!snapshot.exists()) {
    return null
  }
  return normalizeEvent(snapshot.id, snapshot.data())
}

export async function saveOrganizerEvent(input: PortalEvent) {
  const eventId = input.id || doc(collection(db, 'events')).id
  const eventRef = doc(db, 'events', eventId)
  const occurrenceRef = doc(db, 'event_occurrences', `${eventId}_primary`)
  const shareLinkRef = doc(db, 'share_links', eventId)
  const startAt = toTimestamp(input.startAt)
  const endAt = input.endAt ? toTimestamp(input.endAt) : null

  const payload = {
    organizationId: input.organizationId,
    createdBy: input.createdBy,
    title: input.title,
    description: input.description,
    venue: input.venue,
    city: input.city,
    country: 'Ghana',
    addressText: `${input.venue}, ${input.city}`,
    visibility: input.visibility,
    status: input.status,
    categoryId: input.categoryId,
    category: input.categoryId,
    categoryLabel: categoryById(input.categoryId).label,
    timezone: input.timezone,
    startAt,
    endAt,
    recurrence: {
      frequency: 'none',
      interval: 1,
      endType: 'never',
      endDate: null,
      endAfterOccurrences: null,
    },
    ticketing: {
      enabled: input.ticketingEnabled,
      requireTicket: input.requireTicket,
      currency: input.currency,
      tiers: input.tiers,
    },
    lineup: {
      performers: input.performers,
      djs: input.djs,
      mcs: input.mcs,
    },
    distribution: {
      allowSharing: input.allowSharing,
      sendPushNotification: input.sendPushNotification,
      sendSmsNotification: input.sendSmsNotification,
    },
    metrics: {
      likesCount: input.likesCount,
      rsvpCount: input.rsvpCount,
      ticketCount: input.ticketCount,
      grossRevenue: input.grossRevenue,
    },
    mood: input.mood,
    tags: input.tags,
    coverImageUrl: input.coverImageUrl || '',
    updatedAt: serverTimestamp(),
    createdAt: serverTimestamp(),
  }

  await setDoc(eventRef, payload, { merge: true })
  await setDoc(
    occurrenceRef,
    {
      eventId,
      organizationId: input.organizationId,
      seriesEventId: eventId,
      title: input.title,
      visibility: input.visibility,
      status: input.status,
      categoryId: input.categoryId,
      category: input.categoryId,
      categoryLabel: categoryById(input.categoryId).label,
      occurrenceStartAt: startAt,
      occurrenceEndAt: endAt,
      timezone: input.timezone,
      city: input.city,
      venue: input.venue,
      ticketingEnabled: input.ticketingEnabled,
      requireTicket: input.requireTicket,
      createdAt: serverTimestamp(),
      updatedAt: serverTimestamp(),
    },
    { merge: true },
  )

  await setDoc(
    shareLinkRef,
    {
      type: 'event',
      targetId: eventId,
      organizationId: input.organizationId,
      title: input.title,
      description: input.description,
      slug: input.title
        .toLowerCase()
        .replace(/[^a-z0-9]+/g, '-')
        .replace(/-{2,}/g, '-')
        .replace(/^-|-$/g, ''),
      requireTicket: input.requireTicket,
      status: input.allowSharing ? 'active' : 'disabled',
      createdBy: input.createdBy,
      createdAt: serverTimestamp(),
      updatedAt: serverTimestamp(),
    },
    { merge: true },
  )

  return eventId
}

export async function loadOverviewMetrics(
  organizationId: string,
): Promise<OverviewMetrics> {
  const [eventsSnap, ordersSnap, rsvpSnap] = await Promise.all([
    getDocs(
      query(
        collection(db, 'events'),
        where('organizationId', '==', organizationId),
        orderBy('startAt', 'desc'),
        limit(24),
      ),
    ),
    getDocs(
      query(
        collection(db, 'event_ticket_orders'),
        where('organizationId', '==', organizationId),
        orderBy('createdAt', 'desc'),
        limit(100),
      ),
    ),
    getDocs(
      query(
        collection(db, 'event_rsvps'),
        where('organizationId', '==', organizationId),
        orderBy('createdAt', 'desc'),
        limit(100),
      ),
    ),
  ])

  const events = eventsSnap.docs.map((docSnap) => docSnap.data())
  const liveEvents = events.filter((event) => event.status === 'published').length
  const draftEvents = events.filter((event) => event.status !== 'published').length
  const paidOrders = ordersSnap.docs.filter((docSnap) => {
    const status = String(docSnap.data().paymentStatus ?? '').replace(/_/g, '').toLowerCase()
    return ['paid', 'cashatgatepaid', 'complimentary'].includes(status)
  })

  const grossRevenue = paidOrders.reduce(
    (sum, docSnap) => sum + Number(docSnap.data().totalAmount ?? 0),
    0,
  )
  const ticketsIssued = paidOrders.reduce((sum, docSnap) => {
    const selectedTiers = (docSnap.data().selectedTiers as Array<{ quantity?: number }> | undefined) ?? []
    return (
      sum +
      selectedTiers.reduce((tierSum, tier) => tierSum + Number(tier.quantity ?? 0), 0)
    )
  }, 0)

  return {
    grossRevenue,
    paidOrders: paidOrders.length,
    totalRsvps: rsvpSnap.docs.length,
    liveEvents,
    draftEvents,
    ticketsIssued,
  }
}

export async function listOrganizerOrders(
  organizationId: string,
): Promise<PortalOrder[]> {
  const ordersSnap = await getDocs(
    query(
      collection(db, 'event_ticket_orders'),
      where('organizationId', '==', organizationId),
      orderBy('createdAt', 'desc'),
      limit(500),
    ),
  )
  const orders = ordersSnap.docs.map((docSnap) => {
    const d = docSnap.data()
    const selectedTiers =
      (d.selectedTiers as Array<{ quantity?: number }> | undefined) ?? []
    const ticketCount = selectedTiers.reduce(
      (sum, tier) => sum + Number(tier.quantity ?? 0),
      0,
    )
    const createdAt =
      d.createdAt instanceof Timestamp
        ? d.createdAt.toDate().toISOString()
        : typeof d.createdAt === 'string'
          ? d.createdAt
          : new Date().toISOString()
    return {
      id: docSnap.id,
      organizationId: String(d.organizationId ?? ''),
      eventId: String(d.eventId ?? ''),
      eventTitle: '',
      totalAmount: Number(d.totalAmount ?? 0),
      paymentStatus: String(d.paymentStatus ?? 'pending'),
      createdAt,
      buyerEmail: String(d.buyerEmail ?? d.payeeEmail ?? ''),
      buyerName: String(d.buyerName ?? d.payeeName ?? ''),
      buyerPhone: String(
        d.buyerPhone ??
          d.payeeMobileNumber ??
          (d.paymentDetails as { customerPhoneNumber?: unknown } | undefined)?.customerPhoneNumber ??
          '',
      ),
      marketingConsent: d.marketingConsent === true || d.buyerMarketingConsent === true,
      smsConsent: d.smsConsent === true || d.buyerSmsConsent === true,
      ticketCount,
    }
  })
  const eventIds = [...new Set(orders.map((o) => o.eventId).filter(Boolean))]
  const eventTitles: Record<string, string> = {}
  await Promise.all(
    eventIds.map(async (eventId) => {
      const snap = await getDoc(doc(db, 'events', eventId))
      eventTitles[eventId] = snap.exists()
        ? String(snap.data()?.title ?? 'Unknown event')
        : 'Unknown event'
    }),
  )
  return orders.map((o) => ({
    ...o,
    eventTitle: eventTitles[o.eventId] ?? 'Unknown event',
  }))
}

export async function listOrganizerContacts(
  organizationId: string,
): Promise<PortalContact[]> {
  const [orders, rsvpSnap, audienceSnap] = await Promise.all([
    listOrganizerOrders(organizationId),
    getDocs(
      query(
        collection(db, 'event_rsvps'),
        where('organizationId', '==', organizationId),
        orderBy('createdAt', 'desc'),
        limit(200),
      ),
    ),
    getDocs(
      query(
        collection(db, 'audience_contacts'),
        where('organizationId', '==', organizationId),
        limit(500),
      ),
    ),
  ])
  const contactsByKey = new Map<
    string,
    {
      email: string
      displayName: string
      phone: string
      userId?: string
      lastEventId: string
      lastEventTitle: string
      lastActivityAt: string
      orderCount: number
      rsvpCount: number
      totalSpent: number
      marketingConsent: boolean
      smsConsent: boolean
      tags: Set<string>
      notes: string
      sources: Set<'orders' | 'rsvps' | 'uploaded'>
      sourceNames: Set<string>
      events: PortalContact['events']
    }
  >()

  function toIsoDate(value: unknown): string {
    if (value instanceof Timestamp) return value.toDate().toISOString()
    if (typeof value === 'string') return value
    return new Date().toISOString()
  }

  function contactKey(input: { email?: string; phone?: string; userId?: string }) {
    const email = input.email?.trim().toLowerCase()
    if (email) return `email:${email}`
    const phone = input.phone?.replace(/\D/g, '')
    if (phone) return `phone:${phone}`
    const userId = input.userId?.trim()
    return userId ? `uid:${userId}` : null
  }

  function isPaidOrderStatus(value: string) {
    const normalized = value.replace(/_/g, '').toLowerCase()
    return ['paid', 'cashatgate', 'cashatgatepaid', 'complimentary', 'reserved'].includes(normalized)
  }

  function upsertContact(input: {
    key: string
    email?: string
    displayName?: string
    phone?: string
    userId?: string
    lastEventId: string
    lastEventTitle: string
    lastActivityAt: string
    orderCount?: number
    rsvpCount?: number
    totalSpent?: number
    marketingConsent?: boolean
    smsConsent?: boolean
    tags?: string[]
    notes?: string
    source: 'orders' | 'rsvps' | 'uploaded'
    sourceName?: string
    activity: PortalContact['events'][number]
  }) {
    const existing = contactsByKey.get(input.key)
    const isNewer =
      !existing || new Date(input.lastActivityAt) > new Date(existing.lastActivityAt)

    if (!existing) {
      contactsByKey.set(input.key, {
        email: input.email ?? '',
        displayName:
          input.displayName ??
          input.email?.split('@')[0] ??
          input.phone ??
          'Unknown contact',
        phone: input.phone ?? '',
        userId: input.userId,
        lastEventId: input.lastEventId,
        lastEventTitle: input.lastEventTitle,
        lastActivityAt: input.lastActivityAt,
        orderCount: input.orderCount ?? 0,
        rsvpCount: input.rsvpCount ?? 0,
        totalSpent: input.totalSpent ?? 0,
        marketingConsent: input.marketingConsent ?? input.source !== 'orders',
        smsConsent: input.smsConsent ?? false,
        tags: new Set(input.tags ?? []),
        notes: input.notes ?? '',
        sources: new Set([input.source]),
        sourceNames: new Set(input.sourceName ? [input.sourceName] : []),
        events: [input.activity],
      })
      return
    }

    if (!existing.email && input.email) existing.email = input.email
    if (!existing.phone && input.phone) existing.phone = input.phone
    if (!existing.userId && input.userId) existing.userId = input.userId
    if (
      (!existing.displayName || existing.displayName === 'Unknown contact') &&
      input.displayName
    ) {
      existing.displayName = input.displayName
    }
    existing.orderCount += input.orderCount ?? 0
    existing.rsvpCount += input.rsvpCount ?? 0
    existing.totalSpent += input.totalSpent ?? 0
    existing.marketingConsent = existing.marketingConsent || input.marketingConsent === true
    existing.smsConsent = existing.smsConsent || input.smsConsent === true
    for (const tag of input.tags ?? []) existing.tags.add(tag)
    if (input.notes && (!existing.notes || input.source === 'uploaded')) existing.notes = input.notes
    existing.sources.add(input.source)
    if (input.sourceName) existing.sourceNames.add(input.sourceName)
    existing.events.push(input.activity)
    if (isNewer) {
      existing.lastEventId = input.lastEventId
      existing.lastEventTitle = input.lastEventTitle
      existing.lastActivityAt = input.lastActivityAt
    }
  }

  for (const o of orders) {
    if (!isPaidOrderStatus(o.paymentStatus)) continue
    const email = (o.buyerEmail || '').trim().toLowerCase()
    const key = contactKey({ email, phone: o.buyerPhone })
    if (!key) continue
    upsertContact({
      key,
      email: o.buyerEmail || email,
      displayName: o.buyerName || email.split('@')[0],
      phone: o.buyerPhone,
      lastEventId: o.eventId,
      lastEventTitle: o.eventTitle,
      lastActivityAt: o.createdAt,
      orderCount: 1,
      totalSpent: o.totalAmount,
      marketingConsent: o.marketingConsent === true,
      smsConsent: o.smsConsent === true,
      source: 'orders',
      activity: {
        id: `order:${o.id}`,
        type: 'order',
        eventId: o.eventId,
        eventTitle: o.eventTitle,
        occurredAt: o.createdAt,
        amount: o.totalAmount,
      },
    })
  }

  for (const docSnap of rsvpSnap.docs) {
    const data = docSnap.data()
    const email = String(data.email ?? '').trim()
    const phone = String(data.phone ?? data.buyerPhone ?? '').trim()
    const userId = String(data.userId ?? data.uid ?? '').trim()
    const key = contactKey({ email, phone, userId })
    if (!key) continue
    upsertContact({
      key,
      email,
      displayName: String(data.name ?? data.fullName ?? '').trim(),
      phone,
      lastEventId: String(data.eventId ?? ''),
      lastEventTitle: String(data.eventTitle ?? 'Unknown event'),
      lastActivityAt: toIsoDate(data.createdAt ?? data.updatedAt),
      rsvpCount: 1,
      marketingConsent: data.marketingConsent === true,
      smsConsent: data.smsConsent === true,
      source: 'rsvps',
      activity: {
        id: `rsvp:${docSnap.id}`,
        type: 'rsvp',
        eventId: String(data.eventId ?? ''),
        eventTitle: String(data.eventTitle ?? 'Unknown event'),
        occurredAt: toIsoDate(data.createdAt ?? data.updatedAt),
      },
    })
  }

  for (const docSnap of audienceSnap.docs) {
    const data = docSnap.data()
    const email = String(data.email ?? data.emailLower ?? '').trim()
    const phone = String(data.phone ?? '').trim()
    const userId = String(data.userId ?? '').trim()
    const key = contactKey({ email, phone, userId })
    if (!key) continue
    const sourceName = String(data.sourceName ?? data.source ?? 'Uploaded list').trim()
    const importedAt = toIsoDate(data.lastImportedAt ?? data.updatedAt ?? data.createdAt)
    upsertContact({
      key,
      email,
      displayName: String(data.displayName ?? data.name ?? '').trim(),
      phone,
      userId,
      lastEventId: '',
      lastEventTitle: sourceName || 'Uploaded list',
      lastActivityAt: importedAt,
      marketingConsent: Boolean(data.marketingConsent),
      smsConsent: Boolean(data.smsConsent),
      tags: Array.isArray(data.tags) ? data.tags.map(String).filter(Boolean) : [],
      notes: String(data.notes ?? ''),
      source: 'uploaded',
      sourceName,
      activity: {
        id: `upload:${docSnap.id}`,
        type: 'upload',
        eventId: '',
        eventTitle: sourceName || 'Uploaded list',
        occurredAt: importedAt,
        sourceName,
      },
    })
  }

  return Array.from(contactsByKey.values())
    .map((contact) => ({
      ...contact,
      sources: Array.from(contact.sources),
      sourceNames: Array.from(contact.sourceNames),
      tags: Array.from(contact.tags),
      notes: contact.notes,
      events: contact.events
        .sort(
          (a, b) =>
            new Date(b.occurredAt).getTime() -
            new Date(a.occurredAt).getTime(),
        )
        .slice(0, 10),
    }))
    .sort(
      (a, b) =>
        new Date(b.lastActivityAt).getTime() -
        new Date(a.lastActivityAt).getTime(),
    )
}
