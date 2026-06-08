import { useEffect, useMemo, useState } from 'react'
import {
  Activity,
  BarChart3,
  CalendarDays,
  Megaphone,
  ReceiptText,
  Ticket,
  TrendingUp,
  Users,
  type LucideIcon,
} from 'lucide-react'

import {
  getAdminAnalyticsOverview,
  type AdminAnalyticsDailyPoint,
  type AdminAnalyticsOverview,
} from '../lib/adminAnalytics'
import { copy } from '../lib/copy'
import { getErrorMessage } from '../lib/errorMessages'
import { formatDateTime, formatMoney } from '../lib/formatters'

export function AdminAnalyticsPage() {
  const [analytics, setAnalytics] = useState<AdminAnalyticsOverview | null>(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    let cancelled = false
    async function loadAnalytics() {
      setLoading(true)
      setError(null)
      try {
        const nextAnalytics = await getAdminAnalyticsOverview()
        if (!cancelled) setAnalytics(nextAnalytics)
      } catch (caughtError) {
        if (!cancelled) setError(getErrorMessage(caughtError, copy.loadFailed))
      } finally {
        if (!cancelled) setLoading(false)
      }
    }

    void loadAnalytics()
    return () => {
      cancelled = true
    }
  }, [])

  const recentDaily = useMemo(() => analytics?.daily.slice(-14) ?? [], [analytics])

  if (loading) {
    return <div className="page-loader">{copy.loading}</div>
  }

  if (error || !analytics) {
    return (
      <div className="page-loader">
        <p>{copy.loadFailed}</p>
        {error ? <p className="text-subtle">{error}</p> : null}
      </div>
    )
  }

  return (
    <div className="admin-analytics-page">
      <section className="admin-page-header">
        <div>
          <p className="eyebrow">Analytics</p>
          <h2>Site performance</h2>
          <p>Updated {formatDateTime(analytics.generatedAt)}</p>
        </div>
      </section>

      <section className="admin-metric-grid" aria-label="Site analytics summary">
        <AnalyticsMetric icon={Activity} label="Page views" value={formatNumber(analytics.last30.pageViews)} meta="Last 30 days" />
        <AnalyticsMetric icon={Users} label="Visitors" value={formatNumber(analytics.last30.visitors)} meta="Privacy-safe count" />
        <AnalyticsMetric icon={ReceiptText} label="Revenue" value={formatMoney(analytics.last30.revenue)} meta="Paid orders, 30 days" />
        <AnalyticsMetric icon={Ticket} label="Tickets" value={formatNumber(analytics.last30.tickets)} meta={`${analytics.last30.paidOrders} paid orders`} />
        <AnalyticsMetric icon={Megaphone} label="Campaigns" value={formatNumber(analytics.last30.campaigns)} meta={`${formatMoney(analytics.last30.campaignSpend)} spent`} />
        <AnalyticsMetric icon={TrendingUp} label="Avg order" value={formatMoney(analytics.conversion.averageOrderValue)} meta="Paid ticket orders" />
      </section>

      <section className="admin-analytics-grid">
        <article className="panel admin-analytics-panel">
          <div className="panel__header">
            <div>
              <p className="eyebrow">Trend</p>
              <h3>Last 14 days</h3>
            </div>
            <BarChart3 size={18} aria-hidden />
          </div>
          <DailyChart daily={recentDaily} />
        </article>

        <article className="panel admin-analytics-panel">
          <div className="panel__header">
            <div>
              <p className="eyebrow">Conversion</p>
              <h3>Operating health</h3>
            </div>
            <TrendingUp size={18} aria-hidden />
          </div>
          <div className="admin-analytics-kpis">
            <KpiRow label="Published events" value={formatPercent(analytics.conversion.eventPublishRate)} />
            <KpiRow
              label="Checkout to order"
              value={
                analytics.conversion.checkoutToOrderRate == null
                  ? 'Collecting'
                  : formatPercent(analytics.conversion.checkoutToOrderRate)
              }
            />
            <KpiRow label="New organizers" value={formatNumber(analytics.last30.newOrganizations)} />
            <KpiRow label="Support tickets" value={formatNumber(analytics.last30.supportTickets)} />
            <KpiRow label="Admin actions" value={formatNumber(analytics.last30.adminActions)} />
          </div>
        </article>
      </section>

      <section className="admin-analytics-grid">
        <article className="panel admin-analytics-panel">
          <div className="panel__header">
            <div>
              <p className="eyebrow">Revenue</p>
              <h3>Top events</h3>
            </div>
            <ReceiptText size={18} aria-hidden />
          </div>
          {analytics.topEvents.length === 0 ? (
            <p className="admin-empty-inline">Paid event revenue will appear here.</p>
          ) : (
            <div className="admin-analytics-list">
              {analytics.topEvents.map((event) => (
                <div className="admin-analytics-row" key={event.eventId}>
                  <div>
                    <strong>{event.title || event.eventId}</strong>
                    <span>{event.orders} orders · {event.tickets} tickets</span>
                  </div>
                  <strong>{formatMoney(event.revenue)}</strong>
                </div>
              ))}
            </div>
          )}
        </article>

        <article className="panel admin-analytics-panel">
          <div className="panel__header">
            <div>
              <p className="eyebrow">Totals</p>
              <h3>Platform size</h3>
            </div>
            <CalendarDays size={18} aria-hidden />
          </div>
          <div className="admin-analytics-kpis">
            <KpiRow label="Users" value={formatNumber(analytics.totals.users)} />
            <KpiRow label="Organizers" value={formatNumber(analytics.totals.organizations)} />
            <KpiRow label="Events" value={`${formatNumber(analytics.totals.publishedEvents)} live / ${formatNumber(analytics.totals.events)} total`} />
            <KpiRow label="Ticket orders" value={formatNumber(analytics.totals.ticketOrders)} />
            <KpiRow label="Campaigns" value={formatNumber(analytics.totals.campaigns)} />
            <KpiRow label="Applications waiting" value={formatNumber(analytics.totals.submittedApplications)} />
          </div>
        </article>
      </section>
    </div>
  )
}

function AnalyticsMetric({
  icon: Icon,
  label,
  meta,
  value,
}: {
  icon: LucideIcon
  label: string
  meta: string
  value: string
}) {
  return (
    <article className="admin-metric-card admin-metric-card--static">
      <span className="admin-metric-card__icon" aria-hidden>
        <Icon size={18} />
      </span>
      <span>{label}</span>
      <strong>{value}</strong>
      <small>{meta}</small>
    </article>
  )
}

function DailyChart({ daily }: { daily: AdminAnalyticsDailyPoint[] }) {
  const maxRevenue = Math.max(...daily.map((point) => point.revenue), 1)
  const maxViews = Math.max(...daily.map((point) => point.pageViews), 1)

  return (
    <div className="admin-daily-chart" aria-label="Daily traffic and revenue">
      {daily.map((point) => (
        <div className="admin-daily-chart__day" key={point.date}>
          <div className="admin-daily-chart__bars">
            <span
              className="admin-daily-chart__bar admin-daily-chart__bar--views"
              style={{ height: `${Math.max(8, (point.pageViews / maxViews) * 100)}%` }}
              title={`${point.pageViews} page views`}
            />
            <span
              className="admin-daily-chart__bar admin-daily-chart__bar--revenue"
              style={{ height: `${Math.max(8, (point.revenue / maxRevenue) * 100)}%` }}
              title={`${formatMoney(point.revenue)} revenue`}
            />
          </div>
          <small>{point.date.slice(5)}</small>
        </div>
      ))}
    </div>
  )
}

function KpiRow({ label, value }: { label: string; value: string }) {
  return (
    <div className="admin-analytics-kpi-row">
      <span>{label}</span>
      <strong>{value}</strong>
    </div>
  )
}

function formatNumber(value: number) {
  return new Intl.NumberFormat('en-US').format(Math.round(value))
}

function formatPercent(value: number) {
  return `${Math.round(value * 100)}%`
}
