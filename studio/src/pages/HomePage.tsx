import { useEffect, useState } from 'react'
import { Link } from 'react-router-dom'

import { copy } from '../lib/copy'
import { formatDateTime } from '../lib/formatters'
import { listPublicEvents } from '../lib/portalData'
import type { PortalEvent } from '../lib/types'

const HERO_SLIDE_DURATION_MS = 5000
const FEATURED_COUNT = 6
const UPCOMING_GRID_COUNT = 8

function getEventGradientIndex(id: string): number {
  let n = 0
  for (let i = 0; i < id.length; i++) n += id.charCodeAt(i)
  return n % 6
}

function getDateParts(isoDate: string): { day: string; month: string } {
  if (!isoDate) return { day: '—', month: '—' }
  const d = new Date(isoDate)
  if (isNaN(d.getTime())) return { day: '—', month: '—' }
  return {
    day: String(d.getDate()),
    month: d.toLocaleDateString('en', { month: 'short' }),
  }
}

function getPriceLabel(event: PortalEvent): string {
  if (!event.ticketingEnabled || event.tiers.length === 0) return ''
  const min = Math.min(...event.tiers.map((t) => t.price))
  return min === 0 ? 'Free' : `From ${event.currency} ${min}`
}

const CATEGORIES = [
  { label: 'Music', icon: '🎵' },
  { label: 'Nightlife', icon: '🌙' },
  { label: 'Arts', icon: '🎭' },
  { label: 'Food & Drink', icon: '🍽' },
  { label: 'Business', icon: '💼' },
  { label: 'Sports', icon: '⚽' },
  { label: 'Community', icon: '🤝' },
  { label: 'Workshops', icon: '🎓' },
]

export function HomePage() {
  const [events, setEvents] = useState<PortalEvent[]>([])
  const [loading, setLoading] = useState(true)
  const [heroIndex, setHeroIndex] = useState(0)

  useEffect(() => {
    let cancelled = false
    listPublicEvents(24)
      .then((list) => {
        if (!cancelled) setEvents(list)
      })
      .finally(() => {
        if (!cancelled) setLoading(false)
      })
    return () => { cancelled = true }
  }, [])

  const heroSlides = events.slice(0, 3)
  const featuredEvents = events.slice(0, FEATURED_COUNT)
  const upcomingEvents = events.slice(FEATURED_COUNT, FEATURED_COUNT + UPCOMING_GRID_COUNT)
  const hasAnyEvents = events.length > 0

  useEffect(() => {
    if (heroSlides.length < 2) return
    const t = setInterval(() => {
      setHeroIndex((i) => (i + 1) % heroSlides.length)
    }, HERO_SLIDE_DURATION_MS)
    return () => clearInterval(t)
  }, [heroSlides.length])

  return (
    <div className="public-home">
      {/* ── Hero ─────────────────────────────── */}
      <section className="home-hero" aria-label="Featured">
        <div className="home-hero__inner">
          {loading && (
            <div className="home-hero__slide home-hero__slide--default home-hero__slide--active">
              <div className="home-hero__slide-content">
                <p className="eyebrow">Discover</p>
                <h1>Find events near you</h1>
                <p className="home-hero__meta">Loading events...</p>
                <div className="hero-chip-row">
                  <Link to="/events" className="button button--primary">Browse events</Link>
                </div>
              </div>
            </div>
          )}
          {!loading && !hasAnyEvents && (
            <div className="home-hero__slide home-hero__slide--empty home-hero__slide--active">
              <div className="home-hero__slide-content">
                <p className="eyebrow">Vennuzo</p>
                <h1>Discover and book events you'll love</h1>
                <p className="home-hero__sub">
                  Find concerts, meetups, parties, and more happening near you. Get tickets instantly.
                </p>
                <div className="hero-chip-row">
                  <Link to="/events" className="button button--primary">Browse events</Link>
                  <Link to="/studio" className="button button--secondary">For organizers</Link>
                </div>
              </div>
            </div>
          )}
          {!loading && hasAnyEvents && (
            <>
              {heroSlides.map((event, i) => (
                <div
                  key={event.id}
                  className={[
                    'home-hero__slide',
                    'home-hero__slide--event',
                    event.coverImageUrl ? 'home-hero__slide--has-image' : '',
                    i === heroIndex ? 'home-hero__slide--active' : '',
                  ].filter(Boolean).join(' ')}
                  style={
                    event.coverImageUrl
                      ? { backgroundImage: `url(${event.coverImageUrl})` }
                      : ({ '--hero-gradient': `var(--hero-gradient-${getEventGradientIndex(event.id) + 1})` } as React.CSSProperties)
                  }
                  aria-hidden={i !== heroIndex}
                >
                  <div className="home-hero__slide-content">
                    <p className="eyebrow">Featured event</p>
                    <h1>{event.title}</h1>
                    <p className="home-hero__meta">
                      {formatDateTime(event.startAt)} · {event.venue}, {event.city}
                    </p>
                    <div className="hero-chip-row">
                      <Link to={`/events/${event.id}`} className="button button--primary">Get tickets</Link>
                      <Link to="/events" className="button button--secondary">Browse all</Link>
                    </div>
                  </div>
                </div>
              ))}
              {heroSlides.length > 1 && (
                <div className="home-hero__dots" role="tablist" aria-label="Slideshow">
                  {heroSlides.map((_, i) => (
                    <button
                      key={i}
                      type="button"
                      role="tab"
                      aria-selected={i === heroIndex}
                      aria-label={`Slide ${i + 1}`}
                      className={`home-hero__dot ${i === heroIndex ? 'home-hero__dot--active' : ''}`}
                      onClick={() => setHeroIndex(i)}
                    />
                  ))}
                </div>
              )}
            </>
          )}
        </div>
      </section>

      {/* ── Categories ───────────────────────── */}
      <section className="home-categories">
        <div className="home-categories__grid">
          {CATEGORIES.map((cat) => (
            <Link key={cat.label} to="/events" className="home-categories__item">
              <span className="home-categories__icon">{cat.icon}</span>
              <span className="home-categories__label">{cat.label}</span>
            </Link>
          ))}
        </div>
      </section>

      {/* ── Featured carousel ────────────────── */}
      {!loading && featuredEvents.length > 0 && (
        <section className="home-featured" aria-labelledby="home-featured-title">
          <div className="home-featured__header">
            <h2 id="home-featured-title">Featured events</h2>
            <Link to="/events" className="text-link">View all</Link>
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
                    {event.coverImageUrl && (
                      <div className="home-featured__card-image">
                        <img src={event.coverImageUrl} alt={event.title} />
                      </div>
                    )}
                    <div className="home-featured__card-date-badge">
                      <span className="home-featured__card-date-badge-day">{day}</span>
                      <span className="home-featured__card-date-badge-month">{month}</span>
                    </div>
                    <div className="home-featured__card-body">
                      <span className="home-featured__card-date">{formatDateTime(event.startAt)}</span>
                      <h3>{event.title}</h3>
                      <p>{event.venue}, {event.city}</p>
                      {getPriceLabel(event) && (
                        <span className="home-featured__card-price">{getPriceLabel(event)}</span>
                      )}
                    </div>
                  </Link>
                )
              })}
            </div>
          </div>
        </section>
      )}

      {/* ── Upcoming grid ────────────────────── */}
      <section className="public-events-section" aria-labelledby="home-upcoming-title">
        <div className="public-events-section__header">
          <h2 id="home-upcoming-title">Upcoming events</h2>
          <Link to="/events" className="text-link">View all</Link>
        </div>
        {loading && <p className="public-events-section__loading">{copy.loading}</p>}
        {!loading && events.length === 0 && (
          <div className="home-empty-card">
            <h3>No events yet</h3>
            <p>Check back soon or create your own event as an organizer.</p>
            <div className="home-empty-card__actions">
              <Link to="/studio" className="button button--primary">Create an event</Link>
            </div>
          </div>
        )}
        {!loading && events.length > 0 && (
          <div className="event-grid event-grid--public">
            {(upcomingEvents.length > 0 ? upcomingEvents : events).slice(0, UPCOMING_GRID_COUNT).map((event) => {
              const { day, month } = getDateParts(event.startAt)
              const price = getPriceLabel(event)
              return (
                <Link
                  key={event.id}
                  to={`/events/${event.id}`}
                  className="event-card event-card--public event-card--rich"
                >
                  <div className="event-card__cover">
                    {event.coverImageUrl
                      ? <img src={event.coverImageUrl} alt={event.title} />
                      : <div className={`event-card__mood event-card__mood--${event.mood}`} />
                    }
                    <div className="event-card__scrim" />
                    <div className="event-card__date-badge">
                      <span className="event-card__date-badge-day">{day}</span>
                      <span className="event-card__date-badge-month">{month}</span>
                    </div>
                    <div className="event-card__info">
                      <p className="event-card__city">{event.city}</p>
                      <h3 className="event-card__title">{event.title}</h3>
                      <p className="event-card__venue">{event.venue}</p>
                      <div className="event-card__footer">
                        {price && <span className="event-card__price">{price}</span>}
                        <span className="event-card__cta">Get Tickets</span>
                      </div>
                    </div>
                  </div>
                </Link>
              )
            })}
          </div>
        )}
      </section>

      {/* ── How it works ─────────────────────── */}
      <section className="home-how">
        <h2>How Vennuzo works</h2>
        <div className="home-how__grid">
          <div className="home-how__step">
            <div className="home-how__number">1</div>
            <h3>Browse events</h3>
            <p>Explore events by category, location, or date. Find exactly what you're looking for.</p>
          </div>
          <div className="home-how__step">
            <div className="home-how__number">2</div>
            <h3>Get your tickets</h3>
            <p>Secure checkout with instant confirmation. Your tickets are saved right in the app.</p>
          </div>
          <div className="home-how__step">
            <div className="home-how__number">3</div>
            <h3>Enjoy the event</h3>
            <p>Show your QR code at the door. No printing needed, just your phone.</p>
          </div>
        </div>
      </section>

      {/* ── Organizer CTA ────────────────────── */}
      <section className="home-organizer">
        <div className="home-organizer__content">
          <p className="eyebrow">For organizers</p>
          <h2>Host your next event on Vennuzo</h2>
          <p>
            Create events, sell tickets, manage attendees, and promote to a growing audience.
            Everything you need to run a successful event, all in one place.
          </p>
          <ul className="home-organizer__features">
            <li>Event creation with custom ticket tiers</li>
            <li>Real-time sales tracking and analytics</li>
            <li>Built-in promotion tools</li>
            <li>Secure payments via Hubtel</li>
            <li>Attendee management and check-in</li>
          </ul>
          <Link to="/studio" className="button button--primary">Start for free</Link>
        </div>
      </section>

      {/* ── Trust bar ────────────────────────── */}
      <section className="home-trust">
        <div className="home-trust__grid">
          <div className="home-trust__item">
            <strong>Secure payments</strong>
            <p>All transactions processed securely through Hubtel</p>
          </div>
          <div className="home-trust__item">
            <strong>Instant delivery</strong>
            <p>Tickets delivered to your phone immediately after purchase</p>
          </div>
          <div className="home-trust__item">
            <strong>QR check-in</strong>
            <p>Contactless entry with scannable QR codes</p>
          </div>
          <div className="home-trust__item">
            <strong>24/7 support</strong>
            <p>Our team is here to help whenever you need it</p>
          </div>
        </div>
      </section>
    </div>
  )
}
