import { useEffect, useMemo, useState } from 'react'
import { Link } from 'react-router-dom'
import {
  ArrowRight,
  CalendarPlus,
  LayoutGrid,
  List,
  Search,
  TicketCheck,
  Users,
  WalletCards,
} from 'lucide-react'

import { formatMoney } from '../lib/formatters'
import { listOrganizerEvents } from '../lib/portalData'
import { usePortalSession } from '../lib/portalSession'
import type { PortalEvent } from '../lib/types'

type StatusFilter = 'all' | 'published' | 'draft'
type ViewMode = 'visual' | 'compact'

export function EventsPage() {
  const session = usePortalSession()
  const { organizationId } = session
  const [events, setEvents] = useState<PortalEvent[]>([])
  const [loading, setLoading] = useState(false)
  const [query, setQuery] = useState('')
  const [statusFilter, setStatusFilter] = useState<StatusFilter>('all')
  const [viewMode, setViewMode] = useState<ViewMode>('visual')
  const [viewTimestamp] = useState(() => Date.now())

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
  const totalRsvps = events.reduce((sum, e) => sum + e.rsvpCount, 0)
  const totalCapacity = events.reduce(
    (sum, event) => sum + event.tiers.reduce((tierSum, tier) => tierSum + tier.maxQuantity, 0),
    0,
  )
  const soldThroughPercent =
    totalCapacity > 0 ? Math.min(100, Math.round((totalTickets / totalCapacity) * 100)) : 0
  const activeEventCount = events.filter((event) => event.status !== 'cancelled').length

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
    return <EventsPageSkeleton />
  }

  return (
    <div className="dashboard-stack events-dashboard">
      <section className="events-dashboard__hero">
        <div className="events-dashboard__hero-content">
          <h2>Your events</h2>
          <p>Create and manage events, track sales and RSVPs.</p>
          <div className="hero-chip-row hero-chip-row--compact">
            <span>{activeEventCount} active events</span>
            <span>{soldThroughPercent}% sold through</span>
          </div>
        </div>
        <div className="events-dashboard__hero-actions">
          <Link className="button button--primary" to="/studio/events/new">
            <CalendarPlus size={16} aria-hidden />
            Create event
          </Link>
        </div>
      </section>

      <section className="events-dashboard__stats">
        <div className="events-dashboard__stat">
          <WalletCards size={18} aria-hidden />
          <span className="events-dashboard__stat-label">Total revenue</span>
          <strong>{formatMoney(totalRevenue)}</strong>
        </div>
        <div className="events-dashboard__stat">
          <TicketCheck size={18} aria-hidden />
          <span className="events-dashboard__stat-label">Tickets sold</span>
          <strong>{totalTickets}</strong>
          <small>{soldThroughPercent}% of capacity</small>
        </div>
        <div className="events-dashboard__stat">
          <Users size={18} aria-hidden />
          <span className="events-dashboard__stat-label">Audience</span>
          <strong>{totalRsvps}</strong>
          <small>RSVPs captured</small>
        </div>
        <div className="events-dashboard__stat">
          <span className="events-dashboard__stat-label">Events</span>
          <strong>{events.length}</strong>
          <small>{publishedCount} live · {draftCount} draft</small>
        </div>
      </section>

      <section className="events-dashboard__toolbar">
        <div className="events-dashboard__search">
          <Search className="events-dashboard__search-icon" size={16} aria-hidden />
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
        <div className="events-dashboard__view-toggle" role="group" aria-label="View mode">
          <button
            type="button"
            className={viewMode === 'visual' ? 'is-active' : ''}
            onClick={() => setViewMode('visual')}
            aria-label="Visual card view"
          >
            <LayoutGrid size={15} aria-hidden />
            Visual
          </button>
          <button
            type="button"
            className={viewMode === 'compact' ? 'is-active' : ''}
            onClick={() => setViewMode('compact')}
            aria-label="Compact list view"
          >
            <List size={15} aria-hidden />
            Compact
          </button>
        </div>
      </section>

      <section className="events-dashboard__list">
        {events.length === 0 ? (
          <div className="events-dashboard__empty">
            <div className="events-dashboard__empty-icon" aria-hidden>
              <CalendarPlus size={42} />
            </div>
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
              const daysToGo = eventDate && !Number.isNaN(eventDate.getTime())
                ? Math.ceil((eventDate.getTime() - viewTimestamp) / 86_400_000)
                : null
              return (
                <li key={event.id}>
                  <Link
                    to={`/studio/events/${event.id}/edit`}
                    className={`events-dashboard__card events-dashboard__card--${viewMode}`}
                  >
                    <div className="events-dashboard__card-art" aria-hidden>
                      <div className="events-dashboard__card-art-fallback">
                        {event.title.trim().slice(0, 1).toUpperCase() || 'V'}
                      </div>
                      {event.coverImageUrl ? (
                        <img
                          alt=""
                          loading="lazy"
                          onError={(imageEvent) => {
                            imageEvent.currentTarget.style.display = 'none'
                          }}
                          src={event.coverImageUrl}
                        />
                      ) : null}
                      <div className="events-dashboard__card-date">
                        <span className="events-dashboard__card-date-day">{dayLabel}</span>
                        <span className="events-dashboard__card-date-month">{monthLabel}</span>
                      </div>
                    </div>
                    <div className="events-dashboard__card-main">
                      <span className={`events-dashboard__card-status status-pill status-pill--${event.status}`}>
                        {event.status}
                      </span>
                      <h3 className="events-dashboard__card-title">{event.title}</h3>
                      <p className="events-dashboard__card-meta">
                        {event.venue}, {event.city}
                      </p>
                      <div className="event-card-detail-row">
                        <span>
                          {daysToGo == null
                            ? 'Date pending'
                            : daysToGo < 0
                              ? 'Past event'
                              : daysToGo === 0
                                ? 'Today'
                                : `${daysToGo} days to go`}
                        </span>
                        <span>{capacity > 0 ? `${capacity} capacity` : 'RSVP only'}</span>
                        {event.tags.slice(0, 1).map((tag) => (
                          <span key={tag}>{tag}</span>
                        ))}
                      </div>
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
                    <span className="events-dashboard__card-cta">
                      Edit <ArrowRight size={14} aria-hidden />
                    </span>
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

function EventsPageSkeleton() {
  return (
    <div className="dashboard-stack events-dashboard">
      <section className="events-dashboard__hero events-dashboard__hero--skeleton">
        <div className="events-dashboard__hero-content">
          <div className="skeleton-line skeleton-line--short" />
          <div className="skeleton-line skeleton-line--title" />
          <div className="skeleton-line" />
        </div>
        <div className="skeleton-button" />
      </section>

      <section className="events-dashboard__stats">
        {[0, 1, 2].map((item) => (
          <div className="events-dashboard__stat events-dashboard__stat--skeleton" key={item}>
            <div className="skeleton-line skeleton-line--short" />
            <div className="skeleton-line skeleton-line--metric" />
          </div>
        ))}
      </section>

      <section className="events-dashboard__toolbar">
        <div className="events-dashboard__search events-dashboard__search--skeleton" />
        <div className="events-dashboard__filters events-dashboard__filters--skeleton">
          {[0, 1, 2].map((item) => (
            <span key={item} />
          ))}
        </div>
      </section>

      <section className="events-dashboard__list">
        <ul className="events-dashboard__cards">
          {[0, 1, 2].map((item) => (
            <li key={item}>
              <div className="events-dashboard__card events-dashboard__card--skeleton">
                <div className="events-dashboard__card-art skeleton-block" />
                <div className="events-dashboard__card-main">
                  <div className="skeleton-line skeleton-line--short" />
                  <div className="skeleton-line skeleton-line--title" />
                  <div className="skeleton-line" />
                </div>
                <div className="events-dashboard__card-metrics">
                  <div className="skeleton-line skeleton-line--metric" />
                  <div className="skeleton-line skeleton-line--short" />
                </div>
                <div className="skeleton-button skeleton-button--small" />
              </div>
            </li>
          ))}
        </ul>
      </section>
    </div>
  )
}
