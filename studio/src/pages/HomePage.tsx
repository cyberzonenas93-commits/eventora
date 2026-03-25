import { useEffect, useState } from 'react'
import { Link } from 'react-router-dom'

import { copy } from '../lib/copy'
import { formatDateTime } from '../lib/formatters'
import { listPublicEvents } from '../lib/portalData'
import type { PortalEvent } from '../lib/types'

const HERO_SLIDE_DURATION_MS = 5000
const FEATURED_COUNT = 6
const UPCOMING_GRID_COUNT = 8

/** Deterministic gradient index from event id for visual variety */
function getEventGradientIndex(id: string): number {
  let n = 0
  for (let i = 0; i < id.length; i++) n += id.charCodeAt(i)
  return n % 6
}

/** Extract day and short month from ISO date string */
function getDateParts(isoDate: string): { day: string; month: string } {
  if (!isoDate) return { day: '—', month: '—' }
  const d = new Date(isoDate)
  if (isNaN(d.getTime())) return { day: '—', month: '—' }
  return {
    day: String(d.getDate()),
    month: d.toLocaleDateString('en', { month: 'short' }),
  }
}

/** Lowest tier price, or "Free" */
function getPriceLabel(event: PortalEvent): string {
  if (!event.ticketingEnabled || event.tiers.length === 0) return ''
  const min = Math.min(...event.tiers.map((t) => t.price))
  return min === 0 ? 'Free' : `From ${event.currency} ${min}`
}

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
      {/* Hero: slideshow of featured events or vibrant default CTA */}
      <section
        className={`home-hero${!hasAnyEvents && !loading ? ' home-hero--vibrant' : ''}`}
        aria-label="Featured"
      >
        <div className="home-hero__inner">
          {loading && (
            <div className="home-hero__slide home-hero__slide--default home-hero__slide--active">
              <p className="eyebrow">Event hub</p>
              <h1>Discover events that move you</h1>
              <p>Loading events…</p>
              <div className="hero-chip-row">
                <Link to="/events" className="button button--primary">Browse events</Link>
                <Link to="/studio" className="button button--secondary">For organizers</Link>
              </div>
            </div>
          )}
          {!loading && !hasAnyEvents && (
            <div className="home-hero__slide home-hero__slide--vibrant home-hero__slide--active">
              {/* Animated gradient orbs */}
              <div className="hero-orb hero-orb--1" aria-hidden="true" />
              <div className="hero-orb hero-orb--2" aria-hidden="true" />
              <div className="hero-orb hero-orb--3" aria-hidden="true" />
              <div className="hero-orb hero-orb--4" aria-hidden="true" />

              <div className="home-hero__empty-content">
                <div className="hero-badge">✦ Event Discovery Platform</div>
                <h1>
                  Where Unforgettable<br />
                  <span className="hero-gradient-text">Nights Begin</span>
                </h1>
                <p className="home-hero__empty-sub">
                  Discover extraordinary events, secure your spot, and create memories that last a lifetime.
                </p>
                <div className="hero-features">
                  <span className="hero-feature-pill">Live Music</span>
                  <span className="hero-feature-pill">Experiences</span>
                  <span className="hero-feature-pill">VIP Events</span>
                  <span className="hero-feature-pill">Festivals</span>
                </div>
                <div className="hero-chip-row">
                  <Link to="/events" className="button button--primary button--glow">Explore Events</Link>
                  <Link to="/studio" className="button button--glass">Host an Event</Link>
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
                      <Link to={`/events/${event.id}`} className="button button--primary">
                        Get tickets
                      </Link>
                      <Link to="/events" className="button button--secondary">
                        Browse all
                      </Link>
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

      {/* Featured events carousel */}
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

      {/* Upcoming events grid */}
      <section className="public-events-section" aria-labelledby="home-upcoming-title">
        <div className="public-events-section__header">
          <h2 id="home-upcoming-title">Upcoming events</h2>
          <Link to="/events" className="text-link">View all</Link>
        </div>
        {loading && <p className="public-events-section__loading">{copy.loading}</p>}
        {!loading && events.length === 0 && (
          <div className="home-empty-state">
            <div
              className="home-empty-state__bg"
              style={{
                backgroundImage:
                  'url(https://images.unsplash.com/photo-1540575467063-178a50c2df87?auto=format&fit=crop&w=1400&q=80)',
              }}
            />
            <div className="home-empty-state__overlay">
              <div className="home-empty-state__glass">
                <div className="home-empty-state__icon">✦</div>
                <h3>Be the First to Experience It</h3>
                <p>
                  Nothing's on the calendar yet — but something extraordinary is coming.
                  Create your own event or check back soon.
                </p>
                <div className="hero-chip-row home-empty-state__actions">
                  <Link to="/studio" className="button button--primary button--glow">
                    Create an Event
                  </Link>
                  <Link to="/events" className="button button--glass-dark">
                    Browse Events
                  </Link>
                </div>
              </div>
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
    </div>
  )
}
