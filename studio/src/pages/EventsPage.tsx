import { useEffect, useMemo, useState } from 'react'
import { Link } from 'react-router-dom'

import { formatDateTime, formatMoney } from '../lib/formatters'
import { listOrganizerEvents } from '../lib/portalData'
import { usePortalSession } from '../lib/portalSession'
import type { PortalEvent } from '../lib/types'

export function EventsPage() {
  const { organizationId } = usePortalSession()
  const [events, setEvents] = useState<PortalEvent[]>([])
  const [loading, setLoading] = useState(false)
  const [query, setQuery] = useState('')

  useEffect(() => {
    let cancelled = false
    if (!organizationId) {
      return
    }
    const orgId = organizationId ?? ''

    async function run() {
      setLoading(true)
      const nextEvents = await listOrganizerEvents(orgId)
      if (!cancelled) {
        setEvents(nextEvents)
        setLoading(false)
      }
    }

    void run()
    return () => {
      cancelled = true
    }
  }, [organizationId])

  const publishedEvents = events.filter((event) => event.status === 'published').length
  const draftEvents = events.filter((event) => event.status === 'draft').length
  const totalRevenue = events.reduce((sum, event) => sum + event.grossRevenue, 0)
  const totalTickets = events.reduce((sum, event) => sum + event.ticketCount, 0)
  const filteredEvents = useMemo(() => {
    const trimmed = query.trim().toLowerCase()
    if (!trimmed) {
      return events
    }

    return events.filter((event) =>
      [
        event.title,
        event.description,
        event.venue,
        event.city,
        event.performers,
        event.djs,
        event.mcs,
        ...event.tags,
      ]
        .join(' ')
        .toLowerCase()
        .includes(trimmed),
    )
  }, [events, query])

  if (loading) {
    return <div className="page-loader">Loading events...</div>
  }

  return (
    <div className="dashboard-stack">
      <section className="page-hero page-hero--events">
        <div className="page-hero__content">
          <p className="eyebrow">Events management</p>
          <h2>Keep every event page polished, searchable, and ready to launch.</h2>
          <p>
            Browse your portfolio, jump into edits quickly, and manage every public
            or private event from one clean production workspace.
          </p>
          <div className="hero-chip-row">
            <span>{events.length} total events</span>
            <span>{publishedEvents} published</span>
            <span>{draftEvents} drafts</span>
          </div>
        </div>
        <div className="page-hero__panel">
          <label className="search-field">
            <span>Search your events</span>
            <input
              onChange={(event) => setQuery(event.target.value)}
              placeholder="Search by title, venue, city, or artist"
              value={query}
            />
          </label>
          <div className="hero-actions">
            <Link className="button button--primary" to="/events/new">
              New event
            </Link>
            <Link className="button button--secondary" to="/overview">
              Back to overview
            </Link>
          </div>
        </div>
      </section>

      <section className="stats-grid stats-grid--compact">
        <MetricCard label="Tracked revenue" value={formatMoney(totalRevenue)} />
        <MetricCard label="Tickets issued" value={String(totalTickets)} />
        <MetricCard label="Showing now" value={String(filteredEvents.length)} />
      </section>

      <section className="event-grid">
        {events.length === 0 ? (
          <div className="empty-card">
            <h4>No events created yet</h4>
            <p>Your workspace is live. Create your first event now.</p>
          </div>
        ) : filteredEvents.length === 0 ? (
          <div className="empty-card">
            <h4>No matches for "{query}"</h4>
            <p>Try a different title, venue, city, or artist name.</p>
          </div>
        ) : (
          filteredEvents.map((event) => (
            <article className="event-card event-card--studio" key={event.id}>
              <div className="event-card__badges">
                <span className={`status-pill status-pill--${event.status}`}>
                  {event.status}
                </span>
                <span className="status-pill status-pill--soft">{event.visibility}</span>
              </div>
              <h3>{event.title}</h3>
              <p>{event.description || 'No event description yet.'}</p>
              <div className="event-card__meta">
                <span>{formatDateTime(event.startAt)}</span>
                <span>
                  {event.venue}, {event.city}
                </span>
              </div>
              <div className="event-card__stats">
                <div>
                  <small>Revenue</small>
                  <strong>{formatMoney(event.grossRevenue)}</strong>
                </div>
                <div>
                  <small>Tickets</small>
                  <strong>{event.ticketCount}</strong>
                </div>
                <div>
                  <small>RSVPs</small>
                  <strong>{event.rsvpCount}</strong>
                </div>
              </div>
              <div className="event-card__footer">
                <div className="event-card__taglist">
                  {event.tags.slice(0, 3).map((tag) => (
                    <span className="tag-chip" key={tag}>
                      {tag}
                    </span>
                  ))}
                </div>
                <Link
                  className="button button--secondary"
                  to={`/events/${event.id}/edit`}
                >
                  Edit event
                </Link>
              </div>
            </article>
          ))
        )}
      </section>
    </div>
  )
}

function MetricCard({ label, value }: { label: string; value: string }) {
  return (
    <article className="metric-card metric-card--plain">
      <span>{label}</span>
      <strong>{value}</strong>
    </article>
  )
}
