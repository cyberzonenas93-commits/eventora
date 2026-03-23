import { useEffect, useMemo, useState } from 'react'
import { Link } from 'react-router-dom'

import { copy } from '../lib/copy'
import { formatDateTime, formatMoney } from '../lib/formatters'
import { getErrorMessage } from '../lib/errorMessages'
import { listOrganizerContacts } from '../lib/portalData'
import { usePortalSession } from '../lib/portalSession'
import type { PortalContact } from '../lib/types'

export function ContactsPage() {
  const { organizationId } = usePortalSession()
  const [contacts, setContacts] = useState<PortalContact[]>([])
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [query, setQuery] = useState('')

  useEffect(() => {
    let cancelled = false
    if (!organizationId) return
    async function run() {
      setLoading(true)
      setError(null)
      try {
        const next = await listOrganizerContacts(organizationId ?? '')
        if (!cancelled) setContacts(next)
      } catch (e) {
        if (!cancelled) {
          setError(getErrorMessage(e, copy.contactsLoadFailed))
        }
      } finally {
        if (!cancelled) setLoading(false)
      }
    }
    void run()
    return () => {
      cancelled = true
    }
  }, [organizationId])

  const filtered = useMemo(() => {
    const q = query.trim().toLowerCase()
    if (!q) return contacts
    return contacts.filter(
      (c) =>
        c.email.toLowerCase().includes(q) ||
        c.displayName.toLowerCase().includes(q) ||
        c.lastEventTitle.toLowerCase().includes(q),
    )
  }, [contacts, query])

  if (loading) {
    return <div className="page-loader">{copy.loading}</div>
  }
  if (error) {
    return (
      <div className="page-loader">
        <p>{copy.contactsLoadFailed}</p>
        <p className="text-subtle">{error}</p>
        <p className="text-subtle" style={{ marginTop: '0.5rem', fontSize: '0.9rem' }}>{copy.pleaseTryAgain}</p>
      </div>
    )
  }

  return (
    <div className="dashboard-stack">
      <section className="page-hero page-hero--events">
        <div className="page-hero__content">
          <p className="eyebrow">Contacts</p>
          <h2>Attendees and customers.</h2>
          <div className="hero-chip-row">
            <span>{contacts.length} contacts</span>
            <span>{contacts.reduce((s, c) => s + c.orderCount, 0)} orders</span>
          </div>
        </div>
        <div className="page-hero__panel">
          <label className="search-field">
            <span>Search contacts</span>
            <input
              onChange={(e) => setQuery(e.target.value)}
              placeholder="Search by name, email, or event"
              value={query}
            />
          </label>
          <div className="hero-actions">
            <Link className="button button--secondary" to="/studio/overview">
              Back to overview
            </Link>
            <Link className="button button--secondary" to="/studio/orders">
              View orders
            </Link>
          </div>
        </div>
      </section>

      <section className="content-grid">
        <article className="panel">
          <div className="panel__header">
            <div>
              <p className="eyebrow">Contact list</p>
              <h3>People who have ordered or RSVP&apos;d</h3>
            </div>
            <Link className="text-link" to="/studio/events">
              View events
            </Link>
          </div>
          <div className="event-list">
            {contacts.length === 0 ? (
              <div className="empty-card">
                <h4>No contacts yet</h4>
                <p>Contacts will appear here when customers order tickets or RSVP.</p>
              </div>
            ) : filtered.length === 0 ? (
              <div className="empty-card">
                <h4>No matches for &quot;{query}&quot;</h4>
              </div>
            ) : (
              filtered.map((c) => (
                <div className="event-row" key={c.email}>
                  <div>
                    <strong>{c.displayName}</strong>
                    <span>
                      {c.email}
                      {c.phone ? ` • ${c.phone}` : ''}
                    </span>
                    <span className="text-subtle">
                      Last: {c.lastEventTitle} • {formatDateTime(c.lastActivityAt)}
                    </span>
                  </div>
                  <div className="event-row__metrics">
                    <span>{c.orderCount} order(s)</span>
                    <strong>{formatMoney(c.totalSpent)}</strong>
                  </div>
                </div>
              ))
            )}
          </div>
        </article>
      </section>
    </div>
  )
}
