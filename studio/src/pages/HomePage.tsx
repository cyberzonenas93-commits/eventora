import { type CSSProperties, type FormEvent, useEffect, useMemo, useState } from 'react'
import {
  ArrowRight,
  BadgeCheck,
  CalendarDays,
  ClipboardCheck,
  CreditCard,
  MapPin,
  Megaphone,
  QrCode,
  Search,
  ShieldCheck,
  Sparkles,
  Ticket,
  UsersRound,
  WalletCards,
  Zap,
} from 'lucide-react'
import { Link, useNavigate } from 'react-router-dom'

import { copy } from '../lib/copy'
import { formatDateTime } from '../lib/formatters'
import {
  getDateParts,
  getDemandLabel,
  getPriceLabel,
  getTicketAvailability,
} from '../lib/eventCardHelpers'
import { EVENT_CATEGORIES } from '../lib/eventTaxonomy'
import { listPublicEvents, listPublicPromotionCampaigns } from '../lib/portalData'
import type { PortalCampaign, PortalEvent } from '../lib/types'

const HERO_SLIDE_DURATION_MS = 5000
const FEATURED_COUNT = 6
const UPCOMING_GRID_COUNT = 8

function getEventGradientIndex(id: string): number {
  let n = 0
  for (let i = 0; i < id.length; i++) n += id.charCodeAt(i)
  return n % 6
}

function ticketSalesFor(event: PortalEvent): number {
  const tierSales = event.tiers.reduce((sum, tier) => sum + Math.max(tier.sold, 0), 0)
  return Math.max(event.ticketCount, tierSales)
}

function campaignWeightForEvent(eventId: string, campaigns: PortalCampaign[]): number {
  return campaigns
    .filter((campaign) => campaign.eventId === eventId && campaign.status === 'live')
    .reduce((weight, campaign) => {
      let next = weight
      if (campaign.channels.includes('announcement')) next += 90000
      if (campaign.channels.includes('featured')) next += 65000
      if (campaign.channels.includes('push')) next += 18000
      if (campaign.channels.includes('sms')) next += 18000
      if (campaign.channels.includes('sharelink') || campaign.channels.includes('shareLink')) next += 5000
      next += Math.min(Math.max(campaign.walletReservationAmount || 0, 0), 5000)
      return next
    }, 0)
}

function spotlightScore(event: PortalEvent, campaigns: PortalCampaign[]): number {
  const sales = ticketSalesFor(event)
  const revenue = event.tiers.reduce((sum, tier) => sum + Math.max(tier.sold, 0) * Math.max(tier.price, 0), 0)
  return campaignWeightForEvent(event.id, campaigns) +
    sales * 140 +
    Math.min(revenue, 20000) +
    event.rsvpCount * 35 +
    event.likesCount * 10
}

function rankedSpotlightEvents(events: PortalEvent[], campaigns: PortalCampaign[]): PortalEvent[] {
  return [...events].sort((a, b) => {
    const scoreCompare = spotlightScore(b, campaigns) - spotlightScore(a, campaigns)
    if (scoreCompare !== 0) return scoreCompare
    return new Date(a.startAt).getTime() - new Date(b.startAt).getTime()
  })
}

function getSpotlightLabel(event: PortalEvent, campaigns: PortalCampaign[]): string {
  if (campaignWeightForEvent(event.id, campaigns) > 0) return 'Promoted event'
  if (ticketSalesFor(event) >= 50) return 'Top selling'
  if (event.rsvpCount + event.likesCount >= 150) return 'Popular now'
  return getDemandLabel(event)
}

function eventSearchUrl(categoryId: string): string {
  return `/events?category=${encodeURIComponent(categoryId)}`
}

export function HomePage() {
  const navigate = useNavigate()
  const [events, setEvents] = useState<PortalEvent[]>([])
  const [promotionCampaigns, setPromotionCampaigns] = useState<PortalCampaign[]>([])
  const [loading, setLoading] = useState(true)
  const [heroIndex, setHeroIndex] = useState(0)
  const [heroQuery, setHeroQuery] = useState('')

  useEffect(() => {
    let cancelled = false
    Promise.all([
      listPublicEvents(80),
      listPublicPromotionCampaigns().catch(() => [] as PortalCampaign[]),
    ])
      .then(([list, campaigns]) => {
        if (!cancelled) {
          setEvents(list)
          setPromotionCampaigns(campaigns)
        }
      })
      .finally(() => {
        if (!cancelled) setLoading(false)
      })
    return () => { cancelled = true }
  }, [])

  const rankedEvents = useMemo(
    () => rankedSpotlightEvents(events, promotionCampaigns),
    [events, promotionCampaigns],
  )
  const heroSlides = rankedEvents.slice(0, 3)
  const featuredEvents = rankedEvents.slice(0, FEATURED_COUNT)
  const upcomingEvents = events.slice(0, UPCOMING_GRID_COUNT)
  const spotlightEvent = heroSlides[heroIndex] ?? rankedEvents[0] ?? null
  const hasAnyEvents = events.length > 0

  const marketStats = useMemo(() => {
    const cityCount = new Set(events.map((event) => event.city).filter(Boolean)).size
    const ticketsIssued = events.reduce((sum, event) => sum + event.ticketCount, 0)
    const audienceSignals = events.reduce((sum, event) => sum + event.rsvpCount + event.likesCount, 0)

    return [
      { label: 'Events to explore', value: loading ? '...' : `${events.length || 'New'}`, Icon: Sparkles },
      { label: cityCount > 1 ? 'Cities to discover' : 'Made for Ghana', value: cityCount > 1 ? `${cityCount}` : 'GH', Icon: MapPin },
      { label: ticketsIssued > 0 ? 'Tickets booked' : 'Easy checkout', value: ticketsIssued > 0 ? `${ticketsIssued}` : 'Live', Icon: Ticket },
      { label: audienceSignals > 0 ? 'People interested' : 'Fast entry', value: audienceSignals > 0 ? `${audienceSignals}` : 'Ready', Icon: QrCode },
    ]
  }, [events, loading])

  useEffect(() => {
    if (heroSlides.length < 2) return
    const t = setInterval(() => {
      setHeroIndex((i) => (i + 1) % heroSlides.length)
    }, HERO_SLIDE_DURATION_MS)
    return () => clearInterval(t)
  }, [heroSlides.length])

  useEffect(() => {
    const root = document.querySelector('.public-home--premium')
    if (!root) return
    const els = Array.from(root.querySelectorAll<HTMLElement>('.reveal:not(.in-view)'))
    if (
      typeof IntersectionObserver === 'undefined' ||
      window.matchMedia('(prefers-reduced-motion: reduce)').matches
    ) {
      els.forEach((el) => el.classList.add('in-view'))
      return
    }
    const io = new IntersectionObserver(
      (entries) => {
        entries.forEach((entry) => {
          if (entry.isIntersecting) {
            entry.target.classList.add('in-view')
            io.unobserve(entry.target)
          }
        })
      },
      { rootMargin: '0px 0px -8% 0px', threshold: 0.05 },
    )
    els.forEach((el) => io.observe(el))
    return () => io.disconnect()
  }, [loading, events])

  function handleHeroSearch(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()
    const q = heroQuery.trim()
    navigate(q ? `/events?q=${encodeURIComponent(q)}` : '/events')
  }

  return (
    <div className="public-home public-home--premium">
      <section className="home-hero home-hero--marketplace" aria-label="Vennuzo marketplace">
        <div className="home-hero__inner">
          <div className="home-hero__marketplace">
            <div className="home-hero__copy">
              <div className="home-hero__photo" aria-hidden="true">
                <img src="/visuals/visual_explore_spotlight.jpg" alt="" fetchPriority="high" />
              </div>
              <div className="home-hero__photo-scrim" aria-hidden="true" />
              <span className="home-hero__badge anim" style={{ animationDelay: '0.05s' }}>
                <Sparkles size={15} />
                Your guide to what is happening
              </span>
              <h1 className="anim" style={{ animationDelay: '0.15s' }}>Find your next night out. Sell out your next event.</h1>
              <p className="home-hero__sub anim" style={{ animationDelay: '0.26s' }}>
                Discover standout events across Ghana, book in minutes, and give guests a smoother
                way to pay, share, and check in.
              </p>

              <form className="home-hero__search anim" style={{ animationDelay: '0.38s' }} onSubmit={handleHeroSearch}>
                <Search size={18} aria-hidden="true" />
                <input
                  type="search"
                  value={heroQuery}
                  onChange={(event) => setHeroQuery(event.target.value)}
                  placeholder="Search by event, venue, or city"
                  aria-label="Search events"
                />
                <button type="submit">Search</button>
              </form>

              <div className="hero-chip-row home-hero__actions anim" style={{ animationDelay: '0.48s' }}>
                <Link to="/events" className="button button--primary">
                  Explore events
                  <ArrowRight size={16} />
                </Link>
                <Link to="/studio" className="button button--secondary">
                  Start selling today
                </Link>
              </div>

              <div className="home-hero__stats anim" style={{ animationDelay: '0.58s' }} aria-label="Marketplace highlights">
                {marketStats.map(({ label, value, Icon }) => (
                  <div className="home-hero__stat" key={label}>
                    <Icon size={16} />
                    <strong>{value}</strong>
                    <span>{label}</span>
                  </div>
                ))}
              </div>
            </div>

            <div className="home-hero__spotlight-shell">
              {loading && (
                <div className="home-hero__spotlight home-hero__spotlight--loading">
                  <img src="/logo-mark.png" alt="" />
                  <span>{copy.loading}</span>
                </div>
              )}

              {!loading && !hasAnyEvents && (
                <div className="home-hero__spotlight home-hero__spotlight--brand">
                  <img src="/logo-transparent.png" alt="Vennuzo" />
                  <div>
                    <span className="event-card__status">Ready for organizers</span>
                    <h2>Bring your next event online</h2>
                    <p>Create a polished event page, accept Hubtel payments, and welcome guests with QR entry.</p>
                  </div>
                </div>
              )}

              {!loading && spotlightEvent && (
                <Link
                  to={`/events/${spotlightEvent.id}`}
                  className="home-hero__spotlight home-hero__spotlight--event"
                >
                  <div className="home-hero__spotlight-image">
                    {spotlightEvent.coverImageUrl ? (
                      <img src={spotlightEvent.coverImageUrl} alt={spotlightEvent.title} />
                    ) : (
                      <div
                        className={`event-card__mood event-card__mood--${spotlightEvent.mood}`}
                        style={{ '--hero-gradient': `var(--hero-gradient-${getEventGradientIndex(spotlightEvent.id) + 1})` } as CSSProperties}
                      />
                    )}
                    <div className="home-hero__spotlight-status">
                      <BadgeCheck size={14} />
                      {getSpotlightLabel(spotlightEvent, promotionCampaigns)}
                    </div>
                  </div>
                  <div className="home-hero__spotlight-body">
                    <span className="home-hero__spotlight-kicker">
                      Happening in {spotlightEvent.city || 'Ghana'}
                    </span>
                    <h2>{spotlightEvent.title}</h2>
                    <p>
                      <CalendarDays size={15} />
                      {formatDateTime(spotlightEvent.startAt)}
                    </p>
                    <p>
                      <MapPin size={15} />
                      {spotlightEvent.venue}, {spotlightEvent.city}
                    </p>
                    <div className="home-hero__spotlight-footer">
                      <span>{getPriceLabel(spotlightEvent)}</span>
                      <span>
                        {getTicketAvailability(spotlightEvent)}
                        <ArrowRight size={15} />
                      </span>
                    </div>
                  </div>
                </Link>
              )}

              {heroSlides.length > 1 && (
                <div className="home-hero__dots" role="tablist" aria-label="Featured events">
                  {heroSlides.map((event, i) => (
                    <button
                      key={event.id}
                      type="button"
                      role="tab"
                      aria-selected={i === heroIndex}
                      aria-label={`Show ${event.title}`}
                      className={`home-hero__dot ${i === heroIndex ? 'home-hero__dot--active' : ''}`}
                      onClick={() => setHeroIndex(i)}
                    />
                  ))}
                </div>
              )}
            </div>
          </div>
        </div>
      </section>

      <section className="home-filmstrip" aria-label="A glimpse of the scene">
        <div className="home-filmstrip__track">
          {[
            { src: '02_dj_booth_night', alt: 'DJ performing at a club night' },
            { src: '03_festival_dusk', alt: 'Outdoor festival at dusk' },
            { src: '07_dancefloor_silhouettes', alt: 'Silhouettes on a dancefloor' },
            { src: '08_live_band_intimate', alt: 'Intimate live performance' },
            { src: '10_gallery_culture_event', alt: 'Upscale cultural event' },
            { src: '02_dj_booth_night', alt: '' },
            { src: '03_festival_dusk', alt: '' },
            { src: '07_dancefloor_silhouettes', alt: '' },
            { src: '08_live_band_intimate', alt: '' },
            { src: '10_gallery_culture_event', alt: '' },
          ].map(({ src, alt }, i) => (
            <div className="home-filmstrip__item" key={`${src}-${i}`} aria-hidden={alt === '' ? true : undefined}>
              <img src={`/photos/${src}.png`} alt={alt} loading="lazy" />
            </div>
          ))}
        </div>
      </section>

      <section className="home-categories" aria-label="Browse by category">
        <div className="home-categories__header">
          <p className="eyebrow">Browse by vibe</p>
          <Link to="/events" className="text-link">
            See every event
            <ArrowRight size={14} />
          </Link>
        </div>
        <div className="home-categories__grid">
          {EVENT_CATEGORIES.map(({ id, shortLabel, Icon }) => (
            <Link key={id} to={eventSearchUrl(id)} className="home-categories__pill">
              <Icon size={17} />
              <span>{shortLabel}</span>
            </Link>
          ))}
        </div>
      </section>

      {!loading && featuredEvents.length > 0 && (
        <section className="home-featured" aria-labelledby="home-featured-title">
          <div className="home-featured__header">
            <div>
              <p className="eyebrow">Worth the spotlight</p>
              <h2 id="home-featured-title">Events people are noticing</h2>
            </div>
            <Link to="/events" className="text-link">
              See all events
              <ArrowRight size={14} />
            </Link>
          </div>
          <div className="home-featured__track">
            <div className="home-featured__list">
              {featuredEvents.map((event) => {
                const { day, month } = getDateParts(event.startAt)
                return (
                  <Link
                    key={event.id}
                    to={`/events/${event.id}`}
                    className={`home-featured__card home-featured__card--${getEventGradientIndex(event.id) + 1}`}
                  >
                    {event.coverImageUrl ? (
                      <div className="home-featured__card-image">
                        <img src={event.coverImageUrl} alt={event.title} />
                      </div>
                    ) : (
                      <div className={`event-card__mood event-card__mood--${event.mood}`} />
                    )}
                    <div className="home-featured__card-date-badge">
                      <span className="home-featured__card-date-badge-day">{day}</span>
                      <span className="home-featured__card-date-badge-month">{month}</span>
                    </div>
                    <span className="home-featured__status">{getSpotlightLabel(event, promotionCampaigns)}</span>
                    <div className="home-featured__card-body">
                      <span className="home-featured__card-date">{formatDateTime(event.startAt)}</span>
                      <h3>{event.title}</h3>
                      <p>{event.venue}, {event.city}</p>
                      <span className="home-featured__card-price">{getPriceLabel(event)}</span>
                    </div>
                  </Link>
                )
              })}
            </div>
          </div>
        </section>
      )}

      <section className="public-events-section" aria-labelledby="home-upcoming-title">
        <div className="public-events-section__header">
          <div>
            <p className="eyebrow">Plan ahead</p>
            <h2 id="home-upcoming-title">What is coming up next</h2>
          </div>
          <Link to="/events" className="text-link">
            Explore events
            <ArrowRight size={14} />
          </Link>
        </div>
        {loading && <p className="public-events-section__loading">{copy.loading}</p>}
        {!loading && events.length === 0 && (
          <div className="home-empty-card">
            <h3>No events are live yet</h3>
            <p>Be the first to put your event in front of Vennuzo guests.</p>
            <div className="home-empty-card__actions">
              <Link to="/studio" className="button button--primary">
                Launch your event
                <ArrowRight size={16} />
              </Link>
            </div>
          </div>
        )}
        {!loading && events.length > 0 && (
          <div className="event-grid event-grid--public event-grid--editorial">
            {(upcomingEvents.length > 0 ? upcomingEvents : events).slice(0, UPCOMING_GRID_COUNT).map((event) => {
              const { day, month } = getDateParts(event.startAt)
              const price = getPriceLabel(event)
              return (
                <Link
                  key={event.id}
                  to={`/events/${event.id}`}
                  className="event-card event-card--public event-card--editorial"
                >
                  <div className="event-card__cover">
                    {event.coverImageUrl ? (
                      <img src={event.coverImageUrl} alt={event.title} />
                    ) : (
                      <div className={`event-card__mood event-card__mood--${event.mood}`} />
                    )}
                    <div className="event-card__date-badge">
                      <span className="event-card__date-badge-day">{day}</span>
                      <span className="event-card__date-badge-month">{month}</span>
                    </div>
                    <span className="event-card__status">{getDemandLabel(event)}</span>
                  </div>
                  <div className="event-card__body">
                    <div className="event-card__meta-line">
                      <span>
                        <CalendarDays size={13} />
                        {formatDateTime(event.startAt)}
                      </span>
                      <span>{price}</span>
                    </div>
                    <h3 className="event-card__title">{event.title}</h3>
                    <p className="event-card__venue">
                      <MapPin size={14} />
                      {event.venue}, {event.city}
                    </p>
                    <div className="event-card__footer">
                      <span>{getTicketAvailability(event)}</span>
                      <span className="event-card__cta">
                        Book now
                        <ArrowRight size={14} />
                      </span>
                    </div>
                  </div>
                </Link>
              )
            })}
          </div>
        )}
      </section>

      <section className="home-showcase" aria-label="Every kind of night, one app away">
        <div className="home-section-heading home-showcase__head reveal">
          <p className="eyebrow">For guests</p>
          <h2>Every kind of night, one app away</h2>
        </div>

        <div className="home-showcase__row reveal">
          <div className="home-showcase__media reveal from-left">
            <img src="/photos/04_friends_arriving.png" alt="Friends arriving at a venue at night" loading="lazy" />
            <span className="home-showcase__badge"><Sparkles size={14} /> Discover</span>
          </div>
          <div className="home-showcase__text reveal from-right">
            <span className="home-showcase__num">01 - Discover</span>
            <h3>Find events that feel worth leaving home for</h3>
            <p>
              Browse concerts, parties, mixers, pop-ups, and cultural moments by vibe, venue, or date.
              Vennuzo helps the right plan find you.
            </p>
          </div>
        </div>

        <div className="home-showcase__row home-showcase__row--reverse reveal">
          <div className="home-showcase__media reveal from-right">
            <img src="/photos/05_qr_entry.png" alt="Phone held up to a venue ticket scanner" loading="lazy" />
            <span className="home-showcase__badge"><Ticket size={14} /> Instant entry</span>
          </div>
          <div className="home-showcase__text reveal from-left">
            <span className="home-showcase__num">02 - Book</span>
            <h3>Get in with less friction</h3>
            <p>
              Pay securely, keep your QR ticket on your phone, and arrive with everything ready for
              a smoother door experience.
            </p>
          </div>
        </div>

        <div className="home-showcase__row reveal">
          <div className="home-showcase__media reveal from-left">
            <img src="/photos/06_rooftop_party.png" alt="Friends at a rooftop party with a city skyline" loading="lazy" />
            <span className="home-showcase__badge"><UsersRound size={14} /> Share</span>
          </div>
          <div className="home-showcase__text reveal from-right">
            <span className="home-showcase__num">03 - Share</span>
            <h3>Bring your people with you</h3>
            <p>
              Save events, invite friends, and keep the plan easy to share. The best nights are better
              when everyone knows where to be.
            </p>
          </div>
        </div>
      </section>

      <section className="home-how" aria-labelledby="home-how-title">
        <div className="home-how__photo" aria-hidden="true" style={{ backgroundImage: "url('/photos/07_dancefloor_silhouettes.png')" }} />
        <div className="home-section-heading reveal">
          <p className="eyebrow">How it works</p>
          <h2 id="home-how-title">From interest to entry in a few taps</h2>
        </div>
        <div className="home-how__grid">
          {[
            { title: 'Find your plan', body: 'Search by city, category, venue, or event name.', Icon: Search },
            { title: 'Book securely', body: 'Checkout with Hubtel and get confirmation right away.', Icon: CreditCard },
            { title: 'Walk in ready', body: 'Your QR ticket helps the door move faster.', Icon: QrCode },
          ].map(({ title, body, Icon }) => (
            <div className="home-how__step reveal" key={title}>
              <div className="home-how__number"><Icon size={18} /></div>
              <h3>{title}</h3>
              <p>{body}</p>
            </div>
          ))}
        </div>
      </section>

      <section className="home-organizer">
        <div className="home-organizer__layout">
          <div className="home-organizer__content">
            <p className="eyebrow">For organizers</p>
            <h2>Everything organizers need to sell, promote, and welcome guests.</h2>
            <p>
              Publish a beautiful event page, accept payments, reach your audience, and run check-in
              from one simple workspace.
            </p>
            <div className="home-organizer__features">
              {[
                { label: 'Hubtel payments with clear order records', Icon: WalletCards },
                { label: 'Promotion tools for push, SMS, and audience growth', Icon: Megaphone },
                { label: 'Ticket tiers, guest lists, QR entry, and live reporting', Icon: ClipboardCheck },
              ].map(({ label, Icon }) => (
                <span key={label}>
                  <Icon size={16} />
                  {label}
                </span>
              ))}
            </div>
            <Link to="/studio" className="button button--primary">
              Start selling today
              <ArrowRight size={16} />
            </Link>
          </div>
          <div className="home-organizer__command" aria-label="Organizer command center preview">
            <div className="home-organizer__command-header">
              <img src="/logo-mark.png" alt="" />
              <div>
                <span>Vennuzo Studio</span>
              <strong>Event dashboard</strong>
              </div>
            </div>
            <div className="home-organizer__command-grid">
              <div>
                <span>Payments</span>
                <strong>Hubtel</strong>
              </div>
              <div>
                <span>Door</span>
                <strong>QR scan</strong>
              </div>
              <div>
                <span>Promote</span>
                <strong>SMS + push</strong>
              </div>
              <div>
                <span>Insights</span>
                <strong>Real-time</strong>
              </div>
            </div>
            <div className="home-organizer__command-ticket">
              <Ticket size={19} />
              <div>
                <strong>VIP Early Bird</strong>
                <span>Payment confirmed. Ticket ready.</span>
              </div>
              <BadgeCheck size={18} />
            </div>
          </div>
        </div>
      </section>

      <section className="home-trust" aria-label="Vennuzo trust features">
        <div className="home-trust__grid">
          {[
            { title: 'Trusted organizers', body: 'Event pages built with clear guest information.', Icon: ShieldCheck },
            { title: 'Easy checkout', body: 'Hubtel-powered payments for Ghanaian buyers.', Icon: Zap },
            { title: 'Ready at the door', body: 'QR tickets make entry smoother for everyone.', Icon: Ticket },
            { title: 'Room to grow', body: 'Promotion tools help organizers reach the right audience.', Icon: Megaphone },
          ].map(({ title, body, Icon }) => (
            <div className="home-trust__item" key={title}>
              <Icon size={19} />
              <strong>{title}</strong>
              <p>{body}</p>
            </div>
          ))}
        </div>
      </section>

      <section className="home-cta-band" aria-label="Get the Vennuzo app">
        <div className="home-cta-band__photo" aria-hidden="true">
          <img src="/photos/09_confetti_celebration.png" alt="" loading="lazy" />
        </div>
        <div className="home-cta-band__scrim" aria-hidden="true" />
        <div className="home-cta-band__inner reveal">
          <p className="eyebrow">Get started</p>
          <h2>Ready to make your next plan?</h2>
          <p className="home-cta-band__sub">
            Find events you will love, or launch one of your own. Vennuzo makes discovery,
            ticketing, and guest entry feel simple.
          </p>
          <div className="hero-chip-row">
            <Link to="/events" className="button button--primary">
              Explore events
              <ArrowRight size={16} />
            </Link>
            <Link to="/studio" className="button button--secondary">
              Start selling today
            </Link>
          </div>
        </div>
      </section>
    </div>
  )
}
