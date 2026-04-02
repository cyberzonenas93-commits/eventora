import { useEffect, useRef, useState } from 'react'
import { Link, useParams } from 'react-router-dom'
import { httpsCallable } from 'firebase/functions'

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
  checkoutUrl: string
  checkoutId: string
}

export function CheckoutPage() {
  const { eventId } = useParams<{ eventId: string }>()
  const [event, setEvent] = useState<PortalEvent | null>(null)
  const [loading, setLoading] = useState(true)
  const [step, setStep] = useState<Step>('select')
  const [selections, setSelections] = useState<Selections>({})
  const [buyerName, setBuyerName] = useState('')
  const [buyerEmail, setBuyerEmail] = useState('')
  const [buyerPhone, setBuyerPhone] = useState('')
  const [error, setError] = useState<string | null>(null)
  const [submitting, setSubmitting] = useState(false)
  const nameRef = useRef<HTMLInputElement>(null)

  useEffect(() => {
    if (!eventId) { setLoading(false); return }
    getPublicEvent(eventId)
      .then((e) => setEvent(e ?? null))
      .finally(() => setLoading(false))
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

  const paidTiers = event.tiers.filter((t) => t.price > 0)
  const freeTiers = event.tiers.filter((t) => t.price === 0)
  const total = paidTiers.reduce((sum, t) => sum + (selections[t.tierId] ?? 0) * t.price, 0)
  const totalTickets = event.tiers.reduce((sum, t) => sum + (selections[t.tierId] ?? 0), 0)

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
    setError(null)
    setSubmitting(true)
    try {
      const createOrder = httpsCallable<
        {
          eventId: string
          selections: Selections
          buyerName: string
          buyerPhone: string
          buyerEmail: string
        },
        CreateOrderResult
      >(functions, 'createWebEventTicketOrder')

      const { data } = await createOrder({
        eventId: eventId!,
        selections,
        buyerName: buyerName.trim(),
        buyerPhone: buyerPhone.trim(),
        buyerEmail: buyerEmail.trim(),
      })

      if (data.checkoutUrl) {
        // Redirect the browser to the Hubtel hosted checkout page.
        // After payment, Hubtel redirects back to hubtelReturn → which then
        // redirects to /checkout/:orderId/confirmation.
        window.location.href = data.checkoutUrl
      } else {
        setError('Could not start payment. Please try again.')
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

            {paidTiers.length === 0 && freeTiers.length > 0 && (
              <p className="checkout__info">This event has free admission — no ticket purchase needed.</p>
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

                    {!soldOut && !isFree && (
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

                    {isFree && !soldOut && (
                      <span className="checkout__tier-free-note">Register in the app</span>
                    )}
                  </li>
                )
              })}
            </ul>

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
              disabled={!hasSelection || total === 0}
              onClick={() => setStep('details')}
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
              {paidTiers
                .filter((t) => (selections[t.tierId] ?? 0) > 0)
                .map((t) => (
                  <div key={t.tierId} className="checkout__order-row">
                    <span>{t.name} × {selections[t.tierId]}</span>
                    <span>{formatMoney(t.price * (selections[t.tierId] ?? 0))}</span>
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
                />
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
                />
                <span className="checkout__input-hint">
                  Used for mobile money payment and ticket delivery
                </span>
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
                    !buyerName.trim() ||
                    !buyerEmail.trim() ||
                    !buyerPhone.trim()
                  }
                >
                  {submitting ? 'Opening payment…' : `Pay ${formatMoney(total)}`}
                </button>
              </div>

              {submitting && (
                <p className="checkout__redirect-note">
                  Redirecting you to the secure Hubtel payment page…
                </p>
              )}
            </form>
          </div>
        )}

        <p className="checkout__secure-note">
          🔒 Payments processed securely by Hubtel
        </p>
      </div>
    </div>
  )
}
