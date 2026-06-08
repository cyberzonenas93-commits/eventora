import { useEffect, useState } from 'react'
import { Link, useParams } from 'react-router-dom'
import { httpsCallable } from 'firebase/functions'

import { functions } from '../firebaseFunctions'
import { formatDateTime, formatMoney } from '../lib/formatters'

interface SharedFeed {
  event: {
    id: string
    title: string
    startAt: string
    venue: string
    city: string
  }
  rsvps: Array<{
    id: string
    name: string
    phone: string
    email: string
    guestCount: number
    status: string
    wantsTable: boolean
    createdAt: string
  }>
  orders: Array<{
    id: string
    buyerName: string
    buyerPhone: string
    buyerEmail: string
    paymentStatus: string
    totalAmount: number
    ticketCount: number
    createdAt: string
  }>
  summary: {
    rsvpCount: number
    orderCount: number
    paidOrderCount: number
    ticketCount: number
    revenue: number
  }
}

const getSharedOrganizerRsvpFeed = httpsCallable<
  { shareId: string },
  { success: boolean } & SharedFeed
>(functions, 'getSharedOrganizerRsvpFeed')

export function OrganizerFeedPage() {
  const { shareId } = useParams<{ shareId: string }>()
  const [feed, setFeed] = useState<SharedFeed | null>(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    let cancelled = false
    async function run() {
      if (!shareId) return
      setLoading(true)
      setError(null)
      try {
        const result = await getSharedOrganizerRsvpFeed({ shareId })
        if (!cancelled) setFeed(result.data)
      } catch (err) {
        if (!cancelled) setError(err instanceof Error ? err.message : 'Could not load feed.')
      } finally {
        if (!cancelled) setLoading(false)
      }
    }
    void run()
    return () => {
      cancelled = true
    }
  }, [shareId])

  if (loading) return <div className="page-loader">Loading feed...</div>
  if (error || !feed) {
    return (
      <div className="public-page">
        <div className="empty-card">
          <h4>{error ?? 'Feed not found'}</h4>
          <Link className="button button--secondary" to="/events">Browse events</Link>
        </div>
      </div>
    )
  }

  return (
    <div className="public-page">
      <article className="checkout" style={{ maxWidth: 1040 }}>
        <div className="checkout__header">
          <Link className="checkout__back" to={`/events/${feed.event.id}`}>Back to event</Link>
          <h1 style={{ margin: 0 }}>{feed.event.title}</h1>
          <div className="checkout__meta">
            <span>{feed.event.venue}, {feed.event.city}</span>
            <span>{formatDateTime(feed.event.startAt)}</span>
          </div>
        </div>

        <section className="stats-grid stats-grid--compact">
          <Metric label="RSVPs" value={String(feed.summary.rsvpCount)} />
          <Metric label="Orders" value={String(feed.summary.orderCount)} />
          <Metric label="Tickets" value={String(feed.summary.ticketCount)} />
          <Metric label="Revenue" value={formatMoney(feed.summary.revenue)} />
        </section>

        <section className="content-grid" style={{ marginTop: '1rem' }}>
          <article className="panel">
            <div className="panel__header">
              <div>
                <p className="eyebrow">RSVP feed</p>
                <h3>Public registrations</h3>
              </div>
            </div>
            {feed.rsvps.length === 0 ? (
              <p className="text-subtle">No RSVPs yet.</p>
            ) : (
              <div className="orders-table-wrap">
                <table className="orders-table">
                  <thead>
                    <tr>
                      <th>Name</th>
                      <th>Contact</th>
                      <th>Guests</th>
                      <th>Status</th>
                    </tr>
                  </thead>
                  <tbody>
                    {feed.rsvps.map((item) => (
                      <tr key={item.id}>
                        <td><strong>{item.name}</strong></td>
                        <td className="cell-muted">{item.phone || item.email || '-'}</td>
                        <td>{item.guestCount}{item.wantsTable ? ' + table' : ''}</td>
                        <td>{item.status}</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            )}
          </article>

          <article className="panel">
            <div className="panel__header">
              <div>
                <p className="eyebrow">Ticket feed</p>
                <h3>Orders</h3>
              </div>
            </div>
            {feed.orders.length === 0 ? (
              <p className="text-subtle">No orders yet.</p>
            ) : (
              <div className="orders-table-wrap">
                <table className="orders-table">
                  <thead>
                    <tr>
                      <th>Buyer</th>
                      <th>Tickets</th>
                      <th>Status</th>
                      <th>Total</th>
                    </tr>
                  </thead>
                  <tbody>
                    {feed.orders.map((item) => (
                      <tr key={item.id}>
                        <td><strong>{item.buyerName || item.buyerEmail}</strong></td>
                        <td>{item.ticketCount}</td>
                        <td>{item.paymentStatus}</td>
                        <td>{formatMoney(item.totalAmount)}</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            )}
          </article>
        </section>
      </article>
    </div>
  )
}

function Metric({ label, value }: { label: string; value: string }) {
  return (
    <article className="metric-card metric-card--plain">
      <span>{label}</span>
      <strong>{value}</strong>
    </article>
  )
}
