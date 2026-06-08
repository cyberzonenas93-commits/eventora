import { formatMoney } from './formatters'
import type { PortalEvent } from './types'

/**
 * Shared presentation helpers for event cards, used by the public Home and
 * Events listings. (PublicEventDetailPage intentionally has its own price label.)
 */

export function getDateParts(isoDate: string): { day: string; month: string } {
  if (!isoDate) return { day: '--', month: '--' }
  const d = new Date(isoDate)
  if (Number.isNaN(d.getTime())) return { day: '--', month: '--' }
  return {
    day: String(d.getDate()),
    month: d.toLocaleDateString('en', { month: 'short' }),
  }
}

export function getPriceLabel(event: PortalEvent): string {
  if (!event.ticketingEnabled || event.tiers.length === 0) return 'RSVP'
  const min = Math.min(...event.tiers.map((t) => t.price))
  return min === 0 ? 'Free' : `From ${formatMoney(min)}`
}

export function getDemandLabel(event: PortalEvent): string {
  const signals = event.ticketCount + event.rsvpCount + event.likesCount
  if (signals >= 150) return 'Selling fast'
  if (event.ticketCount > 0) return `${event.ticketCount} going`
  if (event.rsvpCount > 0) return `${event.rsvpCount} RSVPs`
  return 'Just announced'
}

export function getTicketAvailability(event: PortalEvent): string {
  const capacity = event.tiers.reduce((sum, tier) => sum + Math.max(tier.maxQuantity, 0), 0)
  const sold = event.tiers.reduce((sum, tier) => sum + Math.max(tier.sold, 0), 0)
  if (!event.ticketingEnabled || capacity === 0) return 'RSVP open'
  const remaining = Math.max(capacity - sold, 0)
  if (remaining === 0) return 'Sold out'
  if (remaining <= 50) return `${remaining} left`
  return 'Tickets available'
}
