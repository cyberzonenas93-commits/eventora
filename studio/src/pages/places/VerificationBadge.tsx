import { Clock, ShieldCheck, XCircle, type LucideIcon } from 'lucide-react'

import type { PortalPlace } from '../../lib/types'

function verificationBadge(place: PortalPlace): { label: string; tone: string; icon: LucideIcon } {
  if (place.verified || place.verificationStatus === 'verified') {
    return { label: 'Verified', tone: 'active', icon: ShieldCheck }
  }
  if (place.verificationStatus === 'verification_pending') {
    return { label: 'Pending review', tone: 'pending', icon: Clock }
  }
  if (place.verificationStatus === 'rejected' || place.verificationStatus === 'suspended') {
    return { label: 'Unverified', tone: 'rejected', icon: XCircle }
  }
  return { label: 'Unverified', tone: 'draft', icon: XCircle }
}

export function VerificationBadge({ place }: { place: PortalPlace }) {
  const { label, tone, icon: Icon } = verificationBadge(place)
  return (
    <span className={`status-pill status-pill--${tone}`}>
      <Icon size={13} aria-hidden />
      {label}
    </span>
  )
}
