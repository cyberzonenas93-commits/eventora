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
  coverImageUrl: string
  performers: string
  djs: string
  mcs: string
  categoryId: string
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
  buyerName?: string
  buyerPhone?: string
  marketingConsent?: boolean
  smsConsent?: boolean
  ticketCount: number
}

export interface PortalContact {
  email: string
  displayName: string
  phone: string
  userId?: string
  lastEventId: string
  lastEventTitle: string
  lastActivityAt: string
  orderCount: number
  rsvpCount: number
  totalSpent: number
  marketingConsent: boolean
  smsConsent: boolean
  tags: string[]
  notes: string
  sources: Array<'orders' | 'rsvps' | 'uploaded'>
  sourceNames: string[]
  events: PortalContactActivity[]
}

export interface PortalContactActivity {
  id: string
  type: 'order' | 'rsvp' | 'upload'
  eventId: string
  eventTitle: string
  occurredAt: string
  amount?: number
  sourceName?: string
}

export interface PortalCampaign {
  id: string
  organizationId: string
  eventId: string
  eventTitle: string
  name: string
  status: string
  channels: string[]
  audienceSources: string[]
  pushAudience: number
  smsAudience: number
  uploadedAudience?: number
  walletReservationAmount: number
  totalSmsCharged?: number
  totalPushCharged?: number
  createdAt: string
  scheduledAt?: string
}

export interface PortalPlace {
  id: string
  organizationId: string
  ownerId: string
  name: string
  description: string
  city: string
  address: string
  status: string
  verificationStatus: string
  verified: boolean
  latestVerificationRequestId: string
  featured: boolean
  coverUrl: string
  logoUrl: string
  mapsUrl: string
  googlePlaceId: string
  phone: string
  website: string
  categories: string[]
  amenities: string[]
  openingHours: string[]
  subscriberCount: number
  rating: number
  reviewCount: number
}

export interface PortalPlaceMenuSection {
  id: string
  placeId: string
  name: string
  description: string
  sortOrder: number
  visible: boolean
}

export interface PortalPlaceMenuItem {
  id: string
  placeId: string
  sectionId: string
  name: string
  description: string
  price: number
  currency: string
  imageUrl: string
  featured: boolean
  status: string
  sortOrder: number
}

export interface PortalPlaceReservation {
  id: string
  placeId: string
  placeName: string
  organizationId: string
  userId: string
  guestName: string
  phone: string
  partySize: number
  requestedAt: string
  reservationType: string
  status: string
  note: string
  selectedMenuItemIds: string[]
  createdAt: string
}

export interface WalletTransaction {
  id: string
  walletId: string
  type: 'top_up' | 'campaign_reservation' | 'campaign_charge' | 'campaign_release' | 'creative_service_charge' | 'creative_service_refund'
  amount: number
  status: string
  createdAt: string
  campaignId?: string
}

export interface CreativeSession {
  id: string
  organizationId: string
  serviceType: 'event_flyer' | 'table_package_flyer'
  editMode?: string | null
  eventName: string
  imageUrl: string
  postUrl?: string | null
  prompt: string
  priceChargedGhs: number
  minorEditsRemaining?: number | null
  redesignsRemaining?: number | null
  createdAt: string
}
