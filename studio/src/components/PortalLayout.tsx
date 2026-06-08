import type { CSSProperties } from 'react'
import { useEffect, useState } from 'react'
import {
  BarChart3,
  CalendarDays,
  ContactRound,
  CreditCard,
  Handshake,
  LogOut,
  Megaphone,
  Menu,
  Monitor,
  Moon,
  MoreHorizontal,
  Plus,
  ReceiptText,
  ScanLine,
  Settings,
  Sparkles,
  Store,
  Sun,
  Table2,
  TicketPlus,
  UsersRound,
  X,
  type LucideIcon,
} from 'lucide-react'
import { Link, NavLink, Outlet, useLocation, useNavigate } from 'react-router-dom'

import { titleCaseStatus } from '../lib/formatters'
import {
  getPayoutReadiness,
  getWorkspaceAccent,
  getWorkspaceName,
  getWorkspaceTagline,
} from '../lib/merchantWorkspace'
import { useThemeContext } from '../lib/ThemeContext'
import { usePortalSession } from '../lib/portalSession'

export function PortalLayout() {
  const { application, profile, status, signOut } = usePortalSession()
  const { theme, isAuto, toggleOverride } = useThemeContext()
  const navigate = useNavigate()
  const location = useLocation()
  const [mobileDrawerOpen, setMobileDrawerOpen] = useState(false)
  const workspaceName = getWorkspaceName(application, profile)
  const workspaceTagline = getWorkspaceTagline(application)
  const accentColor = getWorkspaceAccent(application)
  const payoutReadiness = getPayoutReadiness(application)
  const primaryNav: Array<{ to: string; label: string; icon: LucideIcon; end?: boolean }> = [
    { to: '/studio/overview', label: 'Overview', icon: BarChart3 },
    { to: '/studio/events', label: 'Events', icon: CalendarDays, end: true },
    { to: '/studio/analytics', label: 'Analytics', icon: BarChart3 },
    { to: '/studio/orders', label: 'Orders', icon: ReceiptText },
    { to: '/studio/contacts', label: 'Contacts', icon: ContactRound },
    { to: '/studio/payments', label: 'Payments', icon: CreditCard },
    { to: '/studio/promoters', label: 'Partners', icon: Handshake },
    { to: '/studio/tables', label: 'Tables', icon: Table2 },
    { to: '/studio/places', label: 'Places', icon: Store },
    { to: '/studio/operations', label: 'Operations', icon: ScanLine },
    { to: '/studio/team', label: 'Team', icon: UsersRound },
  ]
  const actionNav: Array<{ to: string; label: string; icon: LucideIcon }> = [
    { to: '/studio/events/new', label: 'Create event', icon: TicketPlus },
    { to: '/studio/promote', label: 'Promote event', icon: Megaphone },
    { to: '/studio/creative', label: 'Creative services', icon: Sparkles },
    { to: '/studio/settings', label: 'Settings', icon: Settings },
  ]

  useEffect(() => {
    const frame = window.requestAnimationFrame(() => setMobileDrawerOpen(false))
    return () => window.cancelAnimationFrame(frame)
  }, [location.pathname])

  // Scroll to top when switching tabs so the new screen is in view
  useEffect(() => {
    window.scrollTo({ top: 0, behavior: 'smooth' })
  }, [location.pathname])

  useEffect(() => {
    if (!mobileDrawerOpen) return
    function onKeyDown(e: KeyboardEvent) {
      if (e.key === 'Escape') setMobileDrawerOpen(false)
    }
    window.addEventListener('keydown', onKeyDown)
    return () => window.removeEventListener('keydown', onKeyDown)
  }, [mobileDrawerOpen])

  const closeDrawer = () => {
    setMobileDrawerOpen(false)
  }

  const ThemeIcon = isAuto ? Monitor : theme === 'dark' ? Sun : Moon
  const themeLabel = isAuto ? 'Auto' : theme === 'dark' ? 'Light mode' : 'Dark mode'
  const themeTitle = isAuto
    ? 'Auto theme (time-based) — click to force dark'
    : theme === 'dark'
      ? 'Forced dark — click to force light'
      : 'Forced light — click to reset to auto'

  return (
    <div
      className={`studio-shell page-motion${mobileDrawerOpen ? ' studio-drawer-open' : ''}`}
      data-theme={theme}
      role="application"
      aria-label="Vennuzo Studio"
    >
      {/* Mobile: top bar */}
      <header className="studio-mobile-header" aria-label="Mobile navigation">
        <div className="studio-mobile-header__brand">
          <div className="studio-brand__mark" aria-hidden>
            <img src="/logo-mark.png" alt="" />
          </div>
          <span className="studio-mobile-header__title">{workspaceName}</span>
        </div>
        <button
          type="button"
          className="studio-mobile-header__menu"
          onClick={() => setMobileDrawerOpen((o) => !o)}
          aria-expanded={mobileDrawerOpen}
          aria-label={mobileDrawerOpen ? 'Close menu' : 'Open menu'}
        >
          {mobileDrawerOpen ? <X size={20} aria-hidden /> : <Menu size={20} aria-hidden />}
        </button>
      </header>

      {/* Drawer overlay (mobile): a real, keyboard-accessible button so it can be
          activated with Enter/Space and announced by screen readers (Escape and
          the header toggle also close the drawer). */}
      <button
        type="button"
        className="studio-drawer-backdrop"
        aria-label="Close menu"
        onClick={closeDrawer}
        style={{ border: 'none', padding: 0, margin: 0, cursor: 'pointer' }}
      />

      <aside className="studio-sidebar studio-drawer" aria-label="Main navigation">
        <div className="studio-sidebar__scroll">
          <button
            type="button"
            className="studio-drawer__close"
            onClick={(e) => {
              e.preventDefault()
              e.stopPropagation()
              closeDrawer()
            }}
            aria-label="Close menu"
          >
            <X size={18} aria-hidden />
          </button>
          <div className="studio-brand">
            <div className="studio-brand__mark" aria-hidden>
              <img src="/logo-mark.png" alt="" />
            </div>
            <div>
              <strong>Vennuzo Studio</strong>
              <span>Event operating system</span>
            </div>
          </div>

          <div className="workspace-badge-card" style={{ '--workspace-accent': accentColor } as CSSProperties}>
            <span className="eyebrow">Workspace</span>
            <strong>{workspaceName}</strong>
            <small>
              {application?.audienceCity?.trim() || 'Accra'} · {application?.businessType?.trim() || 'Organizer'}
            </small>
          </div>

          <nav className="studio-nav">
            {primaryNav.map((item) => (
              <NavLink end={item.end} key={item.to} to={item.to}>
                <span className="studio-nav-icon" aria-hidden>
                  <item.icon size={17} strokeWidth={2.1} />
                </span>
                <strong>{item.label}</strong>
              </NavLink>
            ))}
            <div className="studio-nav__divider" />
            {actionNav.map((item) => (
              <NavLink key={item.to} to={item.to}>
                <span className="studio-nav-icon" aria-hidden>
                  <item.icon size={17} strokeWidth={2.1} />
                </span>
                <strong>{item.label}</strong>
              </NavLink>
            ))}
          </nav>

          <div className="studio-sidebar__meta">
            <span>Workspace status</span>
            <strong>{status === 'active' ? 'Live' : titleCaseStatus(status)}</strong>
            <small className={payoutReadiness.ready ? 'meta-chip meta-chip--ready' : 'meta-chip'}>
              {payoutReadiness.label}
            </small>
          </div>

          <div className="studio-sidebar__footer">
            <button
              type="button"
              className="theme-toggle"
              onClick={toggleOverride}
              title={themeTitle}
              aria-label={themeTitle}
            >
              <ThemeIcon size={16} aria-hidden />
              <span>{themeLabel}</span>
            </button>
            <Link className="button button--primary button--full" to="/studio/events/new">
              <Plus size={16} aria-hidden />
              Create a new event
            </Link>
            <button
              className="button button--ghost button--full"
              onClick={async () => {
                await signOut()
                navigate('/studio')
              }}
              type="button"
            >
              <LogOut size={16} aria-hidden />
              Sign out
            </button>
          </div>
        </div>
      </aside>

      <main className="studio-main">
        <header className="studio-topbar">
          <div>
            <p className="eyebrow">Organizer workspace</p>
            <h1>{workspaceName}</h1>
            {workspaceTagline ? <p>{workspaceTagline}</p> : null}
          </div>
          <div className="studio-topbar__actions">
            <div className={`status-pill status-pill--${status}`}>
              {status === 'active' ? 'Live' : titleCaseStatus(status)}
            </div>
            <Link className="button button--secondary" to="/studio/events">
              <CalendarDays size={16} aria-hidden />
              Open events
            </Link>
          </div>
        </header>

        <section className="studio-content page-motion__content">
          <Outlet key={location.pathname} />
        </section>
      </main>

      {/* Mobile: bottom nav */}
      <nav className="studio-bottomnav" aria-label="Quick navigation">
        <NavLink to="/studio/overview" className="studio-bottomnav__item">
          <BarChart3 className="studio-bottomnav__icon" size={19} aria-hidden />
          <span>Overview</span>
        </NavLink>
        <NavLink to="/studio/events" end className="studio-bottomnav__item">
          <CalendarDays className="studio-bottomnav__icon" size={19} aria-hidden />
          <span>Events</span>
        </NavLink>
        <NavLink to="/studio/events/new" className="studio-bottomnav__item studio-bottomnav__item--primary">
          <Plus className="studio-bottomnav__icon" size={20} aria-hidden />
          <span>Create</span>
        </NavLink>
        <NavLink to="/studio/payments" className="studio-bottomnav__item">
          <CreditCard className="studio-bottomnav__icon" size={19} aria-hidden />
          <span>Payments</span>
        </NavLink>
        <button
          type="button"
          className="studio-bottomnav__item"
          onClick={() => setMobileDrawerOpen(true)}
          aria-label="More menu"
        >
          <MoreHorizontal className="studio-bottomnav__icon" size={20} aria-hidden />
          <span>More</span>
        </button>
      </nav>
    </div>
  )
}
