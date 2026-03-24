import { useEffect, useMemo, useState } from 'react'
import { Link } from 'react-router-dom'

import { copy } from '../lib/copy'
import { formatDateTime, formatMoney } from '../lib/formatters'
import { getErrorMessage } from '../lib/errorMessages'
import { listOrganizerOrders } from '../lib/portalData'
import { usePortalSession } from '../lib/portalSession'
import type { PortalOrder } from '../lib/types'

function orderPaymentStatusDisplay(status: string): string {
  const normalized = String(status ?? '').replace(/_/g, ' ').trim().toLowerCase()
  if (normalized === 'paid' || normalized === 'cashatgatepaid' || normalized === 'complimentary') {
    return 'paid'
  }
  if (normalized === 'pending' || normalized === 'initiated') {
    return 'pending'
  }
  return normalized || 'pending'
}

type StatusChip = 'all' | 'paid' | 'pending' | 'other'

export function OrdersPage() {
  const { organizationId } = usePortalSession()
  const [orders, setOrders] = useState<PortalOrder[]>([])
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [query, setQuery] = useState('')
  const [statusChip, setStatusChip] = useState<StatusChip>('all')

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
        const nextOrders = await listOrganizerOrders(orgId)
        if (!cancelled) {
          setOrders(nextOrders)
        }
      } catch (e) {
        if (!cancelled) {
          setError(getErrorMessage(e, copy.ordersLoadFailed))
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

  const paidOrders = orders.filter((o) => orderPaymentStatusDisplay(o.paymentStatus) === 'paid')
  const totalRevenue = paidOrders.reduce((sum, o) => sum + o.totalAmount, 0)
  const totalTickets = orders.reduce((sum, o) => sum + o.ticketCount, 0)

  const filteredOrders = useMemo(() => {
    let list = orders
    if (statusChip === 'paid') list = list.filter((o) => orderPaymentStatusDisplay(o.paymentStatus) === 'paid')
    if (statusChip === 'pending') list = list.filter((o) => orderPaymentStatusDisplay(o.paymentStatus) === 'pending')
    if (statusChip === 'other') list = list.filter((o) => !['paid','pending'].includes(orderPaymentStatusDisplay(o.paymentStatus)))
    const trimmed = query.trim().toLowerCase()
    if (!trimmed) return list
    return list.filter(
      (order) =>
        order.eventTitle.toLowerCase().includes(trimmed) ||
        order.buyerEmail.toLowerCase().includes(trimmed) ||
        order.id.toLowerCase().includes(trimmed),
    )
  }, [orders, query, statusChip])

  if (loading) {
    return <div className="page-loader">{copy.loading}</div>
  }

  if (error) {
    return (
      <div className="page-loader">
        <p>{copy.ordersLoadFailed}</p>
        <p className="text-subtle">{error}</p>
        <p className="text-subtle" style={{ marginTop: '0.5rem', fontSize: '0.9rem' }}>{copy.pleaseTryAgain}</p>
      </div>
    )
  }

  return (
    <div className="dashboard-stack">
      <section className="page-hero page-hero--events">
        <div className="page-hero__content">
          <p className="eyebrow">Ticket orders</p>
          <h2>View and track all ticket sales.</h2>
          <div className="hero-chip-row">
            <span>{orders.length} total orders</span>
            <span>{paidOrders.length} paid</span>
            <span>{formatMoney(totalRevenue)} revenue</span>
          </div>
        </div>
        <div className="page-hero__panel">
          <label className="search-field">
            <span>Search orders</span>
            <input
              onChange={(event) => setQuery(event.target.value)}
              placeholder="Search by event, buyer email, or order ID"
              value={query}
            />
          </label>
          <div className="hero-actions">
            <Link className="button button--secondary" to="/studio/overview">
              Back to overview
            </Link>
            <Link className="button button--secondary" to="/studio/events">
              View events
            </Link>
          </div>
        </div>
      </section>

      <section className="stats-grid stats-grid--compact">
        <MetricCard label="Orders" value={String(orders.length)} />
        <MetricCard label="Paid orders" value={String(paidOrders.length)} />
        <MetricCard label="Revenue" value={formatMoney(totalRevenue)} />
        <MetricCard label="Tickets issued" value={String(totalTickets)} />
      </section>

      <article className="panel">
        <div className="panel__header">
          <div>
            <p className="eyebrow">Order list</p>
            <h3>Ticket orders</h3>
          </div>
          <div style={{ display: 'flex', gap: '0.75rem', alignItems: 'center', flexWrap: 'wrap' }}>
            <div className="orders-filter-chips">
              {(['all', 'paid', 'pending', 'other'] as const).map((chip) => (
                <button
                  key={chip}
                  type="button"
                  className={`orders-filter-chip${statusChip === chip ? ' orders-filter-chip--active' : ''}`}
                  onClick={() => setStatusChip(chip)}
                >
                  {chip === 'all' ? 'All' : chip === 'paid' ? 'Paid' : chip === 'pending' ? 'Pending' : 'Other'}
                </button>
              ))}
            </div>
            <Link className="text-link" to="/studio/events">
              View events
            </Link>
          </div>
        </div>

        {orders.length === 0 ? (
          <div className="empty-card">
            <h4>No orders yet</h4>
            <p>Ticket orders will appear here once customers purchase.</p>
          </div>
        ) : filteredOrders.length === 0 ? (
          <div className="empty-card">
            <h4>No matches</h4>
            <p>{query.trim() ? `No orders match "${query}".` : `No ${statusChip} orders.`}</p>
          </div>
        ) : (
          <div className="orders-table-wrap">
            <table className="orders-table">
              <thead>
                <tr>
                  <th>Event</th>
                  <th>Buyer</th>
                  <th>Date</th>
                  <th>Tickets</th>
                  <th>Status</th>
                  <th>Amount</th>
                  <th></th>
                </tr>
              </thead>
              <tbody>
                {filteredOrders.map((order) => (
                  <tr key={order.id}>
                    <td><strong>{order.eventTitle}</strong></td>
                    <td className="cell-muted">{order.buyerEmail || '—'}</td>
                    <td className="cell-muted">{formatDateTime(order.createdAt)}</td>
                    <td>{order.ticketCount}</td>
                    <td>
                      <span className={`status-pill status-pill--${orderPaymentStatusDisplay(order.paymentStatus) === 'paid' ? 'paid' : 'pending'}`}>
                        {orderPaymentStatusDisplay(order.paymentStatus)}
                      </span>
                    </td>
                    <td className="cell-amount">{formatMoney(order.totalAmount)}</td>
                    <td>
                      <Link className="button button--ghost" style={{ padding: '0.35rem 0.7rem', fontSize: '0.76rem' }} to={`/studio/events/${order.eventId}/edit`}>
                        Event
                      </Link>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </article>
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
