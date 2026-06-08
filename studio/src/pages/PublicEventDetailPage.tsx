import { useEffect, useMemo, useState, type FormEvent } from 'react'
import {
  ArrowLeft,
  ArrowRight,
  BadgeCheck,
  CalendarDays,
  Clock,
  Heart,
  MapPin,
  QrCode,
  Share2,
  ShieldCheck,
  Sparkles,
  Ticket,
  UsersRound,
} from 'lucide-react'
import { Link, useParams } from 'react-router-dom'
import { useSearchParams } from 'react-router-dom'
import { httpsCallable } from 'firebase/functions'

import { copy } from '../lib/copy'
import { trackEvent } from '../lib/analytics'
import { formatDateTime, formatMoney } from '../lib/formatters'
import { getPublicEvent } from '../lib/portalData'
import { functions } from '../firebaseFunctions'
import type { PortalEvent, PortalTicketTier } from '../lib/types'

function getPriceLabel(event: PortalEvent): string {
  if (!event.ticketingEnabled || event.tiers.length === 0) return 'RSVP'
  const min = Math.min(...event.tiers.map((tier) => tier.price))
  return min === 0 ? 'Free entry' : `From ${formatMoney(min)}`
}

function getTierAvailability(tier: PortalTicketTier): string {
  if (tier.maxQuantity <= 0) return 'Available'
  const remaining = Math.max(tier.maxQuantity - tier.sold, 0)
  return remaining > 0 ? `${remaining} spots left` : 'Sold out'
}

function getLineup(event: PortalEvent): string {
  return [event.performers, event.djs, event.mcs].filter(Boolean).join(' · ')
}

interface TablePackage {
  id: string
  name: string
  description: string
  priceGhs: number
  capacity: number
  quantity: number
  booked: number
  available: number | null
  items: string
  status: string
}

const submitPublicEventRsvp = httpsCallable<
  {
    eventId: string
    name: string
    phone: string
    email?: string
    guestCount: number
    wantsTable?: boolean
    partnerRef?: string
  },
  { success: boolean; rsvpId: string; created: boolean }
>(functions, 'submitPublicEventRsvp')

const submitPublicEventLike = httpsCallable<
  {
    eventId: string
    clientId: string
  },
  { success: boolean; likeId: string; created: boolean; likesCount: number }
>(functions, 'submitPublicEventLike')

const recordPartnerClick = httpsCallable<
  { eventId: string; refCode: string },
  { success: boolean }
>(functions, 'recordPartnerClick')

const listTablePackages = httpsCallable<
  { eventId: string },
  { success: boolean; packages: TablePackage[] }
>(functions, 'listTablePackages')

const createWebTablePackageBooking = httpsCallable<
  {
    eventId: string
    tablePackageId: string
    buyerName: string
    buyerPhone: string
    buyerEmail: string
    quantity: number
  },
  { success: boolean; bookingId: string; checkoutUrl?: string; status?: string }
>(functions, 'createWebTablePackageBooking')

export function PublicEventDetailPage() {
  const { eventId } = useParams()
  const [searchParams] = useSearchParams()
  const partnerRef = searchParams.get('ref') ?? ''
  const [event, setEvent] = useState<PortalEvent | null>(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [shareCopied, setShareCopied] = useState(false)
  const [liked, setLiked] = useState(false)
  const [likeSubmitting, setLikeSubmitting] = useState(false)
  const [rsvpName, setRsvpName] = useState('')
  const [rsvpPhone, setRsvpPhone] = useState('')
  const [rsvpEmail, setRsvpEmail] = useState('')
  const [rsvpGuestCount, setRsvpGuestCount] = useState(1)
  const [rsvpWantsTable, setRsvpWantsTable] = useState(false)
  const [rsvpSubmitting, setRsvpSubmitting] = useState(false)
  const [rsvpMessage, setRsvpMessage] = useState<string | null>(null)
  const [rsvpError, setRsvpError] = useState<string | null>(null)
  const [tablePackages, setTablePackages] = useState<TablePackage[]>([])
  const [selectedTablePackageId, setSelectedTablePackageId] = useState('')
  const [tableBuyerName, setTableBuyerName] = useState('')
  const [tableBuyerPhone, setTableBuyerPhone] = useState('')
  const [tableBuyerEmail, setTableBuyerEmail] = useState('')
  const [tableQuantity, setTableQuantity] = useState(1)
  const [tableSubmitting, setTableSubmitting] = useState(false)
  const [tableMessage, setTableMessage] = useState<string | null>(null)
  const [tableError, setTableError] = useState<string | null>(null)

  useEffect(() => {
    let cancelled = false

    async function loadEvent() {
      await Promise.resolve()
      if (cancelled) return

      setLoading(true)
      setError(null)
      setEvent(null)

      if (!eventId) {
        setLoading(false)
        setError('Event not found.')
        return
      }

      try {
        const e = await getPublicEvent(eventId)
        if (cancelled) return
        setEvent(e ?? null)
        if (e == null) setError('Event not found or no longer available.')
      } catch {
        if (!cancelled) setError('We could not load this event right now.')
      } finally {
        if (!cancelled) setLoading(false)
      }
    }

    void loadEvent()
    return () => { cancelled = true }
  }, [eventId])

  useEffect(() => {
    if (!eventId || !partnerRef) return
    void recordPartnerClick({ eventId, refCode: partnerRef }).catch(() => undefined)
  }, [eventId, partnerRef])

  useEffect(() => {
    if (!event) return
    void trackEvent('page_view', {
      event_id: event.id,
      source: partnerRef ? 'promoter_link' : searchParams.get('utm_source') || searchParams.get('source') || 'direct',
      ref: partnerRef || undefined,
      referrer: document.referrer || undefined,
    }, {
      area: 'public_events',
      organizationId: event.organizationId,
      path: `/events/${event.id}`,
      role: 'guest',
    })
  }, [event, partnerRef, searchParams])

  useEffect(() => {
    if (!eventId) {
      setLiked(false)
      return
    }
    try {
      setLiked(window.localStorage.getItem(`vennuzo:eventLiked:${eventId}`) === 'true')
    } catch {
      setLiked(false)
    }
  }, [eventId])

  useEffect(() => {
    let cancelled = false
    if (!eventId) return
    async function loadTables() {
      try {
        const result = await listTablePackages({ eventId: eventId ?? '' })
        if (cancelled) return
        const packages = result.data.packages.filter((item) => item.status === 'active')
        setTablePackages(packages)
        setSelectedTablePackageId((current) => current || packages[0]?.id || '')
      } catch {
        if (!cancelled) setTablePackages([])
      }
    }
    void loadTables()
    return () => {
      cancelled = true
    }
  }, [eventId])

  const detailStats = useMemo(() => {
    if (!event) return []
    const hasTicketStats = event.ticketingEnabled && event.tiers.length > 0
    return [
      ...(hasTicketStats
        ? [{ label: 'Tickets issued', value: event.ticketCount || 0, Icon: Ticket }]
        : []),
      { label: 'RSVPs', value: event.rsvpCount || 0, Icon: UsersRound },
      { label: 'Likes', value: event.likesCount || 0, Icon: Sparkles },
    ]
  }, [event])

  if (loading) {
    return <div className="page-loader">{copy.loading}</div>
  }

  if (error || !event) {
    return (
      <div className="public-page">
        <div className="empty-card">
          <h4>{error ?? 'Event not found'}</h4>
          <Link to="/events" className="button button--secondary" style={{ marginTop: '1rem' }}>
            <ArrowLeft size={15} />
            Back to events
          </Link>
        </div>
      </div>
    )
  }

  const hasTickets = event.ticketingEnabled && event.tiers.length > 0
  const analyticsEvent = event
  const lineup = getLineup(event)
  const primaryCtaLabel = hasTickets ? 'Get tickets' : 'RSVP'
  const checkoutUrl = `/checkout/${event.id}${partnerRef ? `?ref=${encodeURIComponent(partnerRef)}` : ''}`

  async function handleSubmitRsvp(e: FormEvent) {
    e.preventDefault()
    if (!eventId || rsvpSubmitting) return
    setRsvpSubmitting(true)
    setRsvpError(null)
    setRsvpMessage(null)
    try {
      await submitPublicEventRsvp({
        eventId,
        name: rsvpName.trim(),
        phone: rsvpPhone.trim(),
        email: rsvpEmail.trim() || undefined,
        guestCount: rsvpGuestCount,
        wantsTable: rsvpWantsTable,
        partnerRef: partnerRef || undefined,
      })
      void trackEvent('event_rsvp', {
        event_id: eventId,
        guest_count: rsvpGuestCount,
        wants_table: rsvpWantsTable,
        source: partnerRef ? 'promoter_link' : searchParams.get('utm_source') || searchParams.get('source') || 'direct',
        ref: partnerRef || undefined,
      }, {
        area: 'public_events',
        organizationId: analyticsEvent.organizationId,
        path: `/events/${eventId}`,
        role: 'guest',
      })
      setRsvpMessage('You are on the list. Keep an eye out for event updates from the organizer.')
      setRsvpName('')
      setRsvpPhone('')
      setRsvpEmail('')
      setRsvpGuestCount(1)
      setRsvpWantsTable(false)
    } catch (err) {
      setRsvpError(err instanceof Error ? err.message : 'We could not save your RSVP. Please try again.')
    } finally {
      setRsvpSubmitting(false)
    }
  }

  async function handleBookTable(e: FormEvent) {
    e.preventDefault()
    if (!eventId || !selectedTablePackageId || tableSubmitting) return
    setTableSubmitting(true)
    setTableError(null)
    setTableMessage(null)
    try {
      const result = await createWebTablePackageBooking({
        eventId,
        tablePackageId: selectedTablePackageId,
        buyerName: tableBuyerName.trim(),
        buyerPhone: tableBuyerPhone.trim(),
        buyerEmail: tableBuyerEmail.trim(),
        quantity: tableQuantity,
      })
      if (result.data.checkoutUrl) {
        window.location.href = result.data.checkoutUrl
        return
      }
      setTableMessage('Your table request is in. We will guide you through the next step if payment is needed.')
      setTableBuyerName('')
      setTableBuyerPhone('')
      setTableBuyerEmail('')
      setTableQuantity(1)
    } catch (err) {
      setTableError(err instanceof Error ? err.message : 'We could not reserve that table package. Please try again.')
    } finally {
      setTableSubmitting(false)
    }
  }

  function getPublicLikeClientId() {
    try {
      const key = 'vennuzo:publicLikeClientId'
      const existing = window.localStorage.getItem(key)
      if (existing && existing.length >= 8) return existing
      const next = window.crypto?.randomUUID?.() ?? `web_${Date.now()}_${Math.random().toString(16).slice(2)}`
      window.localStorage.setItem(key, next)
      return next
    } catch {
      return `web_${Date.now()}_${Math.random().toString(16).slice(2)}`
    }
  }

  async function handleLikeEvent() {
    if (!eventId || liked || likeSubmitting) return
    setLikeSubmitting(true)
    setLiked(true)
    try {
      const result = await submitPublicEventLike({
        eventId,
        clientId: getPublicLikeClientId(),
      })
      setEvent((current) => current
        ? { ...current, likesCount: result.data.likesCount }
        : current)
      void trackEvent('event_saved', {
        event_id: eventId,
        source: partnerRef ? 'promoter_link' : searchParams.get('utm_source') || searchParams.get('source') || 'direct',
      }, {
        area: 'public_events',
        organizationId: analyticsEvent.organizationId,
        path: `/events/${eventId}`,
        role: 'guest',
      })
      try {
        window.localStorage.setItem(`vennuzo:eventLiked:${eventId}`, 'true')
      } catch {
        // Liking still succeeded; persistence is only a local duplicate guard.
      }
    } catch {
      setLiked(false)
    } finally {
      setLikeSubmitting(false)
    }
  }

  async function handleShareEvent(sharedEvent: PortalEvent) {
    const url = `${window.location.origin}/events/${encodeURIComponent(sharedEvent.id)}`
    const payload = {
      title: sharedEvent.title,
      text: sharedEvent.description || `View ${sharedEvent.title} on Vennuzo.`,
      url,
    }

    try {
      if (navigator.share) {
        await navigator.share(payload)
        void trackEvent('event_shared', {
          event_id: sharedEvent.id,
          source: 'native_share',
          ref: partnerRef || undefined,
        }, {
          area: 'public_events',
          organizationId: sharedEvent.organizationId,
          path: `/events/${sharedEvent.id}`,
          role: 'guest',
        })
        return
      }
      await navigator.clipboard.writeText(url)
      void trackEvent('event_shared', {
        event_id: sharedEvent.id,
        source: 'copy_link',
        ref: partnerRef || undefined,
      }, {
        area: 'public_events',
        organizationId: sharedEvent.organizationId,
        path: `/events/${sharedEvent.id}`,
        role: 'guest',
      })
      setShareCopied(true)
      window.setTimeout(() => setShareCopied(false), 2200)
    } catch (err) {
      const name = err instanceof DOMException ? err.name : ''
      if (name === 'AbortError') return
      try {
        await navigator.clipboard.writeText(url)
        setShareCopied(true)
        window.setTimeout(() => setShareCopied(false), 2200)
      } catch {
        setShareCopied(false)
      }
    }
  }

  return (
    <div className="public-page public-page--detail">
      <article className="public-event-detail public-event-detail--premium">
        <Link to="/events" className="public-event-detail__back">
          <ArrowLeft size={15} />
          Back to events
        </Link>

        <section className="public-event-detail__hero">
          <div className={`public-event-detail__media ${event.coverImageUrl ? '' : 'public-event-detail__media--fallback'}`}>
            {event.coverImageUrl ? (
              <img src={event.coverImageUrl} alt={event.title} />
            ) : (
              <img src="/logo-mark.png" alt="" />
            )}
          </div>
          <div className="public-event-detail__hero-copy">
            <span className="home-hero__badge">
              <BadgeCheck size={15} />
              Verified Vennuzo event
            </span>
            <h1>{event.title}</h1>
            <div className="public-event-detail__hero-meta">
              <span>
                <CalendarDays size={15} />
                {formatDateTime(event.startAt)}
              </span>
              {event.endAt && (
                <span>
                  <Clock size={15} />
                  Ends {formatDateTime(event.endAt)}
                </span>
              )}
              <span>
                <MapPin size={15} />
                {event.venue}, {event.city}
              </span>
            </div>
            <div className="public-event-detail__hero-actions">
              {hasTickets ? (
                <Link to={checkoutUrl} className="button button--primary">
                  Book tickets
                  <ArrowRight size={16} />
                </Link>
              ) : (
                <a href="#event-rsvp" className="button button--primary">
                  {primaryCtaLabel}
                  <ArrowRight size={16} />
                </a>
              )}
              <button
                type="button"
                className="button button--ghost"
                onClick={() => { void handleShareEvent(event) }}
              >
                <Share2 size={16} />
                {shareCopied ? 'Link copied' : 'Share event'}
              </button>
              <button
                type="button"
                className={`button button--ghost public-event-detail__like${liked ? ' public-event-detail__like--active' : ''}`}
                aria-pressed={liked}
                disabled={liked || likeSubmitting}
                onClick={() => { void handleLikeEvent() }}
              >
                <Heart size={16} />
                {liked ? 'Liked by you' : likeSubmitting ? 'Liking...' : 'Like'}
              </button>
              <span>{getPriceLabel(event)}</span>
            </div>
          </div>
        </section>

        <div className="public-event-detail__layout">
          <main className="public-event-detail__main">
            <section className="public-event-detail__trust">
              <div>
                <ShieldCheck size={18} />
                <div>
                  <strong>Trusted event page</strong>
                  <span>Published through Vennuzo with clear event details and checkout tools.</span>
                </div>
              </div>
              <div>
                {hasTickets ? <QrCode size={18} /> : <UsersRound size={18} />}
                <div>
                  <strong>Smoother entry</strong>
                  <span>
                    {hasTickets
                      ? 'QR tickets help guests move through the door faster.'
                      : 'RSVPs keep the guest list clear before the event starts.'}
                  </span>
                </div>
              </div>
            </section>

            <section className="public-event-detail__section">
              <p className="eyebrow">About this event</p>
              <h2>What to expect</h2>
              <p>{event.description || 'More event details will be shared by the organizer soon.'}</p>
            </section>

            {lineup && (
              <section className="public-event-detail__section">
                <p className="eyebrow">Lineup</p>
                <h2>On the bill</h2>
                <p>{lineup}</p>
              </section>
            )}

            {event.tags.length > 0 && (
              <section className="public-event-detail__section">
                <p className="eyebrow">Tags</p>
                <div className="public-event-detail__tags">
                  {event.tags.map((tag) => (
                    <span key={tag} className="public-event-detail__tag">{tag}</span>
                  ))}
                </div>
              </section>
            )}
          </main>

          <aside className="public-event-detail__ticket-panel" aria-label={hasTickets ? 'Ticket checkout' : 'Event RSVP'}>
            <div className="public-event-detail__ticket-card">
              <div className="public-event-detail__ticket-card-header">
                <span>Your entry</span>
                <strong>{getPriceLabel(event)}</strong>
              </div>
              <div className="public-event-detail__quick-meta">
                <span>
                  <CalendarDays size={14} />
                  {formatDateTime(event.startAt)}
                </span>
                <span>
                  <MapPin size={14} />
                  {event.city}
                </span>
              </div>

              {hasTickets ? (
                <ul className="public-event-detail__tiers">
                  {event.tiers.map((tier) => (
                    <li key={tier.tierId}>
                      <div className="public-event-detail__tier-info">
                        <span className="public-event-detail__tier-name">{tier.name}</span>
                        {tier.description && (
                          <span className="public-event-detail__tier-desc">{tier.description}</span>
                        )}
                      </div>
                      <div className="public-event-detail__tier-right">
                        <span className="public-event-detail__tier-price">
                          {tier.price === 0 ? 'Free' : formatMoney(tier.price)}
                        </span>
                        <span className="public-event-detail__tier-avail">
                          {getTierAvailability(tier)}
                        </span>
                      </div>
                    </li>
                  ))}
                </ul>
              ) : (
                <p className="public-event-detail__ticket-note">
                  This event is RSVP-based. Save your spot and the organizer will handle the guest list.
                </p>
              )}

              {hasTickets ? (
                <Link
                  to={checkoutUrl}
                  className="button button--primary public-event-detail__get-tickets"
                >
                  Book tickets
                  <ArrowRight size={16} />
                </Link>
              ) : (
                <form className="checkout__form" id="event-rsvp" onSubmit={handleSubmitRsvp}>
                  <label className="checkout__label">
                    Full name
                    <input className="checkout__input" onChange={(e) => setRsvpName(e.target.value)} required value={rsvpName} />
                  </label>
                  <label className="checkout__label">
                    Phone number
                    <input className="checkout__input" onChange={(e) => setRsvpPhone(e.target.value)} required type="tel" value={rsvpPhone} />
                  </label>
                  <label className="checkout__label">
                    Email
                    <input className="checkout__input" onChange={(e) => setRsvpEmail(e.target.value)} type="email" value={rsvpEmail} />
                  </label>
                  <label className="checkout__label">
                    Guests
                    <input className="checkout__input" min={1} max={20} onChange={(e) => setRsvpGuestCount(Number(e.target.value || 1))} type="number" value={rsvpGuestCount} />
                  </label>
                  <label className="checkout__label" style={{ alignItems: 'center', display: 'flex', flexDirection: 'row', gap: '0.55rem' }}>
                    <input checked={rsvpWantsTable} onChange={(e) => setRsvpWantsTable(e.target.checked)} type="checkbox" />
                    I am interested in a table
                  </label>
                  {rsvpError && <p className="checkout__error" role="alert">{rsvpError}</p>}
                  {rsvpMessage && <p className="checkout__info">{rsvpMessage}</p>}
                  <button className="button button--primary public-event-detail__get-tickets" disabled={rsvpSubmitting || !rsvpName.trim() || !rsvpPhone.trim()} type="submit">
                    {rsvpSubmitting ? 'Submitting…' : primaryCtaLabel}
                    <ArrowRight size={16} />
                  </button>
                </form>
              )}

              {tablePackages.length > 0 && (
                <div className="public-event-detail__section" style={{ padding: 0 }}>
                  <p className="eyebrow">Tables</p>
                  <form className="checkout__form" onSubmit={handleBookTable}>
                    <label className="checkout__label">
                      Package
                      <select className="checkout__input" onChange={(e) => setSelectedTablePackageId(e.target.value)} value={selectedTablePackageId}>
                        {tablePackages.map((item) => (
                          <option key={item.id} value={item.id}>
                            {item.name} · {formatMoney(item.priceGhs)}
                          </option>
                        ))}
                      </select>
                    </label>
                    {selectedTablePackageId && (
                      <p className="public-event-detail__ticket-note">
                        {tablePackages.find((item) => item.id === selectedTablePackageId)?.description ||
                          tablePackages.find((item) => item.id === selectedTablePackageId)?.items ||
                          'Choose a table package and we will help you reserve it for this event.'}
                      </p>
                    )}
                    <label className="checkout__label">
                      Full name
                      <input className="checkout__input" onChange={(e) => setTableBuyerName(e.target.value)} required value={tableBuyerName} />
                    </label>
                    <label className="checkout__label">
                      Phone number
                      <input className="checkout__input" onChange={(e) => setTableBuyerPhone(e.target.value)} required type="tel" value={tableBuyerPhone} />
                    </label>
                    <label className="checkout__label">
                      Email
                      <input className="checkout__input" onChange={(e) => setTableBuyerEmail(e.target.value)} required type="email" value={tableBuyerEmail} />
                    </label>
                    <label className="checkout__label">
                      Quantity
                      <input className="checkout__input" min={1} max={10} onChange={(e) => setTableQuantity(Number(e.target.value || 1))} type="number" value={tableQuantity} />
                    </label>
                    {tableError && <p className="checkout__error" role="alert">{tableError}</p>}
                    {tableMessage && <p className="checkout__info">{tableMessage}</p>}
                    <button className="button button--secondary public-event-detail__get-tickets" disabled={tableSubmitting || !selectedTablePackageId || !tableBuyerName.trim() || !tableBuyerPhone.trim() || !tableBuyerEmail.trim()} type="submit">
                      {tableSubmitting ? 'Opening...' : 'Reserve a table'}
                    </button>
                  </form>
                </div>
              )}

              <div className="public-event-detail__stats">
                {detailStats.map(({ label, value, Icon }) => (
                  <span key={label}>
                    <Icon size={14} />
                    <strong>{value}</strong>
                    {label}
                  </span>
                ))}
              </div>
              {liked && (
                <div className="public-event-detail__liked-confirmation" role="status">
                  <Heart size={16} />
                  <div>
                    <strong>Liked by you</strong>
                    <span>This event is saved in your likes on this device.</span>
                  </div>
                </div>
              )}
            </div>
          </aside>
        </div>

        <div className="public-event-detail__mobile-bar">
          <div>
            <span>{getPriceLabel(event)}</span>
            <strong>{event.title}</strong>
          </div>
          {hasTickets ? (
            <Link to={`/checkout/${event.id}`} className="button button--primary">
              Book tickets
            </Link>
          ) : (
            <a
              href={`https://vennuzo.page.link/event/${event.id}`}
              target="_blank"
              rel="noopener noreferrer"
              className="button button--primary"
            >
              RSVP
            </a>
          )}
        </div>
      </article>
    </div>
  )
}
