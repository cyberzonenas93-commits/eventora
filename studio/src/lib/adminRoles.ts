import type { AdminCollectionId } from './adminConsole'

export type AdminRoleId =
  | 'superadmin'
  | 'admin'
  | 'operations_manager'
  | 'customer_support'
  | 'organizer_success'
  | 'organizer_approvals'
  | 'event_operations'
  | 'trust_safety'
  | 'finance'
  | 'payouts_manager'
  | 'marketing_manager'
  | 'creative_services'
  | 'content_curator'
  | 'read_only'

export type AdminAction =
  | 'manage_staff'
  | 'update_auth_users'
  | 'review_organizers'
  | 'read_pricing'
  | 'manage_pricing'
  | 'manage_promo_packages'
  | 'read_campaigns'
  | 'read_analytics'
  | 'manage_support'
  | 'record_sms_opt_out'

export const adminRoleDefinitions: Record<
  AdminRoleId,
  { label: string; description: string; aliasOf?: AdminRoleId }
> = {
  superadmin: {
    label: 'Owner / Super Admin',
    description: 'Full control over Vennuzo, staff access, settings, and emergency changes.',
  },
  admin: {
    label: 'Operations Manager',
    description: 'Legacy operations access. Matches the Operations Manager role.',
    aliasOf: 'operations_manager',
  },
  operations_manager: {
    label: 'Operations Manager',
    description: 'Runs daily platform operations across organizers, events, safety, and payments.',
  },
  customer_support: {
    label: 'Customer Support',
    description: 'Helps users and organizers with accounts, tickets, records, and support notes.',
  },
  organizer_success: {
    label: 'Organizer Success',
    description: 'Supports organizers, onboarding, profiles, memberships, and plan status.',
  },
  organizer_approvals: {
    label: 'Organizer Approvals',
    description: 'Reviews new organizer applications and approval notes.',
  },
  event_operations: {
    label: 'Event Operations',
    description: 'Manages event details, schedules, tickets, RSVPs, and check-in records.',
  },
  trust_safety: {
    label: 'Trust & Safety',
    description: 'Handles reports, moderation, account blocking, and unsafe event escalation.',
  },
  finance: {
    label: 'Finance',
    description: 'Handles billing, plan payments, balances, refunds, and payment records.',
  },
  payouts_manager: {
    label: 'Payouts Manager',
    description: 'Reviews and updates organizer payout requests.',
  },
  marketing_manager: {
    label: 'Marketing Manager',
    description: 'Manages promotions, contacts, messages, SMS opt-outs, and promotion packages.',
  },
  creative_services: {
    label: 'Creative Services',
    description: 'Handles brand guides, flyer requests, creative jobs, and deliveries.',
  },
  content_curator: {
    label: 'Content Curator',
    description: 'Manages public event quality, discovery, social content, and featured content.',
  },
  read_only: {
    label: 'Read-Only / Auditor',
    description: 'Can review operational records without making changes.',
  },
}

export const staffRoleOptions = Object.entries(adminRoleDefinitions)
  .filter(([id, role]) => id !== 'admin' && !role.aliasOf)
  .map(([id, role]) => ({
    id: id as AdminRoleId,
    label: role.label,
    description: role.description,
  }))

const collectionPermissions: Partial<
  Record<AdminCollectionId, { read: AdminRoleId[]; write: AdminRoleId[]; delete?: AdminRoleId[] }>
> = {
  users: {
    read: [
      'superadmin',
      'operations_manager',
      'customer_support',
      'organizer_success',
      'organizer_approvals',
      'event_operations',
      'trust_safety',
      'finance',
      'payouts_manager',
      'marketing_manager',
      'creative_services',
      'content_curator',
      'read_only',
    ],
    write: ['superadmin', 'operations_manager', 'customer_support', 'trust_safety'],
  },
  admins: { read: ['superadmin'], write: ['superadmin'], delete: ['superadmin'] },
  organizations: {
    read: [
      'superadmin',
      'operations_manager',
      'customer_support',
      'organizer_success',
      'organizer_approvals',
      'event_operations',
      'trust_safety',
      'finance',
      'payouts_manager',
      'marketing_manager',
      'creative_services',
      'content_curator',
      'read_only',
    ],
    write: ['superadmin', 'operations_manager', 'customer_support', 'organizer_success', 'organizer_approvals'],
  },
  organization_members: {
    read: [
      'superadmin',
      'operations_manager',
      'customer_support',
      'organizer_success',
      'organizer_approvals',
      'event_operations',
      'read_only',
    ],
    write: ['superadmin', 'operations_manager', 'organizer_success', 'organizer_approvals'],
  },
  organizer_applications: {
    read: ['superadmin', 'operations_manager', 'customer_support', 'organizer_success', 'organizer_approvals', 'read_only'],
    write: ['superadmin', 'operations_manager', 'organizer_success', 'organizer_approvals'],
  },
  events: {
    read: [
      'superadmin',
      'operations_manager',
      'customer_support',
      'organizer_success',
      'event_operations',
      'trust_safety',
      'finance',
      'marketing_manager',
      'creative_services',
      'content_curator',
      'read_only',
    ],
    write: ['superadmin', 'operations_manager', 'event_operations', 'trust_safety', 'content_curator'],
  },
  event_occurrences: {
    read: ['superadmin', 'operations_manager', 'customer_support', 'event_operations', 'marketing_manager', 'content_curator', 'read_only'],
    write: ['superadmin', 'operations_manager', 'event_operations', 'content_curator'],
  },
  share_links: {
    read: ['superadmin', 'operations_manager', 'customer_support', 'event_operations', 'marketing_manager', 'content_curator', 'read_only'],
    write: ['superadmin', 'operations_manager', 'event_operations', 'content_curator'],
  },
  places: {
    read: ['superadmin', 'operations_manager', 'customer_support', 'organizer_success', 'event_operations', 'marketing_manager', 'content_curator', 'read_only'],
    write: ['superadmin', 'operations_manager', 'organizer_success', 'event_operations', 'content_curator'],
  },
  place_menu_sections: {
    read: ['superadmin', 'operations_manager', 'customer_support', 'event_operations', 'marketing_manager', 'read_only'],
    write: ['superadmin', 'operations_manager', 'event_operations'],
  },
  place_menu_items: {
    read: ['superadmin', 'operations_manager', 'customer_support', 'event_operations', 'marketing_manager', 'read_only'],
    write: ['superadmin', 'operations_manager', 'event_operations'],
  },
  place_reservations: {
    read: ['superadmin', 'operations_manager', 'customer_support', 'event_operations', 'marketing_manager', 'read_only'],
    write: ['superadmin', 'operations_manager', 'customer_support', 'event_operations'],
  },
  place_subscriptions: {
    read: ['superadmin', 'operations_manager', 'customer_support', 'marketing_manager', 'read_only'],
    write: ['superadmin', 'operations_manager', 'marketing_manager'],
  },
  place_verifications: {
    read: ['superadmin', 'operations_manager', 'customer_support', 'organizer_success', 'trust_safety', 'read_only'],
    write: ['superadmin', 'operations_manager', 'trust_safety'],
  },
  event_rsvps: {
    read: ['superadmin', 'operations_manager', 'customer_support', 'event_operations', 'marketing_manager', 'read_only'],
    write: ['superadmin', 'operations_manager', 'customer_support', 'event_operations'],
  },
  event_ticket_orders: {
    read: ['superadmin', 'operations_manager', 'customer_support', 'event_operations', 'finance', 'payouts_manager', 'read_only'],
    write: ['superadmin', 'operations_manager', 'customer_support', 'event_operations', 'finance'],
  },
  event_ticket_lookups: {
    read: ['superadmin', 'operations_manager', 'customer_support', 'event_operations', 'read_only'],
    write: ['superadmin', 'operations_manager', 'event_operations'],
  },
  tablePackages: {
    read: ['superadmin', 'operations_manager', 'customer_support', 'event_operations', 'finance', 'read_only'],
    write: ['superadmin', 'operations_manager', 'event_operations'],
  },
  table_bookings: {
    read: ['superadmin', 'operations_manager', 'customer_support', 'event_operations', 'finance', 'read_only'],
    write: ['superadmin', 'operations_manager', 'event_operations', 'finance'],
  },
  table_package_bookings: {
    read: ['superadmin', 'operations_manager', 'customer_support', 'event_operations', 'finance', 'payouts_manager', 'read_only'],
    write: ['superadmin', 'operations_manager', 'event_operations', 'finance'],
  },
  event_ops_configs: {
    read: ['superadmin', 'operations_manager', 'customer_support', 'event_operations', 'finance', 'read_only'],
    write: ['superadmin', 'operations_manager', 'event_operations'],
  },
  event_inventory_items: {
    read: ['superadmin', 'operations_manager', 'customer_support', 'event_operations', 'finance', 'read_only'],
    write: ['superadmin', 'operations_manager', 'event_operations'],
  },
  event_ops_staff: {
    read: ['superadmin', 'operations_manager', 'customer_support', 'event_operations', 'read_only'],
    write: ['superadmin', 'operations_manager', 'event_operations'],
  },
  event_ops_tabs: {
    read: ['superadmin', 'operations_manager', 'customer_support', 'event_operations', 'finance', 'payouts_manager', 'read_only'],
    write: ['superadmin', 'operations_manager', 'event_operations', 'finance'],
  },
  event_ops_reports: {
    read: ['superadmin', 'operations_manager', 'customer_support', 'event_operations', 'finance', 'payouts_manager', 'read_only'],
    write: ['superadmin', 'operations_manager', 'event_operations', 'finance'],
  },
  event_ops_onboarding_visuals: {
    read: ['superadmin', 'operations_manager', 'customer_support', 'organizer_success', 'event_operations', 'creative_services', 'read_only'],
    write: ['superadmin', 'operations_manager', 'event_operations', 'creative_services'],
  },
  event_reminders: {
    read: ['superadmin', 'operations_manager', 'customer_support', 'event_operations', 'marketing_manager', 'read_only'],
    write: ['superadmin', 'operations_manager', 'customer_support', 'event_operations', 'marketing_manager'],
  },
  event_reports: {
    read: ['superadmin', 'operations_manager', 'customer_support', 'trust_safety', 'event_operations', 'read_only'],
    write: ['superadmin', 'operations_manager', 'customer_support', 'trust_safety'],
  },
  support_tickets: {
    read: ['superadmin', 'operations_manager', 'customer_support', 'organizer_success', 'trust_safety', 'read_only'],
    write: ['superadmin', 'operations_manager', 'customer_support', 'organizer_success', 'trust_safety'],
  },
  event_posts: {
    read: ['superadmin', 'operations_manager', 'customer_support', 'trust_safety', 'content_curator', 'read_only'],
    write: ['superadmin', 'operations_manager', 'trust_safety', 'content_curator'],
  },
  gplus_events: {
    read: ['superadmin', 'operations_manager', 'marketing_manager', 'content_curator', 'read_only'],
    write: ['superadmin', 'operations_manager', 'marketing_manager', 'content_curator'],
  },
  gplus_profiles: {
    read: ['superadmin', 'operations_manager', 'marketing_manager', 'content_curator', 'read_only'],
    write: ['superadmin', 'operations_manager', 'marketing_manager', 'content_curator'],
  },
  gplus_media_gallery: {
    read: ['superadmin', 'operations_manager', 'marketing_manager', 'content_curator', 'read_only'],
    write: ['superadmin', 'operations_manager', 'marketing_manager', 'content_curator'],
  },
  gplus_sync_status: {
    read: ['superadmin', 'operations_manager', 'marketing_manager', 'content_curator', 'read_only'],
    write: ['superadmin'],
  },
  gelo_content_queue: {
    read: ['superadmin', 'operations_manager', 'marketing_manager', 'content_curator', 'read_only'],
    write: ['superadmin', 'operations_manager', 'marketing_manager', 'content_curator'],
  },
  gelo_event_launch_drafts: {
    read: ['superadmin', 'operations_manager', 'marketing_manager', 'content_curator', 'read_only'],
    write: ['superadmin', 'operations_manager', 'marketing_manager', 'content_curator'],
  },
  gelo_website_features: {
    read: ['superadmin', 'operations_manager', 'marketing_manager', 'content_curator', 'read_only'],
    write: ['superadmin', 'operations_manager', 'marketing_manager', 'content_curator'],
  },
  event_reviews: {
    read: ['superadmin', 'operations_manager', 'customer_support', 'trust_safety', 'content_curator', 'read_only'],
    write: ['superadmin', 'operations_manager', 'trust_safety', 'content_curator'],
  },
  post_comments: {
    read: ['superadmin', 'operations_manager', 'customer_support', 'trust_safety', 'content_curator', 'read_only'],
    write: ['superadmin', 'operations_manager', 'trust_safety', 'content_curator'],
  },
  post_likes: {
    read: ['superadmin', 'operations_manager', 'trust_safety', 'content_curator', 'read_only'],
    write: ['superadmin', 'operations_manager', 'trust_safety'],
  },
  social_follows: {
    read: ['superadmin', 'operations_manager', 'customer_support', 'trust_safety', 'content_curator', 'read_only'],
    write: ['superadmin', 'operations_manager', 'trust_safety'],
  },
  event_saves: {
    read: ['superadmin', 'operations_manager', 'customer_support', 'event_operations', 'marketing_manager', 'read_only'],
    write: ['superadmin', 'operations_manager', 'customer_support'],
  },
  promotion_campaigns: {
    read: ['superadmin', 'operations_manager', 'customer_support', 'marketing_manager', 'finance', 'read_only'],
    write: ['superadmin', 'operations_manager', 'marketing_manager'],
  },
  audience_contacts: {
    read: ['superadmin', 'operations_manager', 'customer_support', 'marketing_manager', 'read_only'],
    write: ['superadmin', 'operations_manager', 'marketing_manager'],
  },
  advertiser_wallets: {
    read: ['superadmin', 'operations_manager', 'finance', 'marketing_manager', 'read_only'],
    write: ['superadmin', 'operations_manager', 'finance'],
  },
  wallet_transactions: {
    read: ['superadmin', 'operations_manager', 'finance', 'marketing_manager', 'payouts_manager', 'read_only'],
    write: ['superadmin', 'operations_manager', 'finance'],
  },
  notification_jobs: {
    read: ['superadmin', 'operations_manager', 'customer_support', 'marketing_manager', 'read_only'],
    write: ['superadmin', 'operations_manager', 'marketing_manager'],
  },
  push_queue: {
    read: ['superadmin', 'operations_manager', 'customer_support', 'marketing_manager', 'read_only'],
    write: ['superadmin', 'operations_manager', 'marketing_manager'],
  },
  admin_notifications: {
    read: ['superadmin', 'operations_manager', 'customer_support', 'organizer_success', 'trust_safety', 'read_only'],
    write: ['superadmin', 'operations_manager'],
  },
  sms_opt_out: {
    read: ['superadmin', 'operations_manager', 'customer_support', 'marketing_manager', 'read_only'],
    write: ['superadmin', 'operations_manager', 'customer_support', 'marketing_manager'],
  },
  promo_packages: {
    read: ['superadmin', 'operations_manager', 'finance', 'marketing_manager', 'read_only'],
    write: ['superadmin', 'operations_manager', 'marketing_manager'],
  },
  creative_brand_configs: {
    read: ['superadmin', 'operations_manager', 'customer_support', 'organizer_success', 'creative_services', 'read_only'],
    write: ['superadmin', 'operations_manager', 'organizer_success', 'creative_services'],
  },
  flyer_jobs: {
    read: ['superadmin', 'operations_manager', 'customer_support', 'creative_services', 'finance', 'read_only'],
    write: ['superadmin', 'operations_manager', 'creative_services'],
  },
  flyer_sessions: {
    read: ['superadmin', 'operations_manager', 'creative_services', 'finance', 'read_only'],
    write: ['superadmin', 'operations_manager', 'creative_services'],
  },
  payout_requests: {
    read: ['superadmin', 'operations_manager', 'finance', 'payouts_manager', 'read_only'],
    write: ['superadmin', 'operations_manager', 'payouts_manager'],
  },
  app_config: {
    // Holds payment-provider secrets (Hubtel API keys, callbackSecret). Restrict
    // to superadmin only — must stay in sync with functions/admin_permissions.js,
    // where operations_manager is intentionally denied read/write of payment creds.
    read: ['superadmin'],
    write: ['superadmin'],
  },
  rate_limits: {
    read: ['superadmin', 'operations_manager', 'trust_safety'],
    write: ['superadmin', 'operations_manager', 'trust_safety'],
  },
}

const actionPermissions: Record<AdminAction, AdminRoleId[]> = {
  manage_staff: ['superadmin'],
  update_auth_users: ['superadmin'],
  review_organizers: ['superadmin', 'operations_manager', 'organizer_success', 'organizer_approvals'],
  read_pricing: ['superadmin', 'operations_manager', 'finance', 'marketing_manager'],
  manage_pricing: ['superadmin', 'operations_manager'],
  manage_promo_packages: ['superadmin', 'operations_manager', 'marketing_manager'],
  read_campaigns: ['superadmin', 'operations_manager', 'customer_support', 'marketing_manager', 'finance'],
  read_analytics: ['superadmin', 'operations_manager', 'finance', 'marketing_manager', 'read_only'],
  manage_support: ['superadmin', 'operations_manager', 'customer_support', 'organizer_success', 'trust_safety'],
  record_sms_opt_out: ['superadmin', 'operations_manager', 'customer_support', 'marketing_manager'],
}

export function normalizeAdminRole(value: string | null | undefined): AdminRoleId | '' {
  const role = String(value || '').trim().toLowerCase().replace(/[\s-]+/g, '_')
  if (role === 'owner' || role === 'super_admin') return 'superadmin'
  return role in adminRoleDefinitions ? (role as AdminRoleId) : ''
}

export function effectiveAdminRole(value: string | null | undefined): AdminRoleId | '' {
  const role = normalizeAdminRole(value)
  if (!role) return ''
  return adminRoleDefinitions[role].aliasOf ?? role
}

export function isKnownAdminRole(value: string | null | undefined) {
  return Boolean(normalizeAdminRole(value))
}

export function isOwnerAdminRole(value: string | null | undefined) {
  return effectiveAdminRole(value) === 'superadmin'
}

export function getAdminRoleLabel(value: string | null | undefined) {
  const role = normalizeAdminRole(value)
  return role ? adminRoleDefinitions[role].label : 'Admin'
}

function roleListAllows(role: string | null | undefined, roles: AdminRoleId[]) {
  const normalized = normalizeAdminRole(role)
  const effective = effectiveAdminRole(role)
  return Boolean(normalized && roles.includes(normalized)) || Boolean(effective && roles.includes(effective))
}

export function canReadAdminCollection(role: string | null | undefined, collectionId: AdminCollectionId) {
  if (effectiveAdminRole(role) === 'superadmin') return true
  return roleListAllows(role, collectionPermissions[collectionId]?.read ?? [])
}

export function canWriteAdminCollection(role: string | null | undefined, collectionId: AdminCollectionId) {
  if (effectiveAdminRole(role) === 'superadmin') return true
  return roleListAllows(role, collectionPermissions[collectionId]?.write ?? [])
}

export function canDeleteAdminCollection(role: string | null | undefined, collectionId: AdminCollectionId) {
  return roleListAllows(role, collectionPermissions[collectionId]?.delete ?? ['superadmin'])
}

export function canPerformAdminAction(role: string | null | undefined, action: AdminAction) {
  if (effectiveAdminRole(role) === 'superadmin') return true
  return roleListAllows(role, actionPermissions[action] ?? [])
}
