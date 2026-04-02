import { useEffect, useState } from 'react'
import { Link, useParams, useSearchParams } from 'react-router-dom'
import { getFirestore, doc, onSnapshot } from 'firebase/firestore'

import { app } from '../firebaseApp'
import { formatMoney } from '../lib/formatters'

const db = getFirestore(app)

// ── Types ──────────────────────────────────────────────────────────────────────

interface IssuedTicket {
  ticketId: string
  orderId: string
  eventId: string
  tierId: string
  tierName: string
  qrToken: string
  status: string
  attendeeName: string
  price: number
  issuedAt: number
  issuedAtIso: string
}

interface OrderDoc {
  eventId: string
  eventTitle: string
  buyerName: string
  buyerEmail: string
  buyerPhone: string
  totalAmount: number
  currency: string
  status: string
  paymentStatus: string
  source: string
  tickets?: Record<string, IssuedTicket>
}

// ── QR code via public API ─────────────────────────────────────────────────────
// The qrToken is a 32-char hex string that organizers scan with their scanner.
// We render it as a QR code image using the free goqr.me API (no dependency needed).
function QRCode({ value, size = 200 }: { value: string; size?: number }) {
  const url = `https://api.qrserver.com/v1/create-qr-code/?size=${size}x${size}&data=${encodeURIComponent(value)}&ecc=M&margin=1`
  return (
    <img
      src={url}
      alt={`QR code for ticket ${value}`}
      width={size}
      height={size}
      className="ticket-card__qr"
      loading="lazy"
    />
  )
}

// ── Main Page ──────────────────────────────────────────────────────────────────

type Phase =
  | 'loading'      // Initial Firestore fetch
  | 'pending'      // Order exists, payment not yet confirmed
  | 'cancelled'    // Payment cancelled / failed
  | 'issued'       // Tickets have been issued
  | 'error'        // Unexpected error

export function CheckoutConfirmationPage() {
  const { orderId } = useParams<{ orderId: string }>()
  const [searchParams] = useSearchParams()
  const hubtelStatus = searchParams.get('status') ?? 'success'

  const [phase, setPhase] = useState<Phase>('loading')
  const [order, setOrder] = useState<OrderDoc | null>(null)
  const [tickets, setTickets] = useState<IssuedTicket[]>([])
  const [errorMsg, setErrorMsg] = useState<string | null>(null)
  // How many seconds we've been waiting for ticket issuance
  const [waitSecs, setWaitSecs] = useState(0)

  useEffect(() => {
    if (!orderId) {
      setPhase('error')
      setErrorMsg('No order ID found in the URL.')
      return
    }

    // If Hubtel told us the payment was cancelled, show that immediately
    // (but still subscribe so we can recover if it flips to paid)
    if (hubtelStatus === 'cancelled' || hubtelStatus === 'failed') {
      setPhase('cancelled')
    }

    const orderRef = doc(db, 'event_ticket_orders', orderId)
    const unsub = onSnapshot(
      orderRef,
      (snap) => {
        if (!snap.exists()) {
          setPhase('error')
          setErrorMsg('Order not found. It may still be processing — please check back shortly.')
          return
        }

        const data = snap.data() as OrderDoc
        setOrder(data)

        const issued = data.tickets ? Object.values(data.tickets) : []

        if (issued.length > 0) {
          setTickets(issued)
          setPhase('issued')
          return
        }

        // No tickets yet — determine phase from payment status
        const ps = data.paymentStatus ?? data.status
        if (ps === 'failed' || ps === 'cancelled') {
          setPhase('cancelled')
        } else {
          // Still pending — waiting for Hubtel callback to issue tickets
          setPhase('pending')
        }
      },
      (err) => {
        console.error('Firestore snapshot error:', err)
        setPhase('error')
        setErrorMsg('Could not load your order. Please contact support with your order ID.')
      },
    )

    return unsub
  }, [orderId, hubtelStatus])

  // Increment wait counter while pending so we can show helpful messaging
  useEffect(() => {
    if (phase !== 'pending') return
    const interval = setInterval(() => setWaitSecs((s) => s + 1), 1000)
    return () => clearInterval(interval)
  }, [phase])

  // ── Render helpers ───────────────────────────────────────────────────────────

  if (phase === 'loading') {
    return (
      <div className="public-page">
        <div className="confirmation confirmation--loading">
          <div className="confirmation__spinner" aria-hidden="true" />
          <p>Loading your order…</p>
        </div>
      </div>
    )
  }

  if (phase === 'cancelled') {
    return (
      <div className="public-page">
        <div className="confirmation confirmation--cancelled">
          <div className="confirmation__icon">✕</div>
          <h2>Payment cancelled</h2>
          <p>Your payment was not completed. No charge was made.</p>
          {order && (
            <Link
              to={`/checkout/${order.eventId}`}
              className="button button--primary"
            >
              Try again
            </Link>
          )}
          <p className="confirmation__order-id">Order ref: {orderId}</p>
        </div>
      </div>
    )
  }

  if (phase === 'error') {
    return (
      <div className="public-page">
        <div className="confirmation confirmation--error">
          <div className="confirmation__icon">⚠</div>
          <h2>Something went wrong</h2>
          <p>{errorMsg}</p>
          {orderId && (
            <p className="confirmation__order-id">Order ref: {orderId}</p>
          )}
          <Link to="/events" className="button button--secondary">
            Browse events
          </Link>
        </div>
      </div>
    )
  }

  if (phase === 'pending') {
    return (
      <div className="public-page">
        <div className="confirmation confirmation--pending">
          <div className="confirmation__spinner" aria-hidden="true" />
          <h2>Processing your payment…</h2>
          <p>
            {waitSecs < 15
              ? 'Your tickets are being generated. This usually takes a few seconds.'
              : waitSecs < 60
              ? 'Still processing — please keep this page open.'
              : "This is taking longer than usual. Your payment may still complete. We\u2019ll update this page automatically."}
          </p>
          <p className="confirmation__order-id">Order ref: {orderId}</p>
          {order?.buyerEmail && (
            <p className="confirmation__email-note">
              A confirmation will also be sent to {order.buyerEmail}.
            </p>
          )}
        </div>
      </div>
    )
  }

  // ── phase === 'issued' ───────────────────────────────────────────────────────

  return (
    <div className="public-page">
      <div className="confirmation confirmation--success">
        <div className="confirmation__success-header">
          <div className="confirmation__icon confirmation__icon--success">✓</div>
          <h2>You're going!</h2>
          {order && (
            <p className="confirmation__event-name">{order.eventTitle}</p>
          )}
          {order && (
            <p className="confirmation__buyer-info">
              Tickets for {order.buyerName} · {formatMoney(order.totalAmount)}
            </p>
          )}
        </div>

        <p className="confirmation__instructions">
          Show any of the QR codes below at the door. You can screenshot or
          bookmark this page — tickets are always available at this URL.
        </p>

        <div className="ticket-list">
          {tickets.map((ticket, i) => (
            <div key={ticket.ticketId} className="ticket-card">
              <div className="ticket-card__header">
                <span className="ticket-card__tier">{ticket.tierName}</span>
                <span className="ticket-card__num">#{i + 1} of {tickets.length}</span>
              </div>

              <div className="ticket-card__qr-wrap">
                <QRCode value={ticket.qrToken} size={220} />
              </div>

              <div className="ticket-card__details">
                <div className="ticket-card__row">
                  <span className="ticket-card__label">Attendee</span>
                  <span className="ticket-card__value">{ticket.attendeeName}</span>
                </div>
                <div className="ticket-card__row">
                  <span className="ticket-card__label">Ticket ID</span>
                  <span className="ticket-card__value ticket-card__value--mono">
                    {ticket.ticketId.slice(-8).toUpperCase()}
                  </span>
                </div>
                <div className="ticket-card__row">
                  <span className="ticket-card__label">Price</span>
                  <span className="ticket-card__value">{formatMoney(ticket.price)}</span>
                </div>
              </div>

              <div className="ticket-card__status">
                <span className="ticket-card__status-dot" />
                Valid
              </div>
            </div>
          ))}
        </div>

        <div className="confirmation__footer">
          <p className="confirmation__order-id">Order ref: {orderId}</p>
          {order?.buyerEmail && (
            <p className="confirmation__email-note">
              A copy has been sent to {order.buyerEmail}.
            </p>
          )}
          <Link to="/events" className="button button--ghost confirmation__browse-link">
            Browse more events
          </Link>
        </div>
      </div>
    </div>
  )
}
