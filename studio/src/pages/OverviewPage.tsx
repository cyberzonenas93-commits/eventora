import { useEffect, useMemo, useState } from 'react'
import { Link } from 'react-router-dom'

import { formatDateTime, formatMoney } from '../lib/formatters'
import { getPayoutReadiness, getWorkspaceName, getWorkspaceTagline } from '../lib/merchantWorkspace'
import { listOrganizerEvents, loadOverviewMetrics } from '../lib/portalData'
import { usePortalSession } from '../lib/portalSession'
import type { OverviewMetrics, PortalEvent } from '../lib/types'

export function OverviewPage() {
  const session = usePortalSession()
  const { organizationId } = session
  const [metrics, setMetrics] = useState<OverviewMetrics | null>(null)
  const [events, setEvents] = useState<PortalEvent[]>([])
  const [loading, setLoading] = useState(false)
  const [viewTimestamp] = useState(() => Date.now())

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
        setEvents(nextEvents)
        setLoading(false)
      }
    }

    void run()
    return () => {
      cancelled = true
    }
  }, [organizationId])

  const orderedEvents = useMemo(
    () =>
      [...events].sort(
        (left, right) =>
          new Date(left.startAt).getTime() - new Date(right.startAt).getTime(),
      ),
    [events],
  )

  const upcomingEvent =
    orderedEvents.find(
      (event) =>
        event.status !== 'cancelled' &&
        new Date(event.startAt).getTime() >= viewTimestamp - 60 * 60 * 1000,
    ) ?? orderedEvents[0]

  const publishedEvents = events.filter((event) => event.status === 'published').length
  const draftEvents = events.filter((event) => event.status === 'draft').length
  const totalCapacity = events.reduce(
    (sum, event) =>
      sum + event.tiers.reduce((tierSum, tier) => tierSum + tier.maxQuantity, 0),
    0,
  )
  const revenuePerEvent =
    events.length > 0 ? Math.round((metrics?.grossRevenue ?? 0) / events.length) : 0
  const workspaceName = getWorkspaceName(session.application, session.profile)
  const workspaceTagline = getWorkspaceTagline(session.application)
  const payoutReadiness = getPayoutReadiness(session.application)

  if (loading) {
    return <div className="page-loader">Loading portfolio overview...</div>
  }

  return (
    <div className="dashboard-stack">
      <section className="page-hero page-hero--overview">
        <div className="page-hero__content">
          <p className="eyebrow">Workspace overview</p>
          <h2>{workspaceName}</h2>
          <p>
            {workspaceTagline}
          </p>
          <div className="hero-chip-row">
            <span>{publishedEvents} live event pages</span>
            <span>{draftEvents} drafts still in progress</span>
            <span>{formatMoney(metrics?.grossRevenue ?? 0)} tracked revenue</span>
            <span>{payoutReadiness.ready ? 'Payout profile ready' : 'Payout profile needs attention'}</span>
          </div>
        </div>
        <div className="page-hero__panel">
          <p className="eyebrow">Up next</p>
          {upcomingEvent ? (
            <>
              <h3>{upcomingEvent.title}</h3>
              <p>
                {formatDateTime(upcomingEvent.startAt)} at {upcomingEvent.venue},{' '}
                {upcomingEvent.city}
              </p>
              <div className="hero-chip-row hero-chip-row--compact">
                <span>{upcomingEvent.status}</span>
                <span>{upcomingEvent.visibility}</span>
                <span>{formatMoney(upcomingEvent.grossRevenue)}</span>
              </div>
              <div className="hero-actions">
                <Link className="button button--primary" to={`/events/${upcomingEvent.id}/edit`}>
                  Open event
                </Link>
                <Link className="button button--secondary" to="/events/new">
                  Create event
                </Link>
              </div>
            </>
          ) : (
            <>
              <h3>Your workspace is ready for its first live event.</h3>
              <p>
                Create your first event page to start building ticket tiers,
                launch-ready copy, and a premium guest experience from one dashboard.
              </p>
              <div className="hero-actions">
                <Link className="button button--primary" to="/events/new">
                  Create event
                </Link>
              </div>
            </>
          )}
        </div>
      </section>

      <section className="stats-grid">
        <MetricCard
          label="Gross revenue"
          support="Tracked across your organizer portfolio"
          tone="warm"
          value={formatMoney(metrics?.grossRevenue ?? 0)}
        />
        <MetricCard
          label="Paid orders"
          support="Confirmed checkouts"
          tone="cool"
          value={String(metrics?.paidOrders ?? 0)}
        />
        <MetricCard
          label="RSVPs"
          support="Guests who raised a hand"
          tone="mint"
          value={String(metrics?.totalRsvps ?? 0)}
        />
        <MetricCard
          label="Tickets issued"
          support="Inventory already spoken for"
          tone="sun"
          value={String(metrics?.ticketsIssued ?? 0)}
        />
        <MetricCard
          label="Average revenue per event"
          support="A quick health snapshot"
          tone="ink"
          value={formatMoney(revenuePerEvent)}
        />
        <MetricCard
          label="Planned capacity"
          support="Seats and admissions across tiers"
          tone="rose"
          value={String(totalCapacity)}
        />
      </section>

      <section className="content-grid content-grid--overview">
        <article className="panel panel--feature">
          <div className="panel__header">
            <div>
              <p className="eyebrow">Focus board</p>
              <h3>What deserves attention right now</h3>
            </div>
          </div>

          <div className="focus-list">
            <FocusCard
              label="Drafts waiting for a final pass"
              title={`${draftEvents} event${draftEvents === 1 ? '' : 's'} still in draft`}
              description="Review copy, ticket tiers, and venue details before publishing to guests."
            />
            <FocusCard
              label="Live portfolio"
              title={`${publishedEvents} event${publishedEvents === 1 ? '' : 's'} already visible`}
              description="Keep lineups, timing, and guest messaging polished as plans evolve."
            />
            <FocusCard
              label="Upcoming capacity"
              title={`${totalCapacity} tickets and admissions planned`}
              description="Use capacity as a quick read on venue fit, pricing mix, and launch scale."
            />
          </div>
        </article>

        <article className="panel">
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
                <p>Start by creating your first Eventora event from your dashboard.</p>
              </div>
            ) : (
              orderedEvents.slice(0, 4).map((event) => (
                <Link className="event-row" key={event.id} to={`/events/${event.id}/edit`}>
                  <div>
                    <strong>{event.title}</strong>
                    <span>
                      {formatDateTime(event.startAt)} • {event.venue}, {event.city}
                    </span>
                  </div>
                  <div className="event-row__metrics">
                    <span className={`status-pill status-pill--${event.status}`}>
                      {event.status}
                    </span>
                    <strong>{formatMoney(event.grossRevenue)}</strong>
                  </div>
                </Link>
              ))
            )}
          </div>
        </article>
      </section>
    </div>
  )
}

function MetricCard({
  label,
  support,
  tone,
  value,
}: {
  label: string
  support: string
  tone: string
  value: string
}) {
  return (
    <article className={`metric-card metric-card--${tone}`}>
      <span>{label}</span>
      <strong>{value}</strong>
      <small>{support}</small>
    </article>
  )
}

function FocusCard({
  label,
  title,
  description,
}: {
  label: string
  title: string
  description: string
}) {
  return (
    <article className="focus-card">
      <span>{label}</span>
      <strong>{title}</strong>
      <p>{description}</p>
    </article>
  )
}
