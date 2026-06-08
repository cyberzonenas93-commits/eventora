import { Clock, XCircle } from 'lucide-react'

import { formatDateTime } from '../../lib/formatters'
import type { PortalPlace, PortalPlaceReservation } from '../../lib/types'

type ReservationsTabProps = {
  selectedPlace: PortalPlace | null
  reservationStatusFilter: string
  setReservationStatusFilter: (value: string) => void
  visibleReservations: PortalPlaceReservation[]
  changeReservationStatus: (reservationId: string, status: string) => void
}

export function ReservationsTab({
  selectedPlace,
  reservationStatusFilter,
  setReservationStatusFilter,
  visibleReservations,
  changeReservationStatus,
}: ReservationsTabProps) {
  return (
    <article className="panel">
      <div className="panel__header">
        <div>
          <p className="eyebrow">Reservations</p>
          <h3>Manage requests</h3>
        </div>
        <Clock size={22} aria-hidden />
      </div>
      <div className="places-filter-row">
        <label>
          <span>Status</span>
          <select value={reservationStatusFilter} onChange={(e) => setReservationStatusFilter(e.target.value)}>
            <option value="all">All reservations</option>
            <option value="pending">Pending</option>
            <option value="confirmed">Confirmed</option>
            <option value="cancelled">Cancelled</option>
            <option value="change_requested">Change requested</option>
          </select>
        </label>
      </div>
      <div className="order-list">
        {visibleReservations.length === 0 ? (
          <div className="empty-card">
            <h4>No reservations yet</h4>
            <p>Guestlist, VIP table, and bottle-service requests will appear here.</p>
          </div>
        ) : (
          visibleReservations.map((reservation) => (
            <div className="order-row" key={reservation.id}>
              <div>
                <strong>{reservation.guestName}</strong>
                <span>
                  {reservation.partySize} guests · {reservation.placeName || selectedPlace?.name} · {formatDateTime(reservation.requestedAt)}
                </span>
                {reservation.note ? <small>{reservation.note}</small> : null}
              </div>
              <div className="order-row__meta">
                <span className={`status-pill status-pill--${reservation.status}`}>{reservation.status}</span>
                <button className="button button--secondary" onClick={() => changeReservationStatus(reservation.id, 'confirmed')} type="button">
                  Confirm
                </button>
                <button className="button button--ghost" onClick={() => changeReservationStatus(reservation.id, 'cancelled')} type="button">
                  <XCircle size={15} aria-hidden />
                  Cancel
                </button>
              </div>
            </div>
          ))
        )}
      </div>
    </article>
  )
}
