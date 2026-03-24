import { useEffect, useMemo, useState } from 'react'
import { Link } from 'react-router-dom'
import {
  Area,
  AreaChart,
  CartesianGrid,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
} from 'recharts'

import { copy } from '../lib/copy'
import { formatDateTime, formatMoney } from '../lib/formatters'
import { getErrorMessage } from '../lib/errorMessages'
import { getPayoutReadiness, getWorkspaceName, getWorkspaceTagline } from '../lib/merchantWorkspace'
import { listOrganizerEvents, listOrganizerOrders, loadOverviewMetrics } from '../lib/portalData'
import { usePortalSession } from '../lib/portalSession'
import type { OverviewMetrics, PortalEvent } from '../lib/types'

const MONTH_LABELS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec']

function buildChartDataFromOrders(
  orders: Array<{ createdAt: string; totalAmount: number; ticketCount: number; paymentStatus: string }>,
): Array<{ name: string; revenue: number; registrations: number }> {
  const now = new Date()
  const paidStatuses = ['paid', 'cashatgatepaid', 'complimentary']
  const months: Array<{ name: string; revenue: number; registrations: number; year: number; month: number }> = []
  for (let i = 11; i >= 0; i--) {
    const d = new Date(now.getFullYear(), now.getMonth() - i, 1)
    months.push({
      name: `${MONTH_LABELS[d.getMonth()]} ${d.getFullYear()}`,
      revenue: 0,
      registrations: 0,
      year: d.getFullYear(),
      month: d.getMonth(),
    })
  }
  for (const o of orders) {
    const normalized = String(o.paymentStatus ?? '').replace(/_/g, '').toLowerCase()
    const isPaid = paidStatuses.includes(normalized)
    const date = new Date(o.createdAt)
    if (Number.isNaN(date.getTime())) continue
    const entry = months.find((m) => m.year === date.getFullYear() && m.month === date.getMonth())
    if (entry) {
      if (isPaid) entry.revenue += o.totalAmount
      entry.registrations += o.ticketCount
    }
  }
  return months.map(({ name, revenue, registrations }) => ({ name, revenue, registrations }))
}

export function OverviewPage() {
  const session = usePortalSession()
  const { organizationId } = session
  const [metrics, setMetrics] = useState<OverviewMetrics | null>(null)
  const [events, setEvents] = useState<PortalEvent[]>([])
  const [chartData, setChartData] = useState<Array<{ name: string; revenue: number; registrations: number }>>([])
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [viewTimestamp] = useState(() => Date.now())
  const [chartMounted, setChartMounted] = useState(false)

  useEffect(() => {
    let cancelled = false
    if (!organizationId) {
      return
    }
    const orgId = organizationId ?? ''

    async function run() {
      setLoading(true)
      setError(null)
      try {
        const [nextMetrics, nextEvents, nextOrders] = await Promise.all([
          loadOverviewMetrics(orgId),
          listOrganizerEvents(orgId),
          listOrganizerOrders(orgId),
        ])
        if (!cancelled) {
          setMetrics(nextMetrics)
          setEvents(nextEvents)
          setChartData(
            buildChartDataFromOrders(
              nextOrders.map((o) => ({
                createdAt: o.createdAt,
                totalAmount: o.totalAmount,
                ticketCount: o.ticketCount,
                paymentStatus: o.paymentStatus,
              })),
            ),
          )
        }
      } catch (e) {
        if (!cancelled) {
          setError(getErrorMessage(e, copy.overviewLoadFailed))
          setMetrics(null)
          setEvents([])
          setChartData([])
        }
      } finally {
        if (!cancelled) {
          setLoading(false)
        }
      }
    }

    void run()
    return () => {
      cancelled = true
    }
  }, [organizationId])

  useEffect(() => {
    const t = setTimeout(() => setChartMounted(true), 100)
    return () => clearTimeout(t)
  }, [])

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
    return <div className="page-loader">{copy.loading}</div>
  }

  if (error) {
    return (
      <div className="page-loader">
        <p>{copy.overviewLoadFailed}</p>
        <p className="text-subtle">{error}</p>
        <p className="text-subtle" style={{ marginTop: '0.5rem', fontSize: '0.9rem' }}>{copy.pleaseTryAgain}</p>
      </div>
    )
  }

  return (
    <div className="dashboard-stack">
      <section className="page-hero page-hero--overview">
        <div className="page-hero__content">
          <p className="eyebrow">Workspace overview</p>
          <h2>{workspaceName}</h2>
          {workspaceTagline ? <p>{workspaceTagline}</p> : null}
          <div className="hero-chip-row">
            <span>{publishedEvents} live events</span>
            <span>{draftEvents} drafts</span>
            <span>{formatMoney(metrics?.grossRevenue ?? 0)} revenue</span>
            <span>{payoutReadiness.ready ? 'Payout ready' : 'Payout needs attention'}</span>
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
              <h3>Ready for your first event.</h3>
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
          tone="warm"
          value={formatMoney(metrics?.grossRevenue ?? 0)}
          icon="💰"
        />
        <MetricCard
          label="Paid orders"
          tone="cool"
          value={String(metrics?.paidOrders ?? 0)}
          icon="🎟️"
        />
        <MetricCard
          label="RSVPs"
          tone="mint"
          value={String(metrics?.totalRsvps ?? 0)}
          icon="✅"
        />
        <MetricCard
          label="Tickets issued"
          tone="sun"
          value={String(metrics?.ticketsIssued ?? 0)}
          icon="📋"
        />
        <MetricCard
          label="Avg revenue / event"
          tone="ink"
          value={formatMoney(revenuePerEvent)}
          icon="📈"
        />
        <MetricCard
          label="Planned capacity"
          tone="rose"
          value={String(totalCapacity)}
          icon="🏟️"
        />
      </section>

      <section className="panel">
        <div className="panel__header">
          <div>
            <p className="eyebrow">Quick Actions</p>
            <h3>Jump to what matters</h3>
          </div>
        </div>
        <div style={{ padding: '1rem 1.5rem' }}>
          <div className="quick-actions">
            <Link className="quick-action-btn" to="/studio/events/new">
              <span className="quick-action-btn__icon">✦</span>
              Create event
            </Link>
            <Link className="quick-action-btn" to="/studio/events">
              <span className="quick-action-btn__icon">◈</span>
              Manage events
            </Link>
            <Link className="quick-action-btn" to="/studio/orders">
              <span className="quick-action-btn__icon">◻</span>
              View orders
            </Link>
            <Link className="quick-action-btn" to="/studio/payments">
              <span className="quick-action-btn__icon">◈</span>
              Payments
            </Link>
            <Link className="quick-action-btn" to="/studio/promote">
              <span className="quick-action-btn__icon">↗</span>
              Promote
            </Link>
          </div>
        </div>
      </section>

      <section className="overview-chart-section">
        <article className="panel overview-chart-panel">
          <div className="panel__header">
            <div>
              <p className="eyebrow">Performance over time</p>
              <h3>Revenue and tickets by month</h3>
            </div>
          </div>
          <div className="overview-chart-wrap">
            {chartMounted && (
              <ResponsiveContainer width="100%" height={320} minHeight={280}>
                <AreaChart data={chartData} margin={{ top: 12, right: 12, left: 0, bottom: 0 }}>
                  <defs>
                    <linearGradient id="overviewRevenueFill" x1="0" y1="0" x2="0" y2="1">
                      <stop offset="5%" stopColor="#6366f1" stopOpacity={0.35} />
                      <stop offset="95%" stopColor="#6366f1" stopOpacity={0} />
                    </linearGradient>
                    <linearGradient id="overviewRegistrationsFill" x1="0" y1="0" x2="0" y2="1">
                      <stop offset="5%" stopColor="#22c55e" stopOpacity={0.35} />
                      <stop offset="95%" stopColor="#22c55e" stopOpacity={0} />
                    </linearGradient>
                  </defs>
                  <CartesianGrid strokeDasharray="3 3" vertical={false} stroke="var(--line-strong)" />
                  <XAxis
                    dataKey="name"
                    axisLine={false}
                    tickLine={false}
                    tick={{ fill: 'var(--muted)', fontSize: 11 }}
                  />
                  <YAxis
                    yAxisId="left"
                    axisLine={false}
                    tickLine={false}
                    tick={{ fill: 'var(--muted)', fontSize: 11 }}
                    tickFormatter={(v) => (v >= 1000 ? `${v / 1000}k` : String(v))}
                  />
                  <YAxis
                    yAxisId="right"
                    orientation="right"
                    axisLine={false}
                    tickLine={false}
                    tick={{ fill: 'var(--muted)', fontSize: 11 }}
                  />
                  <Tooltip
                    contentStyle={{
                      backgroundColor: 'var(--panel-strong)',
                      border: '1px solid var(--line)',
                      borderRadius: 'var(--card-radius)',
                      color: 'var(--text)',
                    }}
                    formatter={(value, name) => {
                      const v = Number(value ?? 0)
                      if (name === 'revenue') return [formatMoney(v), 'Revenue']
                      if (name === 'registrations') return [v, 'Tickets']
                      return [v, String(name)]
                    }}
                  />
                  <Area
                    yAxisId="left"
                    type="monotone"
                    dataKey="revenue"
                    stroke="#6366f1"
                    strokeWidth={2}
                    fill="url(#overviewRevenueFill)"
                  />
                  <Area
                    yAxisId="right"
                    type="monotone"
                    dataKey="registrations"
                    stroke="#22c55e"
                    strokeWidth={2}
                    fill="url(#overviewRegistrationsFill)"
                  />
                </AreaChart>
              </ResponsiveContainer>
            )}
          </div>
        </article>
      </section>

      <section className="content-grid content-grid--overview">
        <article className="panel panel--feature">
          <div className="panel__header">
            <div>
              <p className="eyebrow">Focus board</p>
              <h3>What needs attention</h3>
            </div>
          </div>

          <div className="focus-list">
            <FocusCard
              label="Drafts waiting for a final pass"
              title={`${draftEvents} event${draftEvents === 1 ? '' : 's'} still in draft`}
            />
            <FocusCard
              label="Live portfolio"
              title={`${publishedEvents} event${publishedEvents === 1 ? '' : 's'} already visible`}
            />
            <FocusCard
              label="Upcoming capacity"
              title={`${totalCapacity} tickets and admissions planned`}
            />
          </div>
        </article>

        <article className="panel">
          <div className="panel__header">
            <div>
              <p className="eyebrow">Recent events</p>
              <h3>Closest events to the door and ticket desk</h3>
            </div>
            <Link className="text-link" to="/studio/events">
              View all
            </Link>
          </div>

          <div className="event-list">
            {events.length === 0 ? (
              <div className="empty-card">
                <h4>No events yet</h4>
                <p>Create your first event.</p>
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
  tone,
  value,
  icon,
}: {
  label: string
  tone: string
  value: string
  icon?: string
}) {
  return (
    <article className={`metric-card metric-card--${tone}`}>
      {icon ? <span style={{ fontSize: '1.25rem', opacity: 0.7 }}>{icon}</span> : null}
      <span>{label}</span>
      <strong>{value}</strong>
    </article>
  )
}

function FocusCard({
  label,
  title,
}: {
  label: string
  title: string
}) {
  return (
    <article className="focus-card">
      <span>{label}</span>
      <strong>{title}</strong>
    </article>
  )
}
