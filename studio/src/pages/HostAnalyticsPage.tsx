import { useEffect, useMemo, useState, type ReactNode } from 'react'
import { httpsCallable } from 'firebase/functions'
import {
  Activity,
  Banknote,
  BarChart3,
  Brain,
  Download,
  DoorOpen,
  Filter,
  LineChart,
  Megaphone,
  PackageSearch,
  ReceiptText,
  RefreshCw,
  Send,
  Share2,
  Ticket,
  Users,
  WalletCards,
  type LucideIcon,
} from 'lucide-react'
import {
  Area,
  AreaChart,
  Bar,
  BarChart,
  CartesianGrid,
  Cell,
  Funnel,
  FunnelChart,
  LabelList,
  ResponsiveContainer,
  Tooltip,
  XAxis,
  YAxis,
} from 'recharts'

import { functions } from '../firebaseFunctions'
import { getErrorMessage } from '../lib/errorMessages'
import { formatDateTime, formatMoney } from '../lib/formatters'
import { listOrganizerEvents } from '../lib/portalData'
import { usePortalSession } from '../lib/portalSession'
import type { PortalEvent } from '../lib/types'

type AnalyticsTab = 'overview' | 'sales' | 'audience' | 'funnel' | 'marketing' | 'door' | 'inventory' | 'reports'

interface HostAnalyticsOverview {
  success: boolean
  generatedAt: string
  organizationId: string
  eventId: string | null
  aggregateSources: Record<string, number>
  executive: {
    grossSales: number
    netRevenue: number
    ticketsSold: number
    rsvps: number
    conversionRate: number
    eventPageViews: number
    likesOrSaves: number
    shares: number
    campaignSpend: number
    roi: number
    cashAtGateCollected: number
    refunds: number
    payoutReadyBalance: number
    insight: string
  }
  sales: {
    overTime: Array<{ date: string; grossSales: number; tickets: number; orders: number }>
    tierBreakdown: Array<{ tierId: string; eventTitle: string; tierName: string; price: number; capacity: number; sold: number; revenue: number; soldThrough: number }>
    averageOrderValue: number
    buyerCount: number
    ticketCount: number
    compTickets: number
    cashAtGateTickets: number
    failedPayments: number
    pendingPayments: number
    refunds: number
    abandonedCheckout: number
    fastestTier: { tierName: string; soldThrough: number } | null
    suggestedTierToPromote: { tierName: string; soldThrough: number } | null
  }
  audience: {
    ageGenderAvailable: boolean
    cities: Array<{ city: string; count: number }>
    returningAttendees: number
    newAttendees: number
    topBuyers: Array<{ name: string; email: string; spend: number; tickets: number }>
    rsvpToPurchaseConversion: number
    likedSavedNotPurchased: number
    waitlistOrInterested: number
  }
  funnelRows: Array<{ label: string; value: number; conversionFromPrevious: number }>
  marketing: {
    attribution: Array<{ source: string; linkClicks: number; pageViews: number; rsvps: number; ticketsSold: number; revenue: number; conversionRate: number; costPerTicket: number; roi: number }>
    campaigns: Array<{ id: string; name: string; eventTitle: string; channels: string[]; clicks: number; pageViews: number; rsvps: number; ticketsSold: number; revenue: number; spendGhs: number; conversionRate: number; costPerTicket: number; roi: number }>
  }
  promoters: Array<{ id: string; name: string; refCode: string; clicks: number; sales: number; rsvps: number; revenue: number; commissionOwed: number; conversionRate: number; fraudSignals: number }>
  door: {
    ticketsIssued: number
    guestsAdmitted: number
    noShows: number
    duplicateScanAttempts: number
    invalidScans: number
    cashCollectedAtGate: number
    entryPace: Array<{ hour: string; admits: number }>
    peakEntryWindow: { hour: string; admits: number } | null
    scanLogs: Array<{ id: string; attendeeName: string; tierName: string; staffMember: string; role: string; outcome: string; createdAt: string }>
  }
  inventory: {
    salesByItem: Array<{ id: string; itemName: string; category: string; stock: number; soldCount: number; salesGhs: number; costOfGoodsGhs: number; grossMarginGhs: number; lowStock: boolean }>
    salesByStaff: Array<{ staffId: string; staffName: string; role: string; openTabs: number; closedTabs: number; salesGhs: number }>
    openTabs: number
    closedTabs: number
    voidedOrders: number
    grossMargin: number
    costOfGoodsSold: number
    lowStockAlerts: Array<{ itemName: string; stock: number }>
    tablePackagePerformance: Array<{ id: string; name: string; priceGhs: number; quantity: number; booked: number; revenue: number; soldThrough: number }>
  }
  crm: {
    actions: Array<{ id: string; label: string; audienceSize: number; segment: string }>
  }
  aiInsights: Array<{ id: string; title: string; body: string }>
  reports: {
    csvExports: string[]
    pdfReports: string[]
  }
}

const getHostAnalyticsOverview = httpsCallable<
  { organizationId: string; eventId?: string | null },
  HostAnalyticsOverview
>(functions, 'getHostAnalyticsOverview')

const tabs: Array<{ id: AnalyticsTab; label: string }> = [
  { id: 'overview', label: 'Overview' },
  { id: 'sales', label: 'Sales' },
  { id: 'audience', label: 'Audience' },
  { id: 'funnel', label: 'Funnel' },
  { id: 'marketing', label: 'Marketing' },
  { id: 'door', label: 'Door' },
  { id: 'inventory', label: 'Inventory' },
  { id: 'reports', label: 'Reports' },
]

const chartColors = ['#0f766e', '#f59e0b', '#7c3aed', '#ef4444', '#2563eb', '#16a34a']

export function HostAnalyticsPage() {
  const { organizationId } = usePortalSession()
  const [events, setEvents] = useState<PortalEvent[]>([])
  const [selectedEventId, setSelectedEventId] = useState('all')
  const [analytics, setAnalytics] = useState<HostAnalyticsOverview | null>(null)
  const [activeTab, setActiveTab] = useState<AnalyticsTab>('overview')
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    let cancelled = false
    if (!organizationId) return
    listOrganizerEvents(organizationId)
      .then((items) => {
        if (!cancelled) setEvents(items)
      })
      .catch(() => undefined)
    return () => {
      cancelled = true
    }
  }, [organizationId])

  useEffect(() => {
    let cancelled = false
    if (!organizationId) return
    void Promise.resolve().then(() => {
      if (cancelled) return
      setLoading(true)
      setError(null)
      getHostAnalyticsOverview({
        organizationId,
        eventId: selectedEventId === 'all' ? null : selectedEventId,
      })
        .then((result) => {
          if (!cancelled) setAnalytics(result.data)
        })
        .catch((err) => {
          if (!cancelled) setError(getErrorMessage(err, 'Could not load host analytics.'))
        })
        .finally(() => {
          if (!cancelled) setLoading(false)
        })
    })
    return () => {
      cancelled = true
    }
  }, [organizationId, selectedEventId])

  const funnelData = useMemo(
    () => analytics?.funnelRows.map((row) => ({ name: row.label, value: row.value })) ?? [],
    [analytics],
  )

  if (loading) {
    return <div className="page-loader">Loading analytics…</div>
  }

  if (error || !analytics) {
    return (
      <div className="page-loader">
        <p>Could not load host analytics.</p>
        {error ? <p className="text-subtle">{error}</p> : null}
      </div>
    )
  }

  return (
    <div className="host-analytics-page">
      <section className="analytics-hero">
        <div>
          <p className="eyebrow">Host analytics</p>
          <h2>Know what is selling, leaking, converting, and working.</h2>
          <p>
            A first-class command center for sales, audience, funnel, marketing attribution,
            door operations, inventory, CRM actions, and AI recommendations.
          </p>
          <div className="analytics-hero__insight">
            <Brain size={18} aria-hidden />
            <span>{analytics.executive.insight || 'Analytics insights will appear as traffic, orders, campaigns, and check-ins arrive.'}</span>
          </div>
        </div>
        <div className="analytics-hero__panel">
          <label htmlFor="host-analytics-event-scope">
            <Filter size={15} aria-hidden />
            Event scope
          </label>
          <select id="host-analytics-event-scope" value={selectedEventId} onChange={(e) => setSelectedEventId(e.target.value)}>
            <option value="all">All events</option>
            {events.map((event) => (
              <option key={event.id} value={event.id}>{event.title}</option>
            ))}
          </select>
          <small>Updated {formatDateTime(analytics.generatedAt)}</small>
        </div>
      </section>

      <section className="analytics-snapshot-grid">
        <SnapshotCard icon={Banknote} label="Gross sales" value={formatMoney(analytics.executive.grossSales)} />
        <SnapshotCard icon={WalletCards} label="Net revenue after fees" value={formatMoney(analytics.executive.netRevenue)} />
        <SnapshotCard icon={Ticket} label="Tickets sold" value={formatNumber(analytics.executive.ticketsSold)} />
        <SnapshotCard icon={Users} label="RSVPs" value={formatNumber(analytics.executive.rsvps)} />
        <SnapshotCard icon={LineChart} label="Conversion rate" value={`${analytics.executive.conversionRate}%`} />
        <SnapshotCard icon={Activity} label="Event page views" value={formatNumber(analytics.executive.eventPageViews)} />
        <SnapshotCard icon={Share2} label="Likes / saves / shares" value={`${formatNumber(analytics.executive.likesOrSaves)} / ${formatNumber(analytics.executive.shares)}`} />
        <SnapshotCard icon={Megaphone} label="Campaign spend / ROI" value={`${formatMoney(analytics.executive.campaignSpend)} / ${analytics.executive.roi}%`} />
        <SnapshotCard icon={DoorOpen} label="Cash-at-gate collected" value={formatMoney(analytics.executive.cashAtGateCollected)} />
        <SnapshotCard icon={ReceiptText} label="Refunds" value={formatMoney(analytics.executive.refunds)} />
        <SnapshotCard icon={WalletCards} label="Payout-ready balance" value={formatMoney(analytics.executive.payoutReadyBalance)} />
      </section>

      <nav className="analytics-tabs" aria-label="Analytics sections">
        {tabs.map((tab) => (
          <button
            className={activeTab === tab.id ? 'analytics-tabs__item analytics-tabs__item--active' : 'analytics-tabs__item'}
            key={tab.id}
            onClick={() => setActiveTab(tab.id)}
            type="button"
          >
            {tab.label}
          </button>
        ))}
      </nav>

      {activeTab === 'overview' && (
        <section className="analytics-grid">
          <Panel title="AI insights" eyebrow="Recommended actions" icon={Brain}>
            <div className="analytics-insight-list">
              {analytics.aiInsights.map((insight) => (
                <div className="analytics-insight" key={insight.id}>
                  <strong>{insight.title}</strong>
                  <p>{insight.body}</p>
                </div>
              ))}
            </div>
          </Panel>
          <Panel title="CRM actions" eyebrow="Turn data into outreach" icon={Send}>
            <div className="analytics-action-list">
              {analytics.crm.actions.map((action) => (
                <button className="analytics-action" key={action.id} type="button">
                  <span>{action.label}</span>
                  <strong>{formatNumber(action.audienceSize)}</strong>
                  <small>{action.segment}</small>
                </button>
              ))}
            </div>
          </Panel>
        </section>
      )}

      {activeTab === 'sales' && (
        <section className="analytics-grid">
          <Panel title="Sales over time" eyebrow="Revenue and tickets" icon={LineChart}>
            <ResponsiveContainer height={280} width="100%">
              <AreaChart data={analytics.sales.overTime}>
                <CartesianGrid strokeDasharray="3 3" />
                <XAxis dataKey="date" />
                <YAxis />
                <Tooltip formatter={(value, name) => name === 'grossSales' ? formatMoney(Number(value)) : value} />
                <Area dataKey="grossSales" fill="#0f766e33" stroke="#0f766e" />
                <Area dataKey="tickets" fill="#f59e0b33" stroke="#f59e0b" />
              </AreaChart>
            </ResponsiveContainer>
          </Panel>
          <Panel title="Ticket tier breakdown" eyebrow="Fastest and weakest tiers" icon={Ticket}>
            <MetricStrip
              rows={[
                ['Average order value', formatMoney(analytics.sales.averageOrderValue)],
                ['Buyer count vs tickets', `${formatNumber(analytics.sales.buyerCount)} / ${formatNumber(analytics.sales.ticketCount)}`],
                ['Comp tickets', formatNumber(analytics.sales.compTickets)],
                ['Cash-at-gate tickets', formatNumber(analytics.sales.cashAtGateTickets)],
                ['Failed / pending payments', `${analytics.sales.failedPayments} / ${analytics.sales.pendingPayments}`],
                ['Abandoned checkout', formatNumber(analytics.sales.abandonedCheckout)],
              ]}
            />
            <DataTable
              columns={['Tier', 'Sold', 'Revenue', 'Sold-through']}
              rows={analytics.sales.tierBreakdown.map((tier) => [
                `${tier.tierName} · ${tier.eventTitle}`,
                `${tier.sold}/${tier.capacity || '∞'}`,
                formatMoney(tier.revenue),
                `${tier.soldThrough}%`,
              ])}
            />
          </Panel>
        </section>
      )}

      {activeTab === 'audience' && (
        <section className="analytics-grid">
          <Panel title="Audience intelligence" eyebrow="Attendees, RSVPs, interested users" icon={Users}>
            <MetricStrip
              rows={[
                ['Age / gender', analytics.audience.ageGenderAvailable ? 'Available with consent' : 'Not captured yet'],
                ['Returning vs new', `${formatNumber(analytics.audience.returningAttendees)} / ${formatNumber(analytics.audience.newAttendees)}`],
                ['RSVP-to-purchase', `${analytics.audience.rsvpToPurchaseConversion}%`],
                ['Liked/saved but not purchased', formatNumber(analytics.audience.likedSavedNotPurchased)],
                ['Waitlist / interested audience', formatNumber(analytics.audience.waitlistOrInterested)],
              ]}
            />
            <DataTable
              columns={['Top buyer', 'Spend', 'Tickets']}
              rows={analytics.audience.topBuyers.map((buyer) => [
                buyer.name || buyer.email || 'Buyer',
                formatMoney(buyer.spend),
                formatNumber(buyer.tickets),
              ])}
            />
          </Panel>
          <Panel title="Location segments" eyebrow="CRM-ready" icon={BarChart3}>
            <ResponsiveContainer height={260} width="100%">
              <BarChart data={analytics.audience.cities}>
                <CartesianGrid strokeDasharray="3 3" />
                <XAxis dataKey="city" />
                <YAxis allowDecimals={false} />
                <Tooltip />
                <Bar dataKey="count" fill="#0f766e" />
              </BarChart>
            </ResponsiveContainer>
          </Panel>
        </section>
      )}

      {activeTab === 'funnel' && (
        <section className="analytics-grid analytics-grid--wide">
          <Panel title="Funnel conversion" eyebrow="Where guests leak" icon={Filter}>
            <ResponsiveContainer height={360} width="100%">
              <FunnelChart>
                <Tooltip />
                <Funnel data={funnelData} dataKey="value" nameKey="name">
                  <LabelList dataKey="name" fill="#111827" position="right" />
                  {funnelData.map((_, index) => <Cell fill={chartColors[index % chartColors.length]} key={index} />)}
                </Funnel>
              </FunnelChart>
            </ResponsiveContainer>
            <DataTable
              columns={['Step', 'Volume', 'Conversion from previous']}
              rows={analytics.funnelRows.map((row) => [
                row.label,
                formatNumber(row.value),
                `${row.conversionFromPrevious}%`,
              ])}
            />
          </Panel>
        </section>
      )}

      {activeTab === 'marketing' && (
        <section className="analytics-grid">
          <Panel title="Marketing attribution" eyebrow="Links, campaigns, referrals" icon={Megaphone}>
            <DataTable
              columns={['Source', 'Views/clicks', 'RSVPs', 'Tickets', 'Revenue', 'Conv.', 'ROI']}
              rows={analytics.marketing.attribution.map((row) => [
                row.source,
                `${formatNumber(row.pageViews)} / ${formatNumber(row.linkClicks)}`,
                formatNumber(row.rsvps),
                formatNumber(row.ticketsSold),
                formatMoney(row.revenue),
                `${row.conversionRate}%`,
                `${row.roi}%`,
              ])}
            />
          </Panel>
          <Panel title="Promoters and partners" eyebrow="Commission and performance" icon={Share2}>
            <DataTable
              columns={['Promoter', 'Clicks', 'Sales', 'Revenue', 'Commission', 'Fraud signals']}
              rows={analytics.promoters.map((row) => [
                row.name,
                formatNumber(row.clicks),
                formatNumber(row.sales),
                formatMoney(row.revenue),
                formatMoney(row.commissionOwed),
                formatNumber(row.fraudSignals),
              ])}
            />
          </Panel>
        </section>
      )}

      {activeTab === 'door' && (
        <section className="analytics-grid">
          <Panel title="Door and check-in" eyebrow="Event-day operations" icon={DoorOpen}>
            <MetricStrip
              rows={[
                ['Tickets issued', formatNumber(analytics.door.ticketsIssued)],
                ['Guests admitted', formatNumber(analytics.door.guestsAdmitted)],
                ['No-shows', formatNumber(analytics.door.noShows)],
                ['Duplicate scan attempts', formatNumber(analytics.door.duplicateScanAttempts)],
                ['Invalid scans', formatNumber(analytics.door.invalidScans)],
                ['Cash collected at gate', formatMoney(analytics.door.cashCollectedAtGate)],
                ['Peak entry window', analytics.door.peakEntryWindow ? `${analytics.door.peakEntryWindow.hour} (${analytics.door.peakEntryWindow.admits})` : 'Collecting'],
              ]}
            />
            <DataTable
              columns={['Guest', 'Ticket', 'Staff', 'Outcome', 'Time']}
              rows={analytics.door.scanLogs.map((log) => [
                log.attendeeName || 'Guest',
                log.tierName || 'Ticket',
                log.staffMember || log.role || 'Staff',
                log.outcome || 'validated',
                log.createdAt ? formatDateTime(log.createdAt) : '',
              ])}
            />
          </Panel>
          <Panel title="Entry pace over time" eyebrow="Peak windows" icon={Activity}>
            <ResponsiveContainer height={260} width="100%">
              <BarChart data={analytics.door.entryPace}>
                <CartesianGrid strokeDasharray="3 3" />
                <XAxis dataKey="hour" />
                <YAxis allowDecimals={false} />
                <Tooltip />
                <Bar dataKey="admits" fill="#f59e0b" />
              </BarChart>
            </ResponsiveContainer>
          </Panel>
        </section>
      )}

      {activeTab === 'inventory' && (
        <section className="analytics-grid">
          <Panel title="Inventory and Event Ops" eyebrow="Sales, stock, margin" icon={PackageSearch}>
            <MetricStrip
              rows={[
                ['Open / closed tabs', `${analytics.inventory.openTabs} / ${analytics.inventory.closedTabs}`],
                ['Voided/cancelled orders', formatNumber(analytics.inventory.voidedOrders)],
                ['Gross margin', formatMoney(analytics.inventory.grossMargin)],
                ['Cost of goods sold', formatMoney(analytics.inventory.costOfGoodsSold)],
                ['Low-stock alerts', formatNumber(analytics.inventory.lowStockAlerts.length)],
              ]}
            />
            <DataTable
              columns={['Item', 'Sold', 'Stock', 'Sales', 'Margin']}
              rows={analytics.inventory.salesByItem.map((item) => [
                `${item.itemName} · ${item.category}`,
                formatNumber(item.soldCount),
                item.lowStock ? `${item.stock} low` : formatNumber(item.stock),
                formatMoney(item.salesGhs),
                formatMoney(item.grossMarginGhs),
              ])}
            />
          </Panel>
          <Panel title="Staff and table packages" eyebrow="Operational performance" icon={Users}>
            <DataTable
              columns={['Staff', 'Tabs', 'Sales']}
              rows={analytics.inventory.salesByStaff.map((staff) => [
                `${staff.staffName} · ${staff.role}`,
                `${staff.closedTabs} closed / ${staff.openTabs} open`,
                formatMoney(staff.salesGhs),
              ])}
            />
            <DataTable
              columns={['Package', 'Booked', 'Revenue', 'Sold-through']}
              rows={analytics.inventory.tablePackagePerformance.map((pkg) => [
                pkg.name,
                `${pkg.booked}/${pkg.quantity}`,
                formatMoney(pkg.revenue),
                `${pkg.soldThrough}%`,
              ])}
            />
          </Panel>
        </section>
      )}

      {activeTab === 'reports' && (
        <section className="analytics-grid">
          <Panel title="Exports" eyebrow="CSV and PDF" icon={Download}>
            <div className="analytics-export-grid">
              {analytics.reports.csvExports.map((name) => (
                <button className="button button--secondary" key={name} onClick={() => downloadCsv(name, analytics)} type="button">
                  <Download size={15} aria-hidden />
                  {name} CSV
                </button>
              ))}
              {analytics.reports.pdfReports.map((name) => (
                <button className="button button--primary" key={name} onClick={() => printReport(name)} type="button">
                  <ReceiptText size={15} aria-hidden />
                  {name.replace(/_/g, ' ')} PDF
                </button>
              ))}
            </div>
            <div className="analytics-source-note">
              <RefreshCw size={16} aria-hidden />
              <span>
                Uses aggregated docs first: event_daily_metrics, event_funnel_metrics,
                event_campaign_metrics, event_staff_metrics, and event_inventory_metrics.
                Raw event scans are only used as fallback.
              </span>
            </div>
          </Panel>
        </section>
      )}
    </div>
  )
}

function SnapshotCard({ icon: Icon, label, value }: { icon: LucideIcon; label: string; value: string }) {
  return (
    <article className="analytics-snapshot-card">
      <span aria-hidden><Icon size={17} /></span>
      <small>{label}</small>
      <strong>{value}</strong>
    </article>
  )
}

function Panel({
  children,
  eyebrow,
  icon: Icon,
  title,
}: {
  children: ReactNode
  eyebrow: string
  icon: LucideIcon
  title: string
}) {
  return (
    <article className="panel analytics-panel">
      <div className="panel__header">
        <div>
          <p className="eyebrow">{eyebrow}</p>
          <h3>{title}</h3>
        </div>
        <Icon size={19} aria-hidden />
      </div>
      {children}
    </article>
  )
}

function MetricStrip({ rows }: { rows: Array<[string, string]> }) {
  return (
    <div className="analytics-metric-strip">
      {rows.map(([label, value]) => (
        <div key={label}>
          <span>{label}</span>
          <strong>{value}</strong>
        </div>
      ))}
    </div>
  )
}

function DataTable({ columns, rows }: { columns: string[]; rows: string[][] }) {
  if (rows.length === 0) return <p className="text-subtle">No data yet.</p>
  return (
    <div className="analytics-table-wrap">
      <table className="analytics-table">
        <thead>
          <tr>{columns.map((column) => <th key={column}>{column}</th>)}</tr>
        </thead>
        <tbody>
          {rows.map((row, index) => (
            <tr key={`${row.join(':')}:${index}`}>
              {row.map((cell, cellIndex) => <td key={`${cell}:${cellIndex}`}>{cell}</td>)}
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  )
}

function formatNumber(value: number) {
  return new Intl.NumberFormat('en-US').format(Math.round(value || 0))
}

function downloadCsv(section: string, analytics: HostAnalyticsOverview) {
  const rows = csvRows(section, analytics)
  const csv = rows.map((row) => row.map((cell) => `"${String(cell).replace(/"/g, '""')}"`).join(',')).join('\n')
  const blob = new Blob([csv], { type: 'text/csv;charset=utf-8' })
  const url = URL.createObjectURL(blob)
  const link = document.createElement('a')
  link.href = url
  link.download = `vennuzo-${section}-analytics.csv`
  link.click()
  URL.revokeObjectURL(url)
}

function csvRows(section: string, analytics: HostAnalyticsOverview): string[][] {
  if (section === 'sales') {
    return [['Tier', 'Sold', 'Revenue', 'Sold-through'], ...analytics.sales.tierBreakdown.map((tier) => [tier.tierName, String(tier.sold), String(tier.revenue), `${tier.soldThrough}%`])]
  }
  if (section === 'marketing') {
    return [['Source', 'Views', 'Clicks', 'Tickets', 'Revenue'], ...analytics.marketing.attribution.map((row) => [row.source, String(row.pageViews), String(row.linkClicks), String(row.ticketsSold), String(row.revenue)])]
  }
  if (section === 'door') {
    return [['Guest', 'Ticket', 'Staff', 'Outcome', 'Time'], ...analytics.door.scanLogs.map((log) => [log.attendeeName, log.tierName, log.staffMember, log.outcome, log.createdAt])]
  }
  if (section === 'inventory') {
    return [['Item', 'Sold', 'Stock', 'Sales', 'Margin'], ...analytics.inventory.salesByItem.map((item) => [item.itemName, String(item.soldCount), String(item.stock), String(item.salesGhs), String(item.grossMarginGhs)])]
  }
  return [['Metric', 'Value'], ...Object.entries(analytics.executive).map(([key, value]) => [key, String(value)])]
}

function printReport(name: string) {
  document.title = `Vennuzo ${name.replace(/_/g, ' ')} report`
  window.print()
}
