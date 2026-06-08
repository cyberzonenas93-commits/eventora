import { useEffect, useMemo, useState, type FormEvent } from 'react'
import { Link } from 'react-router-dom'
import { httpsCallable } from 'firebase/functions'

import { functions } from '../firebaseFunctions'
import { formatDateTime, formatMoney } from '../lib/formatters'
import { getErrorMessage } from '../lib/errorMessages'
import { listOrganizerEvents } from '../lib/portalData'
import { usePortalSession } from '../lib/portalSession'
import type { PortalEvent } from '../lib/types'

interface TablePackage {
  id: string
  name: string
  description: string
  priceGhs: number
  capacity: number
  quantity: number
  booked: number
  available: number | null
  items: string
  status: string
}

interface TableBooking {
  id: string
  eventId: string
  eventTitle: string
  packageName: string
  buyerName: string
  buyerPhone: string
  buyerEmail: string
  quantity: number
  totalAmount: number
  paymentStatus: string
  status: string
  createdAt: string
}

const createTablePackage = httpsCallable<
  {
    eventId: string
    name: string
    description?: string
    priceGhs: number
    capacity: number
    quantity: number
    items?: string
  },
  { success: boolean; tablePackageId: string }
>(functions, 'createTablePackage')

const listTablePackages = httpsCallable<
  { eventId: string },
  { success: boolean; packages: TablePackage[] }
>(functions, 'listTablePackages')

const listTableBookings = httpsCallable<
  { organizationId: string },
  { success: boolean; bookings: TableBooking[] }
>(functions, 'listTableBookings')

export function TablesPage() {
  const { organizationId } = usePortalSession()
  const [events, setEvents] = useState<PortalEvent[]>([])
  const [selectedEventId, setSelectedEventId] = useState('')
  const [packages, setPackages] = useState<TablePackage[]>([])
  const [bookings, setBookings] = useState<TableBooking[]>([])
  const [loading, setLoading] = useState(true)
  const [submitting, setSubmitting] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [message, setMessage] = useState<string | null>(null)
  const [name, setName] = useState('')
  const [description, setDescription] = useState('')
  const [price, setPrice] = useState('0')
  const [capacity, setCapacity] = useState('4')
  const [quantity, setQuantity] = useState('1')
  const [items, setItems] = useState('')

  useEffect(() => {
    let cancelled = false
    if (!organizationId) return
    async function run() {
      setLoading(true)
      setError(null)
      try {
        const [eventList, bookingResult] = await Promise.all([
          listOrganizerEvents(organizationId ?? ''),
          listTableBookings({ organizationId: organizationId ?? '' }).then((r) => r.data.bookings),
        ])
        if (cancelled) return
        setEvents(eventList)
        setSelectedEventId((current) => current || eventList[0]?.id || '')
        setBookings(bookingResult)
      } catch (err) {
        if (!cancelled) setError(getErrorMessage(err, 'Could not load table packages.'))
      } finally {
        if (!cancelled) setLoading(false)
      }
    }
    void run()
    return () => {
      cancelled = true
    }
  }, [organizationId])

  useEffect(() => {
    let cancelled = false
    if (!selectedEventId) {
      setPackages([])
      return
    }
    async function run() {
      try {
        const result = await listTablePackages({ eventId: selectedEventId })
        if (!cancelled) setPackages(result.data.packages)
      } catch (err) {
        if (!cancelled) setError(getErrorMessage(err, 'Could not load packages for this event.'))
      }
    }
    void run()
    return () => {
      cancelled = true
    }
  }, [selectedEventId])

  const selectedEvent = useMemo(
    () => events.find((item) => item.id === selectedEventId) ?? null,
    [events, selectedEventId],
  )
  const visibleBookings = bookings.filter((booking) => !selectedEventId || booking.eventId === selectedEventId)

  async function handleCreatePackage(e: FormEvent) {
    e.preventDefault()
    if (!selectedEventId || submitting) return
    setSubmitting(true)
    setError(null)
    setMessage(null)
    try {
      await createTablePackage({
        eventId: selectedEventId,
        name: name.trim(),
        description: description.trim() || undefined,
        priceGhs: Number(price || 0),
        capacity: Number(capacity || 1),
        quantity: Number(quantity || 1),
        items: items.trim() || undefined,
      })
      const result = await listTablePackages({ eventId: selectedEventId })
      setPackages(result.data.packages)
      setName('')
      setDescription('')
      setPrice('0')
      setCapacity('4')
      setQuantity('1')
      setItems('')
      setMessage('Table package created.')
    } catch (err) {
      setError(getErrorMessage(err, 'Could not create table package.'))
    } finally {
      setSubmitting(false)
    }
  }

  if (loading) return <div className="page-loader">Loading...</div>

  return (
    <div className="dashboard-stack">
      <section className="page-hero page-hero--events page-hero--wallet-services">
        <div className="page-hero__content">
          <p className="eyebrow">Tables</p>
          <h2>Manage table packages and reservations.</h2>
          <div className="hero-chip-row">
            <span>{packages.length} packages</span>
            <span>{visibleBookings.length} bookings</span>
            <span>{selectedEvent?.title || 'Select event'}</span>
          </div>
        </div>
        <div className="page-hero__panel">
          <label className="search-field">
            <span>Event</span>
            <select value={selectedEventId} onChange={(e) => setSelectedEventId(e.target.value)}>
              {events.map((event) => (
                <option key={event.id} value={event.id}>{event.title}</option>
              ))}
            </select>
          </label>
          <Link className="button button--secondary" to="/studio/events">Events</Link>
        </div>
      </section>

      {error && <p className="checkout__error">{error}</p>}
      {message && <p className="checkout__info">{message}</p>}

      <section className="content-grid">
        <article className="panel">
          <div className="panel__header">
            <div>
              <p className="eyebrow">Inventory</p>
              <h3>Table packages</h3>
            </div>
          </div>
          {packages.length === 0 ? (
            <div className="empty-card">
              <h4>No table packages yet</h4>
              <p>Create VIP tables, booths, bottle-service bundles, or group packages.</p>
            </div>
          ) : (
            <div className="partner-feature-grid">
              {packages.map((item) => (
                <div className="partner-feature-card" key={item.id}>
                  <strong>{item.name}</strong>
                  <p>{item.description || item.items || 'Table package'}</p>
                  <small>{formatMoney(item.priceGhs)} · {item.capacity} seats · {item.available ?? 'Unlimited'} left</small>
                </div>
              ))}
            </div>
          )}
        </article>

        <article className="panel">
          <div className="panel__header">
            <div>
              <p className="eyebrow">Create</p>
              <h3>New table package</h3>
            </div>
          </div>
          <form className="checkout__form" onSubmit={handleCreatePackage}>
            <label className="checkout__label">
              Name
              <input className="checkout__input" value={name} onChange={(e) => setName(e.target.value)} required />
            </label>
            <label className="checkout__label">
              Description
              <textarea className="checkout__input" value={description} onChange={(e) => setDescription(e.target.value)} rows={3} />
            </label>
            <label className="checkout__label">
              Included items
              <textarea className="checkout__input" value={items} onChange={(e) => setItems(e.target.value)} rows={3} />
            </label>
            <div className="form-grid">
              <label className="checkout__label">
                Price GHS
                <input className="checkout__input" min={0} step="0.01" type="number" value={price} onChange={(e) => setPrice(e.target.value)} />
              </label>
              <label className="checkout__label">
                Capacity
                <input className="checkout__input" min={1} type="number" value={capacity} onChange={(e) => setCapacity(e.target.value)} />
              </label>
              <label className="checkout__label">
                Quantity
                <input className="checkout__input" min={1} type="number" value={quantity} onChange={(e) => setQuantity(e.target.value)} />
              </label>
            </div>
            <button className="button button--primary" disabled={submitting || !name.trim() || !selectedEventId} type="submit">
              {submitting ? 'Creating...' : 'Create package'}
            </button>
          </form>
        </article>
      </section>

      <article className="panel">
        <div className="panel__header">
          <div>
            <p className="eyebrow">Bookings</p>
            <h3>Table reservations</h3>
          </div>
        </div>
        {visibleBookings.length === 0 ? (
          <div className="empty-card">
            <h4>No table bookings yet</h4>
            <p>Paid and free table reservations will appear here.</p>
          </div>
        ) : (
          <div className="orders-table-wrap">
            <table className="orders-table">
              <thead>
                <tr>
                  <th>Guest</th>
                  <th>Package</th>
                  <th>Date</th>
                  <th>Status</th>
                  <th>Total</th>
                </tr>
              </thead>
              <tbody>
                {visibleBookings.map((booking) => (
                  <tr key={booking.id}>
                    <td><strong>{booking.buyerName}</strong><br /><span className="cell-muted">{booking.buyerPhone}</span></td>
                    <td>{booking.packageName} x {booking.quantity}</td>
                    <td className="cell-muted">{formatDateTime(booking.createdAt)}</td>
                    <td>{booking.paymentStatus || booking.status}</td>
                    <td>{formatMoney(booking.totalAmount)}</td>
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
