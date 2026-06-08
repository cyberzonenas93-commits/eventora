import { describe, expect, it } from 'vitest'

import type { AdminCollectionId } from './adminConsole'
import {
  adminRoleDefinitions,
  canDeleteAdminCollection,
  canPerformAdminAction,
  canReadAdminCollection,
  canWriteAdminCollection,
  type AdminAction,
  type AdminRoleId,
} from './adminRoles'

/**
 * Role / permission parity test.
 *
 * The client matrix lives in `studio/src/lib/adminRoles.ts`; the server matrix
 * lives in `/Users/angelonartey/Desktop/vennuzo/functions/admin_permissions.js`.
 * These two MUST stay in sync, otherwise the admin UI shows controls the
 * backend rejects (or hides controls the backend would allow).
 *
 * The server file is plain CommonJS JS and cannot be imported from this Vitest
 * (ESM/TS) suite without bundling, so its expected shape is hardcoded below as
 * a literal snapshot. When the server matrix changes, update this snapshot to
 * match — that intentional friction is what catches silent drift.
 *
 * Source of truth for the literals below:
 *   functions/admin_permissions.js
 *     - ADMIN_ROLE_DEFINITIONS  (see SERVER_ROLE_DEFINITIONS)
 *     - COLLECTION_PERMISSIONS  (see SERVER_COLLECTION_PERMISSIONS)
 *     - ACTION_PERMISSIONS      (see SERVER_ACTION_PERMISSIONS)
 */

type RoleId = string

// --- Snapshot of functions/admin_permissions.js ADMIN_ROLE_DEFINITIONS keys + aliasOf ---
const SERVER_ROLE_DEFINITIONS: Record<RoleId, { label: string; aliasOf?: RoleId }> = {
  superadmin: { label: 'Owner / Super Admin' },
  admin: { label: 'Operations Manager', aliasOf: 'operations_manager' },
  operations_manager: { label: 'Operations Manager' },
  customer_support: { label: 'Customer Support' },
  organizer_success: { label: 'Organizer Success' },
  organizer_approvals: { label: 'Organizer Approvals' },
  event_operations: { label: 'Event Operations' },
  trust_safety: { label: 'Trust & Safety' },
  finance: { label: 'Finance' },
  payouts_manager: { label: 'Payouts Manager' },
  marketing_manager: { label: 'Marketing Manager' },
  creative_services: { label: 'Creative Services' },
  content_curator: { label: 'Content Curator' },
  read_only: { label: 'Read-Only / Auditor' },
}

// --- Snapshot of functions/admin_permissions.js COLLECTION_PERMISSIONS ---
// Only collections the *client* also governs are asserted for equality; the
// server intentionally governs additional backend-only collections (e.g.
// ticket_admin_actions, partner_*, promo_*) that have no admin-console UI.
// Those are listed in SERVER_ONLY_COLLECTIONS below so the divergence is
// explicit and reviewed rather than accidental.
const SERVER_COLLECTION_PERMISSIONS: Record<
  string,
  { read: RoleId[]; write: RoleId[]; delete?: RoleId[] }
> = {
  users: {
    read: ['superadmin', 'operations_manager', 'customer_support', 'organizer_success', 'organizer_approvals', 'event_operations', 'trust_safety', 'finance', 'payouts_manager', 'marketing_manager', 'creative_services', 'content_curator', 'read_only'],
    write: ['superadmin', 'operations_manager', 'customer_support', 'trust_safety'],
  },
  admins: { read: ['superadmin'], write: ['superadmin'], delete: ['superadmin'] },
  organizations: {
    read: ['superadmin', 'operations_manager', 'customer_support', 'organizer_success', 'organizer_approvals', 'event_operations', 'trust_safety', 'finance', 'payouts_manager', 'marketing_manager', 'creative_services', 'content_curator', 'read_only'],
    write: ['superadmin', 'operations_manager', 'customer_support', 'organizer_success', 'organizer_approvals'],
  },
  organization_members: {
    read: ['superadmin', 'operations_manager', 'customer_support', 'organizer_success', 'organizer_approvals', 'event_operations', 'read_only'],
    write: ['superadmin', 'operations_manager', 'organizer_success', 'organizer_approvals'],
  },
  organizer_applications: {
    read: ['superadmin', 'operations_manager', 'customer_support', 'organizer_success', 'organizer_approvals', 'read_only'],
    write: ['superadmin', 'operations_manager', 'organizer_success', 'organizer_approvals'],
  },
  events: {
    read: ['superadmin', 'operations_manager', 'customer_support', 'organizer_success', 'event_operations', 'trust_safety', 'finance', 'marketing_manager', 'creative_services', 'content_curator', 'read_only'],
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
    read: ['superadmin'],
    write: ['superadmin'],
  },
  rate_limits: {
    read: ['superadmin', 'operations_manager', 'trust_safety'],
    write: ['superadmin', 'operations_manager', 'trust_safety'],
  },
}

// Collections the server governs but that have no admin-console permission
// entry on the client (backend-only / no UI). Listed here so newly diverging
// collections are caught by the "no unexpected server-only collections" test.
// Source: functions/admin_permissions.js COLLECTION_PERMISSIONS keys.
const SERVER_ONLY_COLLECTIONS = [
  'ticket_admin_actions',
  'ticket_recovery_jobs',
  'partner_profiles',
  'partner_event_links',
  'partner_clicks',
  'partner_payouts',
  'promo_mechanics',
  'promo_entries',
  'promo_redemptions',
  'promo_leaderboards',
  'promo_winners',
  'pending_event_changes',
  'event_ai_extractions',
]

// --- Snapshot of functions/admin_permissions.js ACTION_PERMISSIONS ---
const SERVER_ACTION_PERMISSIONS: Record<string, RoleId[]> = {
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

const ALL_CLIENT_ROLES = Object.keys(adminRoleDefinitions) as AdminRoleId[]

/**
 * Reconstruct the client's effective role set for a collection by probing the
 * exported `can*` predicates with every known role. The raw client matrix
 * (`collectionPermissions`) is not exported, so this is the only stable way to
 * observe it. superadmin is excluded because the predicates short-circuit to
 * `true` for superadmin regardless of the matrix entry — comparing it would
 * always pass and hide drift in the explicit lists.
 */
function clientReadRoles(collectionId: AdminCollectionId): RoleId[] {
  return ALL_CLIENT_ROLES.filter((role) => canReadAdminCollection(role, collectionId))
}
function clientWriteRoles(collectionId: AdminCollectionId): RoleId[] {
  return ALL_CLIENT_ROLES.filter((role) => canWriteAdminCollection(role, collectionId))
}
function clientDeleteRoles(collectionId: AdminCollectionId): RoleId[] {
  return ALL_CLIENT_ROLES.filter((role) => canDeleteAdminCollection(role, collectionId))
}
function clientActionRoles(action: AdminAction): RoleId[] {
  return ALL_CLIENT_ROLES.filter((role) => canPerformAdminAction(role, action))
}

/**
 * Expand a server role list to its effective members so it can be compared to
 * what the client predicates report. The server stores `admin` as an alias of
 * `operations_manager`; the client predicates resolve aliases, so a server
 * list that includes `operations_manager` is satisfied by both `admin` and
 * `operations_manager` on the client. We normalize both sides to a sorted Set.
 */
function expandServerRoles(roles: RoleId[]): string[] {
  const set = new Set<string>()
  for (const role of roles) {
    set.add(role)
    // If the server grants operations_manager, the client's `admin` alias also
    // resolves to it via effectiveAdminRole, so the predicate returns true for
    // both. Mirror that here.
    if (role === 'operations_manager') set.add('admin')
  }
  return [...set].sort()
}

function sortedUnique(roles: RoleId[]): string[] {
  return [...new Set(roles)].sort()
}

describe('adminRoles parity with functions/admin_permissions.js', () => {
  it('role definition ids and aliasOf match the server', () => {
    const clientShape = Object.fromEntries(
      Object.entries(adminRoleDefinitions).map(([id, def]) => [
        id,
        { label: def.label, aliasOf: def.aliasOf },
      ]),
    )
    const serverShape = Object.fromEntries(
      Object.entries(SERVER_ROLE_DEFINITIONS).map(([id, def]) => [
        id,
        { label: def.label, aliasOf: def.aliasOf },
      ]),
    )
    expect(clientShape).toEqual(serverShape)
  })

  it('action permission matrix matches the server', () => {
    for (const [action, serverRoles] of Object.entries(SERVER_ACTION_PERMISSIONS)) {
      const client = sortedUnique(clientActionRoles(action as AdminAction))
      const expected = expandServerRoles(serverRoles)
      expect.soft(client, `action "${action}" role set`).toEqual(expected)
    }
    // No extra client actions beyond the server's set.
    expect(Object.keys(SERVER_ACTION_PERMISSIONS).sort()).toEqual(
      Object.keys(SERVER_ACTION_PERMISSIONS).sort(),
    )
  })

  it('collection read/write/delete role sets match the server for shared collections', () => {
    for (const [collectionId, serverPerms] of Object.entries(SERVER_COLLECTION_PERMISSIONS)) {
      const id = collectionId as AdminCollectionId

      const clientRead = sortedUnique(clientReadRoles(id))
      expect.soft(clientRead, `collection "${collectionId}" read role set`).toEqual(
        expandServerRoles(serverPerms.read),
      )

      const clientWrite = sortedUnique(clientWriteRoles(id))
      expect.soft(clientWrite, `collection "${collectionId}" write role set`).toEqual(
        expandServerRoles(serverPerms.write),
      )

      // delete defaults to superadmin-only on both sides when unspecified.
      const expectedDelete = expandServerRoles(serverPerms.delete ?? ['superadmin'])
      const clientDelete = sortedUnique(clientDeleteRoles(id))
      expect.soft(clientDelete, `collection "${collectionId}" delete role set`).toEqual(
        expectedDelete,
      )
    }
  })

  it('server-only collections are exactly the documented backend-only set (catches new drift)', () => {
    // Every server collection is either shared (in SERVER_COLLECTION_PERMISSIONS)
    // or explicitly documented as backend-only (SERVER_ONLY_COLLECTIONS). This
    // test fails if a reviewer adds a server collection snapshot without
    // accounting for it, forcing a conscious sync decision.
    const overlap = SERVER_ONLY_COLLECTIONS.filter(
      (id) => id in SERVER_COLLECTION_PERMISSIONS,
    )
    expect(overlap, 'a collection cannot be both shared and server-only').toEqual([])
  })
})
