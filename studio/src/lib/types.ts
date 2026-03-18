export type OrganizerApplicationStatus =
  | 'not_started'
  | 'draft'
  | 'active'
  | 'submitted'
  | 'under_review'
  | 'approved'
  | 'rejected'

export interface UserProfile {
  displayName: string
  email: string
  phone: string
  roles: string[]
  adminRole: string
  defaultOrganizationId: string
  organizerApplicationStatus: OrganizerApplicationStatus
}

export interface OrganizerApplication {
  userId: string
  organizerName: string
  contactPerson: string
  email: string
  phone: string
  businessType: string
  businessAddress: string
  audienceCity: string
  instagram: string
  brandTagline: string
  brandAccentColor: string
  logoFileName: string
  logoImageUrl: string
  governmentIdFileName: string
  governmentIdUrl: string
  selfieFileName: string
  selfieUrl: string
  isRegisteredBusiness: 'yes' | 'no'
  businessRegistrationNumber: string
  tinNumber: string
  payoutMethod: 'mobile-money' | 'bank-transfer'
  bankName: string
  accountName: string
  accountNumber: string
  network: string
  payoutPhone: string
  settlementPreference: string
  agreedToPayoutTerms: boolean
  agreesToCompliance: boolean
  status: OrganizerApplicationStatus
  reviewNotes: string
  organizationId: string
}

export interface PortalTicketTier {
  tierId: string
  name: string
  price: number
  maxQuantity: number
  sold: number
  description: string
}

export interface PortalEvent {
  id: string
  organizationId: string
  createdBy: string
  title: string
  description: string
  venue: string
  city: string
  visibility: 'public' | 'private'
  status: 'draft' | 'published' | 'cancelled'
  timezone: string
  startAt: string
  endAt: string
  performers: string
  djs: string
  mcs: string
  mood: string
  tags: string[]
  allowSharing: boolean
  sendPushNotification: boolean
  sendSmsNotification: boolean
  ticketingEnabled: boolean
  requireTicket: boolean
  currency: string
  tiers: PortalTicketTier[]
  likesCount: number
  rsvpCount: number
  ticketCount: number
  grossRevenue: number
}

export interface OverviewMetrics {
  grossRevenue: number
  paidOrders: number
  totalRsvps: number
  liveEvents: number
  draftEvents: number
  ticketsIssued: number
}
