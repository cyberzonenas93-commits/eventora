import { useEffect, useState } from 'react'
import { Link } from 'react-router-dom'

import { formatDateTime, formatMoney } from '../lib/formatters'
import { listOrganizerEvents, loadOverviewMetrics } from '../lib/portalData'
import { usePortalSession } from '../lib/portalSession'
import type { OverviewMetrics, PortalEvent } from '../lib/types'

export function OverviewPage() {
  const { organizationId } = usePortalSession()
  const [metrics, setMetrics] = useState<OverviewMetrics | null>(null)
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
      const [nextMetrics, nextEvents] = await Promise.all([
        loadOverviewMetrics(orgId),
        listOrganizerEvents(orgId),
      ])
      if (!cancelled) {
        setMetrics(nextMetrics)
        setEvents(nextEvents.slice(0, 4))
        setLoading(false)
      }
    }

    void run()
    return () => {
      cancelled = true
    }
  }, [organizationId])

  if (loading) {
    return <div className="page-loader">Loading portfolio overview...</div>
  }

  return (
    <div className="dashboard-stack">
      <section className="hero-card">
        <div>
          <p className="eyebrow">Portfolio aggregation</p>
          <h2>See revenue, RSVPs, and publishing readiness across your event stack.</h2>
        </div>
        <Link className="button button--primary" to="/events/new">
          Create event
        </Link>
      </section>

      <section className="stats-grid">
        <MetricCard label="Gross revenue" value={formatMoney(metrics?.grossRevenue ?? 0)} />
        <MetricCard label="Paid orders" value={String(metrics?.paidOrders ?? 0)} />
        <MetricCard label="RSVPs" value={String(metrics?.totalRsvps ?? 0)} />
        <MetricCard label="Tickets issued" value={String(metrics?.ticketsIssued ?? 0)} />
        <MetricCard label="Live events" value={String(metrics?.liveEvents ?? 0)} />
        <MetricCard label="Draft events" value={String(metrics?.draftEvents ?? 0)} />
      </section>

      <section className="panel">
        <div className="panel__header">
          <div>
            <p className="eyebrow">Recent events</p>
            <h3>Closest events to the door and ticket desk</h3>
          </div>
          <Link className="text-link" to="/events">
            View all
          </Link>
        </div>

        <div className="event-list">
          {events.length === 0 ? (
            <div className="empty-card">
              <h4>No events yet</h4>
              <p>Start by creating your first Eventora event from Studio.</p>
            </div>
          ) : (
            events.map((event) => (
              <Link className="event-row" key={event.id} to={`/events/${event.id}/edit`}>
                <div>
                  <strong>{event.title}</strong>
                  <span>
                    {formatDateTime(event.startAt)} • {event.venue}, {event.city}
                  </span>
                </div>
                <div className="event-row__metrics">
                  <span>{event.visibility}</span>
                  <strong>{formatMoney(event.grossRevenue)}</strong>
                </div>
              </Link>
            ))
          )}
        </div>
      </section>
    </div>
  )
}

function MetricCard({ label, value }: { label: string; value: string }) {
  return (
    <article className="metric-card">
      <span>{label}</span>
      <strong>{value}</strong>
    </article>
  )
}
