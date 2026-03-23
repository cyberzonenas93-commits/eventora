import { useEffect, useMemo, useState } from 'react'
import { Link } from 'react-router-dom'

import { copy } from '../lib/copy'
import { formatDateTime } from '../lib/formatters'
import { listPublicEvents } from '../lib/portalData'
import type { PortalEvent } from '../lib/types'

export function PublicEventsPage() {
  const [events, setEvents] = useState<PortalEvent[]>([])
  const [loading, setLoading] = useState(true)
  const [query, setQuery] = useState('')

  useEffect(() => {
    let cancelled = false
    listPublicEvents(100)
      .then((list) => {
        if (!cancelled) setEvents(list)
      })
      .finally(() => {
        if (!cancelled) setLoading(false)
      })
    return () => { cancelled = true }
  }, [])

  const filtered = useMemo(() => {
    const q = query.trim().toLowerCase()
    if (!q) return events
    return events.filter(
      (e) =>
        e.title.toLowerCase().includes(q) ||
        e.venue.toLowerCase().includes(q) ||
        e.city.toLowerCase().includes(q) ||
        e.description.toLowerCase().includes(q) ||
        e.tags.some((t) => t.toLowerCase().includes(q)),
    )
  }, [events, query])

  return (
    <div className="public-page">
      <section className="page-hero page-hero--events">
        <div className="page-hero__content">
          <p className="eyebrow">Events</p>
          <h2>Upcoming events</h2>
          <p>Find events near you and get tickets.</p>
          <div className="search-field public-search">
            <input
              type="search"
              placeholder="Search events, venue, city…"
              value={query}
              onChange={(e) => setQuery(e.target.value)}
              aria-label="Search events"
            />
          </div>
        </div>
      </section>

      {loading ? (
        <p className="page-loader">{copy.loading}</p>
      ) : filtered.length === 0 ? (
        <div className="empty-card">
          <h4>{query.trim() ? 'No events match your search' : 'No upcoming events'}</h4>
          <p>
            {query.trim()
              ? 'Try a different search or browse all events.'
              : 'Check back later or create your own as an organizer.'}
          </p>
          <Link to="/studio" className="button button--secondary">
            Organizer dashboard
          </Link>
        </div>
      ) : (
        <div className="event-grid event-grid--public">
          {filtered.map((event) => (
            <Link
              key={event.id}
              to={`/events/${event.id}`}
              className="event-card event-card--public"
            >
              <div className="event-card__top">
                <span className="event-card__date">{formatDateTime(event.startAt)}</span>
                <span className="event-card__city">{event.city}</span>
              </div>
              <h3>{event.title}</h3>
              <p>{event.venue}</p>
              {event.ticketingEnabled && event.tiers.length > 0 && (
                <span className="event-card__price">
                  From {event.tiers[0].price === 0 ? 'Free' : `GHS ${event.tiers[0].price}`}
                </span>
              )}
            </Link>
          ))}
        </div>
      )}
    </div>
  )
}
