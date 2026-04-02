import { useEffect, useState } from 'react'
import { Link, useParams } from 'react-router-dom'

import { copy } from '../lib/copy'
import { formatDateTime, formatMoney } from '../lib/formatters'
import { getPublicEvent } from '../lib/portalData'
import type { PortalEvent } from '../lib/types'

export function PublicEventDetailPage() {
  const { eventId } = useParams()
  const [event, setEvent] = useState<PortalEvent | null>(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    let cancelled = false
    if (!eventId) {
      setLoading(false)
      return
    }
    getPublicEvent(eventId)
      .then((e) => {
        if (!cancelled) {
          setEvent(e ?? null)
          if (e == null) setError('Event not found or no longer available.')
        }
      })
      .finally(() => {
        if (!cancelled) setLoading(false)
      })
    return () => { cancelled = true }
  }, [eventId])

  if (loading) {
    return <div className="page-loader">{copy.loading}</div>
  }

  if (error || !event) {
    return (
      <div className="public-page">
        <div className="empty-card">
          <h4>{error ?? 'Event not found'}</h4>
          <Link to="/events" className="button button--secondary" style={{ marginTop: '1rem' }}>
            Back to events
          </Link>
        </div>
      </div>
    )
  }

  const hasTickets = event.ticketingEnabled && event.tiers.length > 0
  const minPrice = hasTickets
    ? Math.min(...event.tiers.map((t) => t.price))
    : null

  return (
    <div className="public-page">
      <article className="public-event-detail">
        {event.coverImageUrl && (
          <div className="public-event-detail__cover">
            <img src={event.coverImageUrl} alt={event.title} />
          </div>
        )}

        <div className="public-event-detail__header">
          <p className="eyebrow">{event.city} · {event.venue}</p>
          <h1>{event.title}</h1>
          <p className="public-event-detail__datetime">{formatDateTime(event.startAt)}</p>
          {event.endAt && (
            <p className="public-event-detail__datetime public-event-detail__datetime--end">
              Ends {formatDateTime(event.endAt)}
            </p>
          )}
          {minPrice !== null && (
            <p className="public-event-detail__price">
              {minPrice === 0 ? 'Free entry' : `From ${formatMoney(minPrice)}`}
            </p>
          )}
        </div>

        <div className="public-event-detail__body">
          {event.description && (
            <section className="public-event-detail__section">
              <h3>About</h3>
              <p>{event.description}</p>
            </section>
          )}
          {(event.performers || event.djs || event.mcs) && (
            <section className="public-event-detail__section">
              <h3>Lineup</h3>
              <p>
                {[event.performers, event.djs, event.mcs].filter(Boolean).join(' · ') || '—'}
              </p>
            </section>
          )}
          {hasTickets && (
            <section className="public-event-detail__section">
              <h3>Tickets</h3>
              <ul className="public-event-detail__tiers">
                {event.tiers.map((tier) => (
                  <li key={tier.tierId}>
                    <div className="public-event-detail__tier-info">
                      <span className="public-event-detail__tier-name">{tier.name}</span>
                      {tier.description && (
                        <span className="public-event-detail__tier-desc">{tier.description}</span>
                      )}
                    </div>
                    <div className="public-event-detail__tier-right">
                      <span className="public-event-detail__tier-price">
                        {tier.price === 0 ? 'Free' : formatMoney(tier.price)}
                      </span>
                      {tier.maxQuantity > 0 && (
                        <span className="public-event-detail__tier-avail">
                          {tier.maxQuantity - tier.sold > 0
                            ? `${tier.maxQuantity - tier.sold} left`
                            : 'Sold out'}
                        </span>
                      )}
                    </div>
                  </li>
                ))}
              </ul>
            </section>
          )}
          {event.tags.length > 0 && (
            <section className="public-event-detail__section">
              <div className="public-event-detail__tags">
                {event.tags.map((tag) => (
                  <span key={tag} className="public-event-detail__tag">{tag}</span>
                ))}
              </div>
            </section>
          )}
        </div>

        <div className="public-event-detail__actions">
          {hasTickets ? (
            <Link
              to={`/checkout/${event.id}`}
              className="button button--primary public-event-detail__get-tickets"
            >
              Get tickets
            </Link>
          ) : (
            <a
              href={`https://vennuzo.page.link/event/${event.id}`}
              target="_blank"
              rel="noopener noreferrer"
              className="button button--primary"
            >
              View in app
            </a>
          )}
          <Link to="/events" className="button button--ghost">
            Back to events
          </Link>
        </div>
      </article>
    </div>
  )
}
