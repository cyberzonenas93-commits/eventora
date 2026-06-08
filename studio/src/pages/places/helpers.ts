import type { PortalPlace } from '../../lib/types'

export function slugify(input: string) {
  return input
    .trim()
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '_')
    .replace(/^_+|_+$/g, '')
    .slice(0, 80) || `place_${Date.now()}`
}

/** Mask all but the last 2 digits of a phone number for display. */
export function maskPhone(phone: string) {
  const trimmed = phone.trim()
  if (trimmed.length <= 2) return trimmed
  const tail = trimmed.slice(-2)
  return `${'•'.repeat(Math.min(trimmed.length - 2, 8))}${tail}`
}

export function verificationLabel(place: PortalPlace) {
  if (place.verified || place.verificationStatus === 'verified') return 'Verified location owner'
  if (place.verificationStatus === 'verification_pending') return 'Verification pending'
  if (place.verificationStatus === 'rejected') return 'Verification rejected'
  if (place.verificationStatus === 'suspended') return 'Verification suspended'
  return 'Unverified location'
}
