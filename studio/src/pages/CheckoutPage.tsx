import { useEffect, useRef, useState } from 'react'
import { Link, useNavigate, useParams, useSearchParams } from 'react-router-dom'
import { httpsCallable } from 'firebase/functions'

import { trackEvent } from '../lib/analytics'
import { formatDateTime, formatMoney } from '../lib/formatters'
import { getPublicEvent } from '../lib/portalData'
import { functions } from '../firebaseFunctions'
import type { PortalEvent } from '../lib/types'

type Step = 'select' | 'details'

interface Selections {
  [tierId: string]: number
}

interface CreateOrderResult {
  success: boolean
  orderId: string
  checkoutUrl?: string
  checkoutId?: string
  ticketUrl?: string
}

function isValidEmail(value: string) {
  return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(value.trim())
}

function normalizeGhanaMobileNumber(value: string) {
  const digits = value.replace(/\D/g, '')

  if (/^0\d{9}$/.test(digits)) {
    return `+233${digits.slice(1)}`
  }

  if (/^233\d{9}$/.test(digits)) {
    return `+${digits}`
  }

  return ''
}

function isValidGhanaMobileNumber(value: string) {
  return /^\+233(2[03456789]|5[03456789])\d{7}$/.test(
    normalizeGhanaMobileNumber(value),
  )
}

export function CheckoutPage() {
  const { eventId } = useParams<{ eventId: string }>()
  const navigate = useNavigate()
  const [searchParams] = useSearchParams()
  const partnerRef = searchParams.get('ref') ?? ''
  const [event, setEvent] = useState<PortalEvent | null>(null)
  const [loading, setLoading] = useState(() => Boolean(eventId))
  const [step, setStep] = useState<Step>('select')
  const [selections, setSelections] = useState<Selections>({})
  const [buyerName, setBuyerName] = useState('')
  const [buyerEmail, setBuyerEmail] = useState('')
  const [buyerPhone, setBuyerPhone] = useState('')
  const [error, setError] = useState<string | null>(null)
  const [submitting, setSubmitting] = useState(false)
  const nameRef = useRef<HTMLInputElement>(null)

  useEffect(() => {
    let cancelled = false

    async function loadEvent() {
      if (!eventId) {
        setEvent(null)
        setLoading(false)
        return
      }

      setLoading(true)
      try {
        const e = await getPublicEvent(eventId)
        if (!cancelled) setEvent(e ?? null)
      } finally {
        if (!cancelled) setLoading(false)
      }
    }

    void loadEvent()
    return () => {
      cancelled = true
    }
  }, [eventId])

  useEffect(() => {
    if (step === 'details') nameRef.current?.focus()
  }, [step])

  if (loading) return <div className="page-loader">Loading…</div>

  if (!event) {
    return (
      <div className="public-page">
        <div className="empty-card">
          <h4>Event not found</h4>
          <Link to="/events" className="button button--secondary" style={{ marginTop: '1rem' }}>
            Browse events
          </Link>
        </div>
      </div>
    )
  }

  if (!event.ticketingEnabled || event.tiers.length === 0) {
    return (
      <div className="public-page">
        <div className="empty-card">
          <h4>Tickets are not available for this event.</h4>
          <Link to={`/events/${eventId}`} className="button button--secondary" style={{ marginTop: '1rem' }}>
            Back to event
          </Link>
        </div>
      </div>
    )
  }

  const freeTiers = event.tiers.filter((t) => t.price === 0)
  const analyticsEvent = event
  const total = event.tiers.reduce((sum, t) => sum + (selections[t.tierId] ?? 0) * t.price, 0)
  const totalTickets = event.tiers.reduce((sum, t) => sum + (selections[t.tierId] ?? 0), 0)
  const freeTickets = freeTiers.reduce((sum, t) => sum + (selections[t.tierId] ?? 0), 0)
  const hasMixedSelection = total > 0 && freeTickets > 0

  function adjustQty(tierId: string, delta: number) {
    setSelections((prev) => {
      const current = prev[tierId] ?? 0
      const next = Math.max(0, Math.min(current + delta, 10))
      return { ...prev, [tierId]: next }
    })
  }

  async function handlePay(e: React.FormEvent) {
    e.preventDefault()
    if (submitting) return

    const trimmedName = buyerName.trim()
    const trimmedEmail = buyerEmail.trim().toLowerCase()
    const normalizedPhone = normalizeGhanaMobileNumber(buyerPhone)

    setError(null)

    if (!trimmedName) {
      setError('Enter the buyer name.')
      nameRef.current?.focus()
      return
    }

    if (!isValidEmail(trimmedEmail)) {
      setError('Enter a valid email address for ticket delivery.')
      return
    }

    if (!isValidGhanaMobileNumber(buyerPhone)) {
      setError('Enter a valid Ghana mobile number for Hubtel payment and ticket delivery.')
      return
    }

    setSubmitting(true)
    try {
      const createOrder = httpsCallable<
        {
          eventId: string
          selections: Selections
          buyerName: string
          buyerPhone: string
          buyerEmail: string
          partnerRef?: string
        },
        CreateOrderResult
      >(functions, total > 0 ? 'createWebEventTicketOrder' : 'createFreeWebTicketOrder')

	      const { data } = await createOrder({
	        eventId: eventId!,
	        selections,
        buyerName: trimmedName,
        buyerPhone: normalizedPhone,
	        buyerEmail: trimmedEmail,
        partnerRef: partnerRef || undefined,
	      })
	      void trackEvent('ticket_order_created', {
	        event_id: analyticsEvent.id,
	        tier_count: Object.values(selections).filter((quantity) => quantity > 0).length,
	        ticket_count: totalTickets,
	        value: total,
          source: partnerRef ? 'promoter_link' : searchParams.get('utm_source') || searchParams.get('source') || 'direct',
          ref: partnerRef || undefined,
	      }, {
	        area: 'checkout',
          organizationId: analyticsEvent.organizationId,
          path: `/checkout/${analyticsEvent.id}`,
          role: 'guest',
	      })

	      if (data.checkoutUrl) {
        void trackEvent('payment_initiated', {
          event_id: analyticsEvent.id,
          ticket_count: totalTickets,
          value: total,
          provider: 'hubtel',
          source: partnerRef ? 'promoter_link' : searchParams.get('utm_source') || searchParams.get('source') || 'direct',
          ref: partnerRef || undefined,
        }, {
          area: 'checkout',
          organizationId: analyticsEvent.organizationId,
          path: `/checkout/${analyticsEvent.id}`,
          role: 'guest',
        })
        // Redirect the browser to the Hubtel hosted checkout page.
        // After payment, Hubtel redirects back to hubtelReturn → which then
        // redirects to /tickets/:orderId.
        window.location.href = data.checkoutUrl
      } else if (data.orderId) {
        void trackEvent('payment_completed', {
          event_id: analyticsEvent.id,
          ticket_count: totalTickets,
          value: total,
          provider: 'free',
        }, {
          area: 'checkout',
          organizationId: analyticsEvent.organizationId,
          path: `/checkout/${analyticsEvent.id}`,
          role: 'guest',
        })
        void trackEvent('ticket_issued', {
          event_id: analyticsEvent.id,
          ticket_count: totalTickets,
          value: total,
        }, {
          area: 'checkout',
          organizationId: analyticsEvent.organizationId,
          path: `/checkout/${analyticsEvent.id}`,
          role: 'guest',
        })
        navigate(`/tickets/${encodeURIComponent(data.orderId)}`)
      } else {
        setError('Could not create your tickets. Please try again.')
        setSubmitting(false)
      }
    } catch (err: unknown) {
      const msg =
        err instanceof Error
          ? err.message
          : 'Something went wrong. Please try again.'
      setError(msg)
      setSubmitting(false)
    }
  }

  const hasSelection = totalTickets > 0
  const hasBuyerEmail = buyerEmail.trim().length > 0
  const hasBuyerPhone = buyerPhone.trim().length > 0
  const buyerEmailInvalid = hasBuyerEmail && !isValidEmail(buyerEmail)
  const buyerPhoneInvalid = hasBuyerPhone && !isValidGhanaMobileNumber(buyerPhone)
  const canSubmitDetails =
    buyerName.trim().length > 0 &&
    isValidEmail(buyerEmail) &&
    isValidGhanaMobileNumber(buyerPhone)

  return (
    <div className="public-page">
      <div className="checkout">
        {/* ── Header ─────────────────────────────────────────── */}
        <div className="checkout__header">
          <Link to={`/events/${eventId}`} className="checkout__back">
            ← {event.title}
          </Link>
          <div className="checkout__meta">
            <span>{event.city} · {event.venue}</span>
            <span>{formatDateTime(event.startAt)}</span>
          </div>
          <div className="checkout__steps" aria-label="Checkout steps">
            <span className={`checkout__step${step === 'select' ? ' checkout__step--active' : ' checkout__step--done'}`}>
              1 · Tickets
            </span>
            <span className="checkout__step-sep" aria-hidden="true">›</span>
            <span className={`checkout__step${step === 'details' ? ' checkout__step--active' : ''}`}>
              2 · Your details
            </span>
            <span className="checkout__step-sep" aria-hidden="true">›</span>
            <span className="checkout__step">3 · Payment</span>
          </div>
        </div>

        {/* ── Step 1: Ticket Selection ────────────────────────── */}
        {step === 'select' && (
          <div className="checkout__body">
            <h2 className="checkout__section-title">Select tickets</h2>

            {freeTiers.length > 0 && (
              <p className="checkout__info">Free ticket tiers can be confirmed here and sent by SMS/email.</p>
            )}

            <ul className="checkout__tiers" aria-label="Ticket tiers">
              {event.tiers.map((tier) => {
                const qty = selections[tier.tierId] ?? 0
                const remaining = tier.maxQuantity > 0 ? tier.maxQuantity - tier.sold : Infinity
                const soldOut = remaining <= 0
                const isFree = tier.price === 0

                return (
                  <li
                    key={tier.tierId}
                    className={`checkout__tier${soldOut ? ' checkout__tier--soldout' : ''}`}
                  >
                    <div className="checkout__tier-info">
                      <span className="checkout__tier-name">{tier.name}</span>
                      {tier.description && (
                        <span className="checkout__tier-desc">{tier.description}</span>
                      )}
                      <span className="checkout__tier-price">
                        {isFree ? 'Free' : formatMoney(tier.price)}
                      </span>
                      {soldOut && <span className="checkout__tier-badge">Sold out</span>}
                      {!soldOut && remaining < 20 && remaining !== Infinity && (
                        <span className="checkout__tier-badge checkout__tier-badge--low">
                          {remaining} left
                        </span>
                      )}
                    </div>

                    {!soldOut && (
                      <div className="checkout__qty" role="group" aria-label={`Quantity for ${tier.name}`}>
                        <button
                          type="button"
                          className="checkout__qty-btn"
                          onClick={() => adjustQty(tier.tierId, -1)}
                          disabled={qty === 0}
                          aria-label="Remove one"
                        >
                          −
                        </button>
                        <span className="checkout__qty-count" aria-live="polite">{qty}</span>
                        <button
                          type="button"
                          className="checkout__qty-btn"
                          onClick={() => adjustQty(tier.tierId, 1)}
                          disabled={remaining !== Infinity && qty >= remaining}
                          aria-label="Add one"
                        >
                          +
                        </button>
                      </div>
                    )}

                    {isFree && !soldOut && <span className="checkout__tier-free-note">Free web ticket</span>}
                  </li>
                )
              })}
            </ul>

            {hasMixedSelection && (
              <p className="checkout__error" role="alert">
                Please confirm free tickets separately from paid tickets.
              </p>
            )}

            {hasSelection && (
              <div className="checkout__summary">
                <span>
                  {totalTickets} ticket{totalTickets !== 1 ? 's' : ''}
                </span>
                <strong>{formatMoney(total)}</strong>
              </div>
            )}

            <button
              type="button"
              className="button button--primary checkout__cta"
	              disabled={!hasSelection || hasMixedSelection}
	              onClick={() => {
	                void trackEvent('checkout_started', {
	                  event_id: analyticsEvent.id,
	                  ticket_count: totalTickets,
	                  value: total,
                    source: partnerRef ? 'promoter_link' : searchParams.get('utm_source') || searchParams.get('source') || 'direct',
                    ref: partnerRef || undefined,
	                }, {
                    area: 'checkout',
                    organizationId: analyticsEvent.organizationId,
                    path: `/checkout/${analyticsEvent.id}`,
                    role: 'guest',
                  })
	                void trackEvent('checkout_step', {
                    event_id: analyticsEvent.id,
                    step: 'details',
                  }, {
                    area: 'checkout',
                    organizationId: analyticsEvent.organizationId,
                    path: `/checkout/${analyticsEvent.id}`,
                    role: 'guest',
                  })
	                setStep('details')
	              }}
	            >
              Continue
            </button>
          </div>
        )}

        {/* ── Step 2: Buyer Details ───────────────────────────── */}
        {step === 'details' && (
          <div className="checkout__body">
            <h2 className="checkout__section-title">Your details</h2>

            <div className="checkout__order-summary">
              {event.tiers
                .filter((t) => (selections[t.tierId] ?? 0) > 0)
                .map((t) => (
                  <div key={t.tierId} className="checkout__order-row">
                    <span>{t.name} × {selections[t.tierId]}</span>
                    <span>{t.price === 0 ? 'Free' : formatMoney(t.price * (selections[t.tierId] ?? 0))}</span>
                  </div>
                ))}
              <div className="checkout__order-row checkout__order-row--total">
                <strong>Total</strong>
                <strong>{formatMoney(total)}</strong>
              </div>
            </div>

            <form onSubmit={handlePay} className="checkout__form" noValidate>
              <label className="checkout__label">
                Full name
                <input
                  ref={nameRef}
                  type="text"
                  className="checkout__input"
                  value={buyerName}
                  onChange={(e) => setBuyerName(e.target.value)}
                  placeholder="e.g. Kwame Mensah"
                  required
                  autoComplete="name"
                  disabled={submitting}
                />
              </label>

              <label className="checkout__label">
                Email address
                <input
                  type="email"
                  className="checkout__input"
                  value={buyerEmail}
                  onChange={(e) => setBuyerEmail(e.target.value)}
                  placeholder="you@example.com"
                  required
                  autoComplete="email"
                  aria-invalid={buyerEmailInvalid}
                  disabled={submitting}
                />
                {buyerEmailInvalid && (
                  <span className="checkout__field-error">
                    Enter a real email address for ticket delivery.
                  </span>
                )}
              </label>

              <label className="checkout__label">
                Phone number
                <input
                  type="tel"
                  className="checkout__input"
                  value={buyerPhone}
                  onChange={(e) => setBuyerPhone(e.target.value)}
                  placeholder="+233 XX XXX XXXX"
                  required
                  autoComplete="tel"
                  aria-invalid={buyerPhoneInvalid}
                  disabled={submitting}
                />
                <span className="checkout__input-hint">
                  Used for mobile money payment and ticket delivery
                </span>
                {buyerPhoneInvalid && (
                  <span className="checkout__field-error">
                    Use a valid Ghana mobile number, for example 0550009876.
                  </span>
                )}
              </label>

              {error && <p className="checkout__error" role="alert">{error}</p>}

              <div className="checkout__form-actions">
                <button
                  type="button"
                  className="button button--ghost"
                  onClick={() => { setStep('select'); setError(null) }}
                  disabled={submitting}
                >
                  ← Back
                </button>
                <button
                  type="submit"
                  className="button button--primary"
                  disabled={
                    submitting ||
                    !canSubmitDetails
                  }
                >
                  {submitting
                    ? total > 0 ? 'Opening payment…' : 'Creating tickets…'
                    : total > 0 ? `Pay ${formatMoney(total)}` : 'Confirm free tickets'}
                </button>
              </div>

              {submitting && (
                <p className="checkout__redirect-note">
                  {total > 0
                    ? 'Redirecting you to the secure Hubtel payment page…'
                    : 'Generating your QR tickets and delivery message…'}
                </p>
              )}
            </form>
          </div>
        )}

        <p className="checkout__secure-note">
          {total > 0 ? 'Payments processed securely by Hubtel' : 'Free tickets are delivered by SMS and email when available'}
        </p>
      </div>
    </div>
  )
}
