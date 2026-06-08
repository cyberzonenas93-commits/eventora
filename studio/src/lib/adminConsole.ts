import { httpsCallable } from 'firebase/functions'

import { functions } from '../firebaseFunctions'

export const adminCollections = [
  {
    id: 'users',
    label: 'Users',
    group: 'Identity',
    path: 'users',
    summaryFields: ['displayName', 'email', 'roles', 'adminRole', 'status'],
    feature: 'Customer accounts, organizer profiles, staff access, and notification choices.',
  },
  {
    id: 'admins',
    label: 'Admin staff',
    group: 'Identity',
    path: 'admins',
    summaryFields: ['displayName', 'email', 'role', 'status'],
    feature: 'People who can sign in to this console and what they are allowed to manage.',
  },
  {
    id: 'organizations',
    label: 'Organizers',
    group: 'Organizer Ops',
    path: 'organizations',
    summaryFields: ['name', 'ownerId', 'status', 'city'],
    feature: 'Organizer businesses, brand details, plan status, and contact information.',
  },
  {
    id: 'organization_members',
    label: 'Organization members',
    group: 'Organizer Ops',
    path: 'organization_members',
    summaryFields: ['organizationId', 'userId', 'role', 'status'],
    feature: 'Team members who help an organizer run events, tickets, and promotions.',
  },
  {
    id: 'organizer_applications',
    label: 'Organizer applications',
    group: 'Organizer Ops',
    path: 'organizer_applications',
    summaryFields: ['organizerName', 'email', 'status', 'organizationId'],
    feature: 'New organizer requests waiting for review and approval.',
  },
  {
    id: 'events',
    label: 'Events',
    group: 'Events',
    path: 'events',
    summaryFields: ['title', 'organizationId', 'status', 'visibility', 'city'],
    feature: 'Event pages, tickets, visibility, location, and public discovery.',
  },
  {
    id: 'event_occurrences',
    label: 'Event dates',
    group: 'Events',
    path: 'event_occurrences',
    summaryFields: ['title', 'eventId', 'status', 'occurrenceStartAt'],
    feature: 'Scheduled dates and times used for listings and reminders.',
  },
  {
    id: 'share_links',
    label: 'Public links',
    group: 'Events',
    path: 'share_links',
    summaryFields: ['title', 'targetId', 'slug', 'status'],
    feature: 'Public event links and share names used by organizers.',
  },
  {
    id: 'places',
    label: 'Places',
    group: 'Places',
    path: 'places',
    summaryFields: ['name', 'organizationId', 'city', 'verificationStatus', 'status'],
    feature: 'Self-serve and verified venue profiles, location details, menus, and discovery settings.',
  },
  {
    id: 'place_menu_sections',
    label: 'Place menu sections',
    group: 'Places',
    path: 'place_menu_sections',
    summaryFields: ['placeId', 'name', 'visible', 'sortOrder'],
    feature: 'Public menu sections created by location owners.',
  },
  {
    id: 'place_menu_items',
    label: 'Place menu items',
    group: 'Places',
    path: 'place_menu_items',
    summaryFields: ['placeId', 'sectionId', 'name', 'price', 'status'],
    feature: 'Food, drink, bottle-service, and package items shown on place profiles.',
  },
  {
    id: 'place_reservations',
    label: 'Place reservations',
    group: 'Places',
    path: 'place_reservations',
    summaryFields: ['placeName', 'guestName', 'partySize', 'status', 'requestedAt'],
    feature: 'User table, guestlist, and bottle-service reservation requests.',
  },
  {
    id: 'place_subscriptions',
    label: 'Place subscriptions',
    group: 'Places',
    path: 'place_subscriptions',
    summaryFields: ['placeId', 'userId', 'status', 'channels'],
    feature: 'Users following venues for updates and push notifications.',
  },
  {
    id: 'place_verifications',
    label: 'Place verification requests',
    group: 'Places',
    path: 'place_verifications',
    summaryFields: ['placeName', 'method', 'status', 'contactEmail'],
    feature: 'Self-serve location ownership verification requests for admin review.',
  },
  {
    id: 'event_rsvps',
    label: 'RSVPs',
    group: 'Tickets',
    path: 'event_rsvps',
    summaryFields: ['eventTitle', 'name', 'phone', 'status'],
    feature: 'People who registered interest before buying or attending.',
  },
  {
    id: 'event_ticket_orders',
    label: 'Ticket orders',
    group: 'Tickets',
    path: 'event_ticket_orders',
    summaryFields: ['eventId', 'buyerEmail', 'paymentStatus', 'totalAmount'],
    feature: 'Ticket purchases, buyer details, amounts, and payment status.',
  },
  {
    id: 'event_ticket_lookups',
    label: 'Door check-in',
    group: 'Tickets',
    path: 'event_ticket_lookups',
    summaryFields: ['eventId', 'orderId', 'status', 'tierName'],
    feature: 'Ticket check-in records used by staff at the event entrance.',
  },
  {
    id: 'ticket_admin_actions',
    label: 'Ticket staff actions',
    group: 'Tickets',
    path: 'ticket_admin_actions',
    summaryFields: ['type', 'eventId', 'orderId', 'performedBy'],
    feature: 'Door staff validation, admits, and cash-at-gate collection actions.',
  },
  {
    id: 'ticket_recovery_jobs',
    label: 'Ticket recovery',
    group: 'Tickets',
    path: 'ticket_recovery_jobs',
    summaryFields: ['orderId', 'eventId', 'issued', 'status'],
    feature: 'Manual recovery jobs for paid orders that need tickets reissued.',
  },
  {
    id: 'tablePackages',
    label: 'Table packages',
    group: 'Tickets',
    path: 'tablePackages',
    summaryFields: ['eventTitle', 'name', 'priceGhs', 'status'],
    feature: 'Public table packages attached to events.',
  },
  {
    id: 'table_bookings',
    label: 'Table bookings',
    group: 'Tickets',
    path: 'table_bookings',
    summaryFields: ['eventId', 'guestName', 'packageName', 'status'],
    feature: 'Operational table reservations for staff and organizers.',
  },
  {
    id: 'table_package_bookings',
    label: 'Table package payments',
    group: 'Tickets',
    path: 'table_package_bookings',
    summaryFields: ['eventTitle', 'packageName', 'paymentStatus', 'totalAmount'],
    feature: 'Public table package checkout and payment status.',
  },
  {
    id: 'event_ops_configs',
    label: 'Event Ops configs',
    group: 'Operations',
    path: 'event_ops_configs',
    summaryFields: ['eventTitle', 'selectedPlan', 'paymentMode', 'setupComplete'],
    feature: 'Event inventory and staff POS setup records.',
  },
  {
    id: 'event_inventory_items',
    label: 'Event inventory',
    group: 'Operations',
    path: 'event_inventory_items',
    summaryFields: ['eventId', 'name', 'category', 'sellingGhs'],
    feature: 'Inventory items listed for sale during an event.',
  },
  {
    id: 'event_ops_staff',
    label: 'Event Ops staff',
    group: 'Operations',
    path: 'event_ops_staff',
    summaryFields: ['eventId', 'name', 'role', 'station'],
    feature: 'Waiter, bartender, vendor, and floor-lead credentials.',
  },
  {
    id: 'event_ops_tabs',
    label: 'Event Ops tabs',
    group: 'Operations',
    path: 'event_ops_tabs',
    summaryFields: ['eventTitle', 'customer', 'status', 'totalAmount'],
    feature: 'Open and closed merchant-collected event sales tabs.',
  },
  {
    id: 'event_ops_reports',
    label: 'Event Ops reports',
    group: 'Operations',
    path: 'event_ops_reports',
    summaryFields: ['eventTitle', 'status', 'tabCount', 'createdAt'],
    feature: 'Generated end-of-event report records.',
  },
  {
    id: 'event_ops_onboarding_visuals',
    label: 'Event Ops onboarding visuals',
    group: 'Operations',
    path: 'event_ops_onboarding_visuals',
    summaryFields: ['eventTitle', 'status', 'model', 'updatedAt'],
    feature: 'Gemini-generated onboarding graphics for Event Ops setup.',
  },
  {
    id: 'event_reminders',
    label: 'Event reminders',
    group: 'Tickets',
    path: 'event_reminders',
    summaryFields: ['eventId', 'userId', 'status', 'scheduledAt'],
    feature: 'Reminder messages for people attending or saving events.',
  },
  {
    id: 'event_reports',
    label: 'Safety reports',
    group: 'Safety',
    path: 'event_reports',
    summaryFields: ['eventTitle', 'reason', 'createdAt', 'status'],
    feature: 'Reports from users about unsafe, incorrect, or problematic events.',
  },
  {
    id: 'support_tickets',
    label: 'Support tickets',
    group: 'Safety',
    path: 'support_tickets',
    summaryFields: ['subject', 'name', 'email', 'status', 'adminUnreadCount'],
    feature: 'In-app support conversations, user contact details, and ticket status.',
  },
  {
    id: 'event_posts',
    label: 'Social posts',
    group: 'Social',
    path: 'event_posts',
    summaryFields: ['eventId', 'userId', 'caption', 'likeCount'],
    feature: 'Photos, captions, and reactions shared around events.',
  },
  {
    id: 'gplus_events',
    label: 'G+ event mirror',
    group: 'Social',
    path: 'gplus_events',
    summaryFields: ['title', 'date', 'status', 'sourceEventId'],
    feature: 'Incoming G+ event documents that sync into Vennuzo as featured events.',
  },
  {
    id: 'gplus_profiles',
    label: 'G+ profile mirror',
    group: 'Social',
    path: 'gplus_profiles',
    summaryFields: ['displayName', 'username', 'updatedAt', 'sourceProfileId'],
    feature: 'Incoming G+ profile documents used to maintain the G+ creator profile on Vennuzo.',
  },
  {
    id: 'gplus_media_gallery',
    label: 'G+ media gallery',
    group: 'Social',
    path: 'gplus_media_gallery',
    summaryFields: ['eventId', 'imageUrl', 'caption', 'updatedAt'],
    feature: 'Incoming G+ media documents that sync into Vennuzo event, creator, and place photos.',
  },
  {
    id: 'gplus_sync_status',
    label: 'G+ sync status',
    group: 'Social',
    path: 'gplus_sync_status',
    summaryFields: ['type', 'status', 'vennuzoEventId', 'syncedAt'],
    feature: 'Server-written status records for automatic G+ to Vennuzo sync.',
  },
  {
    id: 'gelo_content_queue',
    label: 'Gelo content queue',
    group: 'Social',
    path: 'gelo_content_queue',
    summaryFields: ['type', 'title', 'status', 'eventId'],
    feature: 'Vennuzo event posts and G+ imports prepared for the Gelo OS content engine.',
  },
  {
    id: 'gelo_event_launch_drafts',
    label: 'Gelo event drafts',
    group: 'Social',
    path: 'gelo_event_launch_drafts',
    summaryFields: ['eventTitle', 'status', 'source', 'updatedAt'],
    feature: 'Gelo OS launch drafts generated from synced events.',
  },
  {
    id: 'gelo_website_features',
    label: 'Gelo website features',
    group: 'Social',
    path: 'gelo_website_features',
    summaryFields: ['title', 'featureType', 'status', 'urlPath'],
    feature: 'Website and SEO feature records for the Gelo OS engine.',
  },
  {
    id: 'event_reviews',
    label: 'Event reviews',
    group: 'Social',
    path: 'collectionGroup:reviews',
    summaryFields: ['eventId', 'userId', 'rating', 'comment'],
    feature: 'Ratings and comments people leave after events.',
  },
  {
    id: 'post_comments',
    label: 'Post comments',
    group: 'Social',
    path: 'collectionGroup:comments',
    summaryFields: ['postId', 'userId', 'text', 'createdAt'],
    feature: 'Comments people leave on event social posts.',
  },
  {
    id: 'post_likes',
    label: 'Post likes',
    group: 'Social',
    path: 'collectionGroup:likes',
    summaryFields: ['postId', 'userId', 'createdAt'],
    feature: 'Likes and reactions on event social posts.',
  },
  {
    id: 'social_follows',
    label: 'Social follows',
    group: 'Social',
    path: 'collectionGroup:following',
    summaryFields: ['followerId', 'followingId', 'createdAt'],
    feature: 'People following other profiles in the app.',
  },
  {
    id: 'event_saves',
    label: 'Saved events',
    group: 'Social',
    path: 'collectionGroup:saved',
    summaryFields: ['eventId', 'userId', 'createdAt'],
    feature: 'Events people saved to come back to later.',
  },
  {
    id: 'promotion_campaigns',
    label: 'Promotions',
    group: 'Marketing',
    path: 'promotion_campaigns',
    summaryFields: ['eventTitle', 'organizationId', 'status', 'channels'],
    feature: 'Marketing campaigns sent by organizers to promote events.',
  },
  {
    id: 'audience_contacts',
    label: 'Marketing contacts',
    group: 'Marketing',
    path: 'audience_contacts',
    summaryFields: ['organizationId', 'email', 'phone', 'source'],
    feature: 'People organizers can contact for approved marketing campaigns.',
  },
  {
    id: 'advertiser_wallets',
    label: 'Promotion balances',
    group: 'Marketing',
    path: 'advertiser_wallets',
    summaryFields: ['availableBalance', 'heldBalance', 'currency'],
    feature: 'Money available for organizer promotion spending.',
  },
  {
    id: 'wallet_transactions',
    label: 'Wallet transactions',
    group: 'Marketing',
    path: 'wallet_transactions',
    summaryFields: ['walletId', 'type', 'amount', 'status'],
    feature: 'Top-ups, promotion charges, and creative service charges.',
  },
  {
    id: 'notification_jobs',
    label: 'Messages',
    group: 'Marketing',
    path: 'notification_jobs',
    summaryFields: ['eventId', 'channel', 'status', 'campaignId'],
    feature: 'Scheduled campaign and reminder messages.',
  },
  {
    id: 'push_queue',
    label: 'App messages',
    group: 'Marketing',
    path: 'push_queue',
    summaryFields: ['title', 'targetUid', 'status', 'kind'],
    feature: 'In-app and phone notifications waiting to be sent.',
  },
  {
    id: 'sms_opt_out',
    label: 'SMS opt-outs',
    group: 'Marketing',
    path: 'sms_opt_out',
    summaryFields: ['phone', 'source', 'createdAt'],
    feature: 'People who asked not to receive SMS marketing.',
  },
  {
    id: 'promo_packages',
    label: 'Promo packages',
    group: 'Marketing',
    path: 'promo_packages',
    summaryFields: ['name', 'active', 'order', 'defaultSmsRateGhs'],
    feature: 'Promotion plans and prices shown to organizers.',
  },
  {
    id: 'partner_profiles',
    label: 'Partner profiles',
    group: 'Marketing',
    path: 'partner_profiles',
    summaryFields: ['name', 'organizationId', 'type', 'status'],
    feature: 'Promoters, affiliates, venue partners, and referral collaborators.',
  },
  {
    id: 'partner_event_links',
    label: 'Partner links',
    group: 'Marketing',
    path: 'partner_event_links',
    summaryFields: ['eventTitle', 'partnerName', 'refCode', 'status'],
    feature: 'Trackable event referral links for partners.',
  },
  {
    id: 'partner_clicks',
    label: 'Partner clicks',
    group: 'Marketing',
    path: 'partner_clicks',
    summaryFields: ['eventId', 'partnerLinkId', 'refCode', 'createdAt'],
    feature: 'Click events from partner referral links.',
  },
  {
    id: 'partner_payouts',
    label: 'Partner payouts',
    group: 'Marketing',
    path: 'partner_payouts',
    summaryFields: ['partnerProfileId', 'amount', 'status', 'createdAt'],
    feature: 'Commission settlement records for partner referrals.',
  },
  {
    id: 'promo_mechanics',
    label: 'Promo mechanics',
    group: 'Marketing',
    path: 'promo_mechanics',
    summaryFields: ['eventTitle', 'type', 'title', 'status'],
    feature: 'Raffles, leaderboards, referral campaigns, flash offers, and promo codes.',
  },
  {
    id: 'promo_entries',
    label: 'Promo entries',
    group: 'Marketing',
    path: 'promo_entries',
    summaryFields: ['promoMechanicId', 'name', 'points', 'status'],
    feature: 'Audience entries and points for active promo mechanics.',
  },
  {
    id: 'promo_redemptions',
    label: 'Promo redemptions',
    group: 'Marketing',
    path: 'promo_redemptions',
    summaryFields: ['eventId', 'code', 'name', 'status'],
    feature: 'Promo code redemptions and offer usage.',
  },
  {
    id: 'promo_leaderboards',
    label: 'Promo leaderboards',
    group: 'Marketing',
    path: 'promo_leaderboards',
    summaryFields: ['eventId', 'promoMechanicId', 'status', 'updatedAt'],
    feature: 'Stored leaderboard snapshots for competitions.',
  },
  {
    id: 'promo_winners',
    label: 'Promo winners',
    group: 'Marketing',
    path: 'promo_winners',
    summaryFields: ['eventId', 'promoMechanicId', 'name', 'status'],
    feature: 'Selected winners from raffles, challenges, and leaderboards.',
  },
  {
    id: 'pending_event_changes',
    label: 'Pending event changes',
    group: 'Events',
    path: 'pending_event_changes',
    summaryFields: ['eventTitle', 'organizationId', 'status', 'submittedBy'],
    feature: 'Organizer edits waiting for approval before publication.',
  },
  {
    id: 'event_ai_extractions',
    label: 'Flyer event extraction',
    group: 'Events',
    path: 'event_ai_extractions',
    summaryFields: ['organizationId', 'status', 'provider', 'createdAt'],
    feature: 'Flyer and table-package parsing records for assisted event creation.',
  },
  {
    id: 'creative_brand_configs',
    label: 'Brand guides',
    group: 'Creative',
    path: 'creative_brand_configs',
    summaryFields: ['organizationId', 'brandName', 'tone', 'updatedAt'],
    feature: 'Organizer brand details used for creative services.',
  },
  {
    id: 'flyer_jobs',
    label: 'Creative jobs',
    group: 'Creative',
    path: 'flyer_jobs',
    summaryFields: ['organizationId', 'serviceType', 'status', 'eventName'],
    feature: 'Flyer and table package requests from organizers.',
  },
  {
    id: 'flyer_sessions',
    label: 'Creative deliveries',
    group: 'Creative',
    path: 'flyer_sessions',
    summaryFields: ['organizationId', 'serviceType', 'eventName', 'priceChargedGhs'],
    feature: 'Delivered creative work, edits, and final pricing.',
  },
  {
    id: 'payout_requests',
    label: 'Payout requests',
    group: 'Billing',
    path: 'payout_requests',
    summaryFields: ['organizationId', 'amount', 'status', 'createdAt'],
    feature: 'Organizer requests to receive money from completed sales.',
  },
  {
    id: 'app_config',
    label: 'App settings',
    group: 'System',
    path: 'app_config',
    summaryFields: ['updatedAt', 'updatedBy'],
    feature: 'Important platform settings. Change only when approved.',
  },
  {
    id: 'rate_limits',
    label: 'Usage limits',
    group: 'System',
    path: 'rate_limits',
    summaryFields: ['uid', 'operation', 'count', 'expiresAt'],
    feature: 'Temporary blocks that prevent repeated suspicious actions.',
  },
  {
    id: 'admin_notifications',
    label: 'Admin alerts',
    group: 'System',
    path: 'admin_notifications',
    summaryFields: ['title', 'kind', 'status', 'createdAt'],
    feature: 'Operational alerts created by backend workflows for admin staff.',
  },
] as const

export type AdminCollectionId = (typeof adminCollections)[number]['id']

export type AdminJsonValue =
  | null
  | string
  | number
  | boolean
  | AdminJsonValue[]
  | { [key: string]: AdminJsonValue }

export interface AdminDocument {
  id: string
  docPath: string
  data: Record<string, AdminJsonValue>
}

export interface AdminCollectionMeta {
  id: AdminCollectionId
  label: string
  group: string
  path: string
  summaryFields: readonly string[]
  writable: boolean
}

export interface AdminOverview {
  generatedAt: string
	  admin: {
	    uid: string
	    email: string
	    role: string
	    roleLabel?: string
	    displayName: string
	    isSuperAdmin: boolean
	  }
	  counts: Record<string, number>
	  recent: Partial<Record<AdminCollectionId, AdminDocument[]>>
	  roleOptions?: Array<{ id: string; label: string; description: string }>
	  collections: AdminCollectionMeta[]
	}

export interface AdminDocumentList {
  collection: AdminCollectionMeta
  docs: AdminDocument[]
}

const bootstrapOwnerAdminCallable = httpsCallable<
  { email: string; password: string; displayName?: string },
  { success: boolean; uid: string; created: boolean }
>(functions, 'bootstrapOwnerAdmin')

const getAdminConsoleOverviewCallable = httpsCallable<void, AdminOverview>(
  functions,
  'getAdminConsoleOverview',
)

const listAdminConsoleDocumentsCallable = httpsCallable<
  { collectionId: AdminCollectionId; limit?: number },
  AdminDocumentList
>(functions, 'listAdminConsoleDocuments')

const saveAdminConsoleDocumentCallable = httpsCallable<
  {
    collectionId: AdminCollectionId
    docPath?: string
    docId?: string
    data: Record<string, AdminJsonValue>
    merge?: boolean
  },
  { success: boolean; doc: AdminDocument }
>(functions, 'saveAdminConsoleDocument')

const deleteAdminConsoleDocumentCallable = httpsCallable<
  { collectionId: AdminCollectionId; docPath: string },
  { success: boolean; docPath: string }
>(functions, 'deleteAdminConsoleDocument')

const updateAdminAuthUserCallable = httpsCallable<
  {
    uid?: string
    email?: string
    displayName?: string
    password?: string
    disabled?: boolean
  },
  { success: boolean; uid: string; email: string; disabled: boolean }
>(functions, 'updateAdminAuthUser')

export const adminCollectionById = Object.fromEntries(
  adminCollections.map((collection) => [collection.id, collection]),
) as Record<AdminCollectionId, (typeof adminCollections)[number]>

export const adminCollectionGroups = Array.from(
  new Set(adminCollections.map((collection) => collection.group)),
)

const adminGroupLabels: Record<string, string> = {
  Identity: 'People & access',
  'Organizer Ops': 'Organizers',
  Events: 'Events',
  Tickets: 'Tickets & attendees',
  Safety: 'Safety',
  Social: 'Community',
  Marketing: 'Marketing',
  Creative: 'Creative requests',
  Billing: 'Payments',
  System: 'Settings',
}

const adminFieldLabels: Record<string, string> = {
  active: 'Active',
  adminRole: 'Admin level',
  amount: 'Amount',
  availableBalance: 'Available balance',
  brandName: 'Brand name',
  buyerEmail: 'Buyer email',
  campaignId: 'Campaign',
  caption: 'Caption',
  channel: 'Channel',
  channels: 'Channels',
  city: 'City',
  comment: 'Comment',
  count: 'Attempts',
  createdAt: 'Created',
  currency: 'Currency',
  defaultSmsRateGhs: 'SMS price',
  disabled: 'Blocked from signing in',
  displayName: 'Name',
  email: 'Email',
  eventId: 'Event',
  eventName: 'Event name',
  eventTitle: 'Event',
  expiresAt: 'Ends',
  followerId: 'Follower',
  followingId: 'Following',
  heldBalance: 'Reserved balance',
  kind: 'Message type',
  packageName: 'Package',
  partnerLinkId: 'Partner link',
  partnerName: 'Partner',
  partnerProfileId: 'Partner',
  performedBy: 'Staff',
  latestMessage: 'Latest message',
  likeCount: 'Likes',
  name: 'Name',
  occurrenceStartAt: 'Starts',
  operation: 'Action',
  order: 'Display order',
  orderId: 'Order',
  organizationId: 'Organizer',
  ownerId: 'Owner',
  paymentStatus: 'Payment status',
  phone: 'Phone',
  planId: 'Plan',
  postId: 'Post',
  priceChargedGhs: 'Price charged',
  rating: 'Rating',
  refCode: 'Referral code',
  reason: 'Reason',
  role: 'Access level',
  roles: 'Access',
  scheduledAt: 'Scheduled for',
  serviceType: 'Service',
  slug: 'Public link name',
  source: 'Source',
  status: 'Status',
  targetId: 'Linked item',
  targetUid: 'Recipient',
  text: 'Message',
  tierName: 'Ticket type',
  title: 'Title',
  tone: 'Tone',
  totalAmount: 'Total amount',
  type: 'Type',
  uid: 'Person',
  updatedAt: 'Updated',
  updatedBy: 'Updated by',
  userId: 'Person',
  visibility: 'Visibility',
  walletId: 'Balance account',
}

const preferredTitleFields = [
  'displayName',
  'name',
  'title',
  'organizerName',
  'eventTitle',
  'eventName',
  'brandName',
  'buyerEmail',
  'email',
  'phone',
  'orderId',
  'slug',
]

const linkedFieldSummaries: Record<string, string> = {
  campaignId: 'Campaign linked',
  eventId: 'Event linked',
  followerId: 'Follower linked',
  followingId: 'Profile linked',
  orderId: 'Order linked',
  organizationId: 'Organizer linked',
  ownerId: 'Owner linked',
  planId: 'Plan linked',
  postId: 'Post linked',
  targetId: 'Item linked',
  targetUid: 'Recipient linked',
  uid: 'Person linked',
  userId: 'Person linked',
  walletId: 'Balance linked',
}

export function isAdminCollectionId(value: string | undefined): value is AdminCollectionId {
  return Boolean(value && value in adminCollectionById)
}

export function getAdminGroupLabel(group: string) {
  return adminGroupLabels[group] ?? group
}

export function humanizeAdminField(field: string) {
  if (adminFieldLabels[field]) return adminFieldLabels[field]
  return field
    .replace(/([a-z0-9])([A-Z])/g, '$1 $2')
    .replace(/[_-]+/g, ' ')
    .replace(/\b\w/g, (letter) => letter.toUpperCase())
}

export function bootstrapOwnerAdmin(input: {
  email: string
  password: string
  displayName?: string
}) {
  return bootstrapOwnerAdminCallable(input).then((result) => result.data)
}

export function getAdminConsoleOverview() {
  return getAdminConsoleOverviewCallable().then((result) => result.data)
}

export function listAdminConsoleDocuments(collectionId: AdminCollectionId, limit = 100) {
  return listAdminConsoleDocumentsCallable({ collectionId, limit }).then((result) => result.data)
}

export function saveAdminConsoleDocument(input: {
  collectionId: AdminCollectionId
  docPath?: string
  docId?: string
  data: Record<string, AdminJsonValue>
  merge?: boolean
}) {
  return saveAdminConsoleDocumentCallable(input).then((result) => result.data)
}

export function deleteAdminConsoleDocument(input: {
  collectionId: AdminCollectionId
  docPath: string
}) {
  return deleteAdminConsoleDocumentCallable(input).then((result) => result.data)
}

export function updateAdminAuthUser(input: {
  uid?: string
  email?: string
  displayName?: string
  password?: string
  disabled?: boolean
}) {
  return updateAdminAuthUserCallable(input).then((result) => result.data)
}

export function summarizeAdminValue(value: AdminJsonValue): string {
  if (value == null) return '—'
  if (typeof value === 'string') return value || '—'
  if (typeof value === 'number' || typeof value === 'boolean') return String(value)
  if (Array.isArray(value)) return value.map((entry) => summarizeAdminValue(entry)).join(', ') || '—'
  const type = typeof value.__type === 'string' ? value.__type : ''
  if (type === 'timestamp' && typeof value.iso === 'string') return value.iso
  if (type === 'serverTimestamp') return 'Set when saved'
  if (type === 'reference' && typeof value.path === 'string') {
    return value.path.split('/').filter(Boolean).pop() ?? 'Linked record'
  }
  if (type === 'geoPoint') return `${String(value.latitude)}, ${String(value.longitude)}`
  return 'Saved details'
}

export function summarizeAdminFieldValue(field: string, value: AdminJsonValue): string {
  const summary = summarizeAdminValue(value)
  if (!summary || summary === '—') return summary
  if (isLinkedAdminField(field)) return linkedFieldSummaries[field] ?? 'Linked item'
  return summary
}

export function isLinkedAdminField(field: string) {
  return Boolean(linkedFieldSummaries[field] || /^[a-zA-Z]+Id$/.test(field) || /^[a-zA-Z]+Uid$/.test(field))
}

export function compactAdminSummary(data: Record<string, AdminJsonValue>, fields: readonly string[]) {
  return fields
    .map((field) => summarizeAdminFieldValue(field, data[field]))
    .filter((value) => value && value !== '—')
    .slice(0, 3)
    .join(' · ')
}

export function getAdminRecordTitle(doc: AdminDocument, fields: readonly string[] = []) {
  const candidates = [...preferredTitleFields, ...fields]
  for (const field of candidates) {
    const value = fields.includes(field)
      ? summarizeAdminFieldValue(field, doc.data[field])
      : summarizeAdminValue(doc.data[field])
    if (
      value &&
      value !== '—' &&
      value !== 'Saved details' &&
      !value.toLowerCase().endsWith(' linked')
    ) {
      return value
    }
  }
  return `Record ${doc.id.slice(0, 8)}`
}

export function getAdminRecordSubtitle(doc: AdminDocument, fields: readonly string[]) {
  const title = getAdminRecordTitle(doc, fields)
  const summary = compactAdminSummary(doc.data, fields)
  if (!summary) return `Reference ${doc.id.slice(0, 8)}`
  return summary.replace(title, '').replace(/^ · | · $/g, '') || `Reference ${doc.id.slice(0, 8)}`
}
