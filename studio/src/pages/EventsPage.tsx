import { useEffect, useState } from 'react'
import { Link } from 'react-router-dom'

import { formatDateTime, formatMoney } from '../lib/formatters'
import { listOrganizerEvents } from '../lib/portalData'
import { usePortalSession } from '../lib/portalSession'
import type { PortalEvent } from '../lib/types'

export function EventsPage() {
  const { organizationId } = usePortalSession()
  const [events, setEvents] = useState<PortalEvent[]>([])
  const [loading, setLoading] = useState(false)

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

  if (loading) {
    return <div className="page-loader">Loading events...</div>
  }

  return (
    <div className="dashboard-stack">
      <section className="hero-card hero-card--compact">
        <div>
          <p className="eyebrow">Events management</p>
          <h2>Manage your published, draft, and private event inventory.</h2>
        </div>
        <Link className="button button--primary" to="/events/new">
          New event
        </Link>
      </section>

      <section className="event-grid">
        {events.length === 0 ? (
          <div className="empty-card">
            <h4>No events created yet</h4>
            <p>Your approved workspace is ready. Create your first event now.</p>
          </div>
        ) : (
          events.map((event) => (
            <article className="event-card" key={event.id}>
              <div className="event-card__badges">
                <span className="status-pill">{event.status}</span>
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
              <div className="event-card__footer">
                <div>
                  <small>Revenue</small>
                  <strong>{formatMoney(event.grossRevenue)}</strong>
                </div>
                <div>
                  <small>Tickets</small>
                  <strong>{event.ticketCount}</strong>
                </div>
              </div>
              <Link className="button button--secondary button--full" to={`/events/${event.id}/edit`}>
                Edit event
              </Link>
            </article>
          ))
        )}
      </section>
    </div>
  )
}
