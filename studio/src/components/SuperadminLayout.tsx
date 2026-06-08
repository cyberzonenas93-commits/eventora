import { useEffect, useRef, useState } from 'react'
import { collection, onSnapshot, query, where } from 'firebase/firestore'
import {
  Activity,
  AlertTriangle,
  BadgeCheck,
  BarChart3,
  Bell,
  CalendarDays,
  LayoutDashboard,
  LifeBuoy,
  LogOut,
  Megaphone,
  MessageSquareOff,
  Package,
  ReceiptText,
  Settings,
  ShieldCheck,
  Sparkles,
  UserCircle,
  Users,
  type LucideIcon,
} from 'lucide-react'
import { NavLink, Outlet, useLocation, useNavigate } from 'react-router-dom'

import { db } from '../firebaseDb'
import type { AdminCollectionId } from '../lib/adminConsole'
import {
  canPerformAdminAction,
  canReadAdminCollection,
  getAdminRoleLabel,
  type AdminAction,
} from '../lib/adminRoles'
import { usePortalSession } from '../lib/portalSession'

interface AdminNavItem {
  to: string
  label: string
  icon: LucideIcon
  action?: AdminAction
  collectionId?: AdminCollectionId
  end?: boolean
  badgeKey?: 'support'
}

const primaryNav: AdminNavItem[] = [
  { to: '/admin/overview', label: 'Overview', icon: LayoutDashboard },
  { to: '/admin/analytics', label: 'Analytics', icon: BarChart3, action: 'read_analytics' },
  { to: '/admin/approvals', label: 'Approvals', icon: BadgeCheck, action: 'review_organizers' },
  { to: '/admin/data/users', label: 'People', icon: Users, collectionId: 'users' },
  { to: '/admin/data/organizations', label: 'Organizers', icon: ShieldCheck, collectionId: 'organizations' },
  { to: '/admin/data/events', label: 'Events', icon: CalendarDays, collectionId: 'events' },
  { to: '/admin/data/event_ticket_orders', label: 'Tickets & orders', icon: ReceiptText, collectionId: 'event_ticket_orders' },
]

const operationsNav: AdminNavItem[] = [
  { to: '/admin/moderation', label: 'Reports & safety', icon: AlertTriangle, collectionId: 'event_reports' },
  { to: '/admin/data/event_posts', label: 'Social', icon: Activity, collectionId: 'event_posts' },
  { to: '/admin/support', label: 'Support', icon: LifeBuoy, action: 'manage_support', badgeKey: 'support' },
  { to: '/admin/campaigns', label: 'Campaigns', icon: Megaphone, action: 'read_campaigns' },
  { to: '/admin/data/flyer_jobs', label: 'Creative', icon: Sparkles, collectionId: 'flyer_jobs' },
  { to: '/admin/pricing', label: 'Pricing', icon: Package, action: 'read_pricing' },
]

const systemNav: AdminNavItem[] = [
  { to: '/admin/optout', label: 'SMS opt-out', icon: MessageSquareOff, action: 'record_sms_opt_out' },
  { to: '/admin/data/app_config', label: 'App settings', icon: Settings, collectionId: 'app_config' },
  { to: '/admin/data/notification_jobs', label: 'Messages', icon: Bell, collectionId: 'notification_jobs' },
]

const allNav = [...primaryNav, ...operationsNav, ...systemNav]

export function SuperadminLayout() {
  const session = usePortalSession()
  const navigate = useNavigate()
  const location = useLocation()
  const visiblePrimaryNav = primaryNav.filter((item) => canShowNavItem(session.adminRole, item))
  const visibleOperationsNav = operationsNav.filter((item) => canShowNavItem(session.adminRole, item))
  const visibleSystemNav = systemNav.filter((item) => canShowNavItem(session.adminRole, item))
  const visibleNav = [...visiblePrimaryNav, ...visibleOperationsNav, ...visibleSystemNav]
  const [supportUnread, setSupportUnread] = useState(0)
  const previousSupportUnread = useRef<number | null>(null)
  const canManageSupport = canPerformAdminAction(session.adminRole, 'manage_support')
  const visibleSupportUnread = canManageSupport ? supportUnread : 0
  const activeItem =
    (visibleNav.length > 0 ? visibleNav : allNav)
      .slice()
      .reverse()
      .find((item) => location.pathname.startsWith(item.to)) ?? allNav[0]

  useEffect(() => {
    if (!canManageSupport) {
      previousSupportUnread.current = null
      return undefined
    }

    const unreadQuery = query(
      collection(db, 'support_tickets'),
      where('adminUnreadCount', '>', 0),
    )
    return onSnapshot(unreadQuery, (snapshot) => {
      const unread = snapshot.docs.reduce((sum, docSnap) => {
        const count = Number(docSnap.data().adminUnreadCount ?? 0)
        return sum + (Number.isFinite(count) ? count : 0)
      }, 0)
      if (
        previousSupportUnread.current != null &&
        unread > previousSupportUnread.current &&
        typeof Notification !== 'undefined' &&
        Notification.permission === 'granted'
      ) {
        new Notification('New Vennuzo support message', {
          body: 'A support ticket needs a reply.',
        })
      }
      previousSupportUnread.current = unread
      setSupportUnread(unread)
    })
  }, [canManageSupport])

  async function handleSignOut() {
    await session.signOut()
    navigate('/admin', { replace: true })
  }

  return (
    <div className="superadmin-shell" role="application" aria-label="Vennuzo admin console">
      <aside className="superadmin-sidebar" aria-label="Admin navigation">
        <div className="studio-brand">
          <div className="studio-brand__mark" aria-hidden>
            <img src="/logo-mark.png" alt="" />
          </div>
              <div>
                <strong>Vennuzo Admin</strong>
                <span>Staff workspace</span>
              </div>
            </div>

        <AdminNavSection badges={{ support: visibleSupportUnread }} items={visiblePrimaryNav} label="Daily work" />
        <AdminNavSection badges={{ support: visibleSupportUnread }} items={visibleOperationsNav} label="Manage" />
        <AdminNavSection badges={{ support: visibleSupportUnread }} items={visibleSystemNav} label="Settings" />

        <div className="superadmin-sidebar__footer">
          <div>
            <span>Signed in</span>
            <strong>{session.profile?.email || session.user?.email || 'Admin'}</strong>
            <small>{getAdminRoleLabel(session.adminRole)}</small>
          </div>
          <button className="button button--ghost button--full" onClick={handleSignOut} type="button">
            <LogOut size={16} aria-hidden />
            Sign out
          </button>
        </div>
      </aside>

      <main className="superadmin-main">
        <header className="superadmin-topbar">
          <div>
            <h1>{activeItem?.label ?? 'Vennuzo Admin'}</h1>
            <p>Review, update, and support Vennuzo operations.</p>
          </div>
          <div className="superadmin-topbar__tools">
            <div className="superadmin-command" aria-label="Admin context">
              <UserCircle size={15} aria-hidden />
              <span>{session.profile?.email || session.user?.email || 'Admin session'}</span>
            </div>
            <div className="status-pill status-pill--approved">
              {getAdminRoleLabel(session.adminRole)}
            </div>
          </div>
        </header>
        <section className="superadmin-content">
          <Outlet />
        </section>
      </main>
    </div>
  )
}

function AdminNavSection({
  badges,
  items,
  label,
}: {
  badges: Partial<Record<'support', number>>
  items: AdminNavItem[]
  label: string
}) {
  if (items.length === 0) return null
  return (
    <nav className="superadmin-nav" aria-label={label}>
      <span className="superadmin-nav__label">{label}</span>
      {items.map((item) => (
        <NavLink end={item.end} key={item.to} to={item.to}>
          <item.icon size={16} aria-hidden />
          <strong>{item.label}</strong>
          {item.badgeKey && (badges[item.badgeKey] ?? 0) > 0 ? (
            <span className="superadmin-nav__badge">
              {(badges[item.badgeKey] ?? 0) > 99 ? '99+' : badges[item.badgeKey]}
            </span>
          ) : null}
        </NavLink>
      ))}
    </nav>
  )
}

function canShowNavItem(role: string, item: AdminNavItem) {
  const hasActionAccess = item.action ? canPerformAdminAction(role, item.action) : true
  const hasCollectionAccess = item.collectionId ? canReadAdminCollection(role, item.collectionId) : true
  return hasActionAccess && hasCollectionAccess
}
