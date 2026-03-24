import { useEffect, useMemo, useState } from 'react'
import { Link } from 'react-router-dom'

import { copy } from '../lib/copy'
import { formatMoney } from '../lib/formatters'
import { listOrganizerEvents } from '../lib/portalData'
import { usePortalSession } from '../lib/portalSession'
import type { PortalEvent } from '../lib/types'

type StatusFilter = 'all' | 'published' | 'draft'

export function EventsPage() {
  const { organizationId } = usePortalSession()
  const [events, setEvents] = useState<PortalEvent[]>([])
  const [loading, setLoading] = useState(false)
  const [query, setQuery] = useState('')
  const [statusFilter, setStatusFilter] = useState<StatusFilter>('all')

  useEffect(() => {
    let cancelled = false
    const orgId = organizationId ?? ''
    if (!orgId) return
    async function run() {
      setLoading(true)
      const nextEvents = await listOrganizerEvents(orgId)
      if (!cancelled) {
        setEvents(nextEvents)
        setLoading(false)
      }
    }
    void run()
    return () => { cancelled = true }
  }, [organizationId])

  const publishedCount = events.filter((e) => e.status === 'published').length
  const draftCount = events.filter((e) => e.status === 'draft').length
  const totalRevenue = events.reduce((sum, e) => sum + e.grossRevenue, 0)
  const totalTickets = events.reduce((sum, e) => sum + e.ticketCount, 0)

  const filteredEvents = useMemo(() => {
    let list = events
    if (statusFilter === 'published') list = list.filter((e) => e.status === 'published')
    if (statusFilter === 'draft') list = list.filter((e) => e.status === 'draft')
    const q = query.trim().toLowerCase()
    if (!q) return list
    return list.filter((e) =>
      [e.title, e.description, e.venue, e.city, e.performers, e.djs, e.mcs, ...e.tags]
        .join(' ')
        .toLowerCase()
        .includes(q),
    )
  }, [events, query, statusFilter])

  if (loading) {
    return <div className="page-loader">{copy.loading}</div>
  }

  return (
    <div className="dashboard-stack events-dashboard">
      <section className="events-dashboard__hero">
        <div className="events-dashboard__hero-content">
          <h2>Your events</h2>
          <p>Create and manage events, track sales and RSVPs.</p>
        </div>
        <div className="events-dashboard__hero-actions">
          <Link className="button button--primary" to="/studio/events/new">
            Create event
          </Link>
        </div>
      </section>

      <section className="events-dashboard__stats">
        <div className="events-dashboard__stat">
          <span className="events-dashboard__stat-label">Total revenue</span>
          <strong>{formatMoney(totalRevenue)}</strong>
        </div>
        <div className="events-dashboard__stat">
          <span className="events-dashboard__stat-label">Tickets sold</span>
          <strong>{totalTickets}</strong>
        </div>
        <div className="events-dashboard__stat">
          <span className="events-dashboard__stat-label">Events</span>
          <strong>{events.length}</strong>
          <small>{publishedCount} live · {draftCount} draft</small>
        </div>
      </section>

      <section className="events-dashboard__toolbar">
        <div className="events-dashboard__search">
          <input
            type="search"
            placeholder="Search events…"
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            aria-label="Search events"
          />
        </div>
        <div className="events-dashboard__filters" role="tablist" aria-label="Filter by status">
          {(['all', 'published', 'draft'] as const).map((key) => (
            <button
              key={key}
              type="button"
              role="tab"
              aria-selected={statusFilter === key}
              className={`events-dashboard__filter ${statusFilter === key ? 'events-dashboard__filter--active' : ''}`}
              onClick={() => setStatusFilter(key)}
            >
              {key === 'all' ? 'All' : key === 'published' ? 'Published' : 'Drafts'}
            </button>
          ))}
        </div>
      </section>

      <section className="events-dashboard__list">
        {events.length === 0 ? (
          <div className="events-dashboard__empty">
            <div className="events-dashboard__empty-icon" aria-hidden>◎</div>
            <h3>No events yet</h3>
            <p>Create your first event to start selling tickets and tracking RSVPs.</p>
            <Link className="button button--primary" to="/studio/events/new">
              Create event
            </Link>
          </div>
        ) : filteredEvents.length === 0 ? (
          <div className="events-dashboard__empty">
            <h3>No matches</h3>
            <p>{query.trim() ? `No events match "${query}".` : `No ${statusFilter} events.`}</p>
            <button
              type="button"
              className="button button--ghost"
              onClick={() => { setQuery(''); setStatusFilter('all') }}
            >
              Clear filters
            </button>
          </div>
        ) : (
          <ul className="events-dashboard__cards">
            {filteredEvents.map((event) => {
              const eventDate = event.startAt ? new Date(event.startAt) : null
              const dayLabel = eventDate && !Number.isNaN(eventDate.getTime()) ? eventDate.getDate() : '—'
              const monthLabel = eventDate && !Number.isNaN(eventDate.getTime())
                ? eventDate.toLocaleString('default', { month: 'short' }).toUpperCase()
                : ''
              const capacity = event.tiers.reduce((sum, t) => sum + t.maxQuantity, 0)
              const salesPercent = capacity > 0 ? Math.min(100, Math.round((event.ticketCount / capacity) * 100)) : 0
              return (
                <li key={event.id}>
                  <Link to={`/studio/events/${event.id}/edit`} className="events-dashboard__card">
                    <div className="events-dashboard__card-date" aria-hidden>
                      <span className="events-dashboard__card-date-day">{dayLabel}</span>
                      <span className="events-dashboard__card-date-month">{monthLabel}</span>
                    </div>
                    <div className="events-dashboard__card-main">
                      <span className={`events-dashboard__card-status status-pill status-pill--${event.status}`}>
                        {event.status}
                      </span>
                      <h3 className="events-dashboard__card-title">{event.title}</h3>
                      <p className="events-dashboard__card-meta">
                        {event.venue}, {event.city}
                      </p>
                      {event.ticketingEnabled && capacity > 0 && (
                        <div className="events-dashboard__card-progress">
                          <div className="events-dashboard__card-progress-label">
                            <span>{event.ticketCount} sold</span>
                            <span>{salesPercent}%</span>
                          </div>
                          <div className="events-dashboard__card-progress-bar">
                            <div className="events-dashboard__card-progress-fill" style={{ width: `${salesPercent}%` }} />
                          </div>
                        </div>
                      )}
                    </div>
                    <div className="events-dashboard__card-metrics">
                      <span>{formatMoney(event.grossRevenue)}</span>
                      <span>{event.ticketCount} tickets</span>
                      <span>{event.rsvpCount} RSVPs</span>
                    </div>
                    <span className="events-dashboard__card-cta">Edit →</span>
                  </Link>
                </li>
              )
            })}
          </ul>
        )}
      </section>
    </div>
  )
}
