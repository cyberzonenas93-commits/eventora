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

export interface PortalOrder {
  id: string
  organizationId: string
  eventId: string
  eventTitle: string
  totalAmount: number
  paymentStatus: string
  createdAt: string
  buyerEmail: string
  ticketCount: number
}

export interface PortalContact {
  email: string
  displayName: string
  phone: string
  lastEventId: string
  lastEventTitle: string
  lastActivityAt: string
  orderCount: number
  rsvpCount: number
  totalSpent: number
}

export interface PortalCampaign {
  id: string
  organizationId: string
  eventId: string
  eventTitle: string
  name: string
  status: string
  channels: string[]
  pushAudience: number
  smsAudience: number
  walletReservationAmount: number
  totalSmsCharged?: number
  createdAt: string
  scheduledAt?: string
}

export interface WalletTransaction {
  id: string
  walletId: string
  type: 'top_up' | 'campaign_reservation' | 'campaign_charge' | 'campaign_release'
  amount: number
  status: string
  createdAt: string
  campaignId?: string
}
