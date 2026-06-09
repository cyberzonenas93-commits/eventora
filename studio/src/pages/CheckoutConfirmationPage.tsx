import { useCallback, useEffect, useRef, useState } from 'react'
import { Link, useParams, useSearchParams } from 'react-router-dom'
import QRCodeLib from 'qrcode'

import { trackEvent } from '../lib/analytics'
import { formatMoney } from '../lib/formatters'

const FUNCTIONS_REGION = 'us-central1'
const FIREBASE_PROJECT_ID = import.meta.env.VITE_FIREBASE_PROJECT_ID || 'eventora-10063'
const FUNCTIONS_ORIGIN = (import.meta.env.VITE_FIREBASE_FUNCTIONS_ORIGIN || '').replace(/\/+$/, '')

// ── Types ──────────────────────────────────────────────────────────────────────

interface IssuedTicket {
  ticketId: string
  orderId: string
  eventId: string
  tierId?: string
  tierName: string
  qrToken: string
  status: string
  attendeeName: string
  price: number
  issuedAt?: number
  issuedAtIso?: string
}

interface OrderDoc {
  eventId: string
  eventTitle: string
  buyerName: string
  buyerEmail?: string
  buyerPhone?: string
  totalAmount: number
  currency: string
  status?: string
  paymentStatus: string
  source: string
  tickets?: IssuedTicket[]
}

interface PublicTicketResponse extends OrderDoc {
  orderId: string
  tickets: IssuedTicket[]
}

class PublicTicketLookupError extends Error {
  readonly status: number

  constructor(message: string, status: number) {
    super(message)
    this.status = status
  }
}

function publicTicketLookupUrl(orderId: string) {
  const origin = FUNCTIONS_ORIGIN || `https://${FUNCTIONS_REGION}-${FIREBASE_PROJECT_ID}.cloudfunctions.net`
  const params = new URLSearchParams({ orderId })
  return `${origin}/getPublicTicket?${params.toString()}`
}

async function fetchPublicTicket(orderId: string, signal?: AbortSignal): Promise<PublicTicketResponse> {
  const response = await fetch(publicTicketLookupUrl(orderId), { signal })
  const payload = await response.json().catch(() => ({})) as { error?: string }

  if (!response.ok) {
    throw new PublicTicketLookupError(payload.error || 'Ticket lookup failed.', response.status)
  }

  const data = payload as PublicTicketResponse
  return {
    ...data,
    orderId,
    tickets: Array.isArray(data.tickets) ? data.tickets : [],
  }
}

// ── QR code rendered client-side ────────────────────────────────────────────────
// The qrToken is a 32-char hex string that organizers scan with their scanner.
// It is an admission secret, so we render the QR locally in the browser — the
// token never leaves the device.
function QRCode({ value, size = 200 }: { value: string; size?: number }) {
  const [dataUrl, setDataUrl] = useState('')

  useEffect(() => {
    let cancelled = false
    QRCodeLib.toDataURL(value, { errorCorrectionLevel: 'M', margin: 1, width: size })
      .then((url) => {
        if (!cancelled) setDataUrl(url)
      })
      .catch((err) => {
        console.error('QR code generation error:', err)
      })
    return () => {
      cancelled = true
    }
  }, [value, size])

  return (
    <img
      src={dataUrl}
      alt={`QR code for ticket ${value}`}
      width={size}
      height={size}
      className="ticket-card__qr"
    />
  )
}

// ── Main Page ──────────────────────────────────────────────────────────────────

type Phase =
  | 'loading'      // Initial public ticket lookup
  | 'pending'      // Order exists, payment not yet confirmed
  | 'cancelled'    // Payment cancelled / failed
  | 'issued'       // Tickets have been issued
  | 'error'        // Unexpected error

export function CheckoutConfirmationPage() {
  const { orderId } = useParams<{ orderId: string }>()
  const [searchParams] = useSearchParams()
  const hubtelStatus = searchParams.get('status') ?? 'success'
  const hubtelReturnedCancelled = hubtelStatus === 'cancelled' || hubtelStatus === 'failed'

  const [phase, setPhase] = useState<Phase>(() =>
    !orderId ? 'error' : hubtelReturnedCancelled ? 'cancelled' : 'loading',
  )
  const [order, setOrder] = useState<OrderDoc | null>(null)
  const [tickets, setTickets] = useState<IssuedTicket[]>([])
  const [errorMsg, setErrorMsg] = useState<string | null>(() =>
    orderId ? null : 'No order ID found in the URL.',
  )
  const trackedReturnRef = useRef<Set<string>>(new Set())
  // How many seconds we've been waiting for ticket issuance
  const [waitSecs, setWaitSecs] = useState(0)

  const trackPurchaseReturn = useCallback((status: 'issued' | 'cancelled', data: OrderDoc, ticketCount: number) => {
    if (!orderId) return
    const trackingKey = `${orderId}:${status}`
    if (trackedReturnRef.current.has(trackingKey)) return
    trackedReturnRef.current.add(trackingKey)
    void trackEvent('ticket_purchase_returned', {
      payment_status: data.paymentStatus || data.status || status,
      source: data.source || 'web',
      status,
      ticket_count: ticketCount,
      value: data.totalAmount || 0,
    }, {
      area: 'checkout',
    })
  }, [orderId])

  useEffect(() => {
    if (!orderId) {
      return undefined
    }

    let timeoutId: number | undefined
    const abortController = new AbortController()

    async function loadTicket() {
      try {
        const data = await fetchPublicTicket(orderId!, abortController.signal)
        const normalizedOrder: OrderDoc = {
          eventId: data.eventId,
          eventTitle: data.eventTitle,
          buyerName: data.buyerName,
          buyerEmail: data.buyerEmail,
          buyerPhone: data.buyerPhone,
          totalAmount: data.totalAmount,
          currency: data.currency,
          status: data.status,
          paymentStatus: data.paymentStatus,
          source: data.source || 'public_ticket',
          tickets: data.tickets,
        }
        setOrder(normalizedOrder)

        const issued = data.tickets.map((ticket) => ({
          ...ticket,
          orderId: ticket.orderId || orderId!,
          eventId: ticket.eventId || data.eventId,
        }))

        if (issued.length > 0) {
          setTickets(issued)
          setPhase('issued')
          trackPurchaseReturn('issued', normalizedOrder, issued.length)
          return
        }

        // No tickets yet — determine phase from payment status
        const ps = data.paymentStatus ?? data.status
        if (ps === 'failed' || ps === 'cancelled' || hubtelReturnedCancelled) {
          setPhase('cancelled')
          trackPurchaseReturn('cancelled', normalizedOrder, 0)
        } else {
          setPhase('pending')
          timeoutId = window.setTimeout(loadTicket, 3000)
        }
      } catch (err) {
        if (abortController.signal.aborted) return
        console.error('Public ticket lookup error:', err)
        setPhase('error')
        if (err instanceof PublicTicketLookupError && err.status === 404) {
          setErrorMsg('Order not found. It may still be processing — please check back shortly.')
        } else {
          setErrorMsg('Could not load your order. Please contact support with your order ID.')
        }
      }
    }

    void loadTicket()

    return () => {
      abortController.abort()
      if (timeoutId) window.clearTimeout(timeoutId)
    }
  }, [hubtelReturnedCancelled, orderId, trackPurchaseReturn])

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
