import {
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
import type {
  OrganizerApplication,
  OverviewMetrics,
  PortalCampaign,
  PortalContact,
  PortalEvent,
  PortalOrder,
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

function normalizeEvent(docId: string, data: Record<string, unknown>): PortalEvent {
  const ticketing = (data.ticketing as Record<string, unknown> | undefined) ?? {}
  const tiers = (ticketing.tiers as PortalTicketTier[] | undefined) ?? []
  const lineup = (data.lineup as Record<string, unknown> | undefined) ?? {}
  const distribution = (data.distribution as Record<string, unknown> | undefined) ?? {}
  const metrics = (data.metrics as Record<string, unknown> | undefined) ?? {}

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
    mood: String(data.mood ?? 'night'),
    tags: Array.isArray(data.tags) ? data.tags.map(String) : [],
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
  const snapshot = await getDocs(
    query(
      collection(db, 'events'),
      where('visibility', '==', 'public'),
      where('status', '==', 'published'),
      orderBy('startAt', 'asc'),
      limit(limitCount),
    ),
  )
  return snapshot.docs.map((docSnap) => normalizeEvent(docSnap.id, docSnap.data()))
}

/** Get a single event by id for public view; returns null if not public/published or not found. */
export async function getPublicEvent(eventId: string): Promise<PortalEvent | null> {
  const snapshot = await getDoc(doc(db, 'events', eventId))
  if (!snapshot.exists()) return null
  const data = snapshot.data()
  if (data?.visibility !== 'public' || data?.status !== 'published') return null
  return normalizeEvent(snapshot.id, data)
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
  return snapshot.docs.map((docSnap) => {
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
      channels: Array.isArray(d.channels) ? d.channels : [],
      pushAudience: Number(d.pushAudience ?? 0),
      smsAudience: Number(d.smsAudience ?? 0),
      walletReservationAmount: Number(d.walletReservationAmount ?? 0),
      totalSmsCharged: d.totalSmsCharged != null ? Number(d.totalSmsCharged) : undefined,
      createdAt,
      scheduledAt,
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
      limit(100),
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
  const orders = await listOrganizerOrders(organizationId)
  const byEmail = new Map<
    string,
    {
      email: string
      displayName: string
      phone: string
      lastEventId: string
      lastEventTitle: string
      lastActivityAt: string
      orderCount: number
      totalSpent: number
    }
  >()
  for (const o of orders) {
    const email = (o.buyerEmail || '').trim().toLowerCase()
    if (!email) continue
    const existing = byEmail.get(email)
    const at = o.createdAt
    const isNewer =
      !existing || new Date(at) > new Date(existing.lastActivityAt)
    if (!existing) {
      byEmail.set(email, {
        email: o.buyerEmail || email,
        displayName: email.split('@')[0] || '—',
        phone: '',
        lastEventId: o.eventId,
        lastEventTitle: o.eventTitle,
        lastActivityAt: at,
        orderCount: 1,
        totalSpent: o.totalAmount,
      })
    } else {
      existing.orderCount += 1
      existing.totalSpent += o.totalAmount
      if (isNewer) {
        existing.lastEventId = o.eventId
        existing.lastEventTitle = o.eventTitle
        existing.lastActivityAt = at
      }
    }
  }
  return Array.from(byEmail.values())
    .map((c) => ({
      ...c,
      rsvpCount: 0,
    }))
    .sort(
      (a, b) =>
        new Date(b.lastActivityAt).getTime() -
        new Date(a.lastActivityAt).getTime(),
    )
}
