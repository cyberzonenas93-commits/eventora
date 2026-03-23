import type { CSSProperties } from 'react'
import { useEffect, useState } from 'react'
import { Link, NavLink, Outlet, useLocation, useNavigate } from 'react-router-dom'

import { titleCaseStatus } from '../lib/formatters'
import {
  getPayoutReadiness,
  getWorkspaceAccent,
  getWorkspaceName,
  getWorkspaceTagline,
} from '../lib/merchantWorkspace'
import { usePortalSession } from '../lib/portalSession'

export function PortalLayout() {
  const { application, profile, status, signOut } = usePortalSession()
  const navigate = useNavigate()
  const location = useLocation()
  const [mobileDrawerOpen, setMobileDrawerOpen] = useState(false)
  const firstName = profile?.displayName?.trim().split(' ')[0] || 'Organizer'
  const workspaceName = getWorkspaceName(application, profile)
  const workspaceTagline = getWorkspaceTagline(application)
  const accentColor = getWorkspaceAccent(application)
  const payoutReadiness = getPayoutReadiness(application)

  // Always start with drawer closed (avoids stuck-open on load/hydration)
  useEffect(() => {
    setMobileDrawerOpen(false)
  }, [])

  useEffect(() => {
    setMobileDrawerOpen(false)
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

  return (
    <div
      className={`studio-shell page-motion${mobileDrawerOpen ? ' studio-drawer-open' : ''}`}
      role="application"
      aria-label="Vennuzo Studio"
    >
      {/* Mobile: top bar */}
      <header className="studio-mobile-header" aria-label="Mobile navigation">
        <div className="studio-mobile-header__brand">
          <div className="studio-brand__mark" aria-hidden>E</div>
          <span className="studio-mobile-header__title">{workspaceName}</span>
        </div>
        <button
          type="button"
          className="studio-mobile-header__menu"
          onClick={() => setMobileDrawerOpen((o) => !o)}
          aria-expanded={mobileDrawerOpen}
          aria-label={mobileDrawerOpen ? 'Close menu' : 'Open menu'}
        >
          <span className="studio-mobile-header__menu-icon" aria-hidden />
        </button>
      </header>

      {/* Drawer overlay (mobile): tap or click to close */}
      <div
        className="studio-drawer-backdrop"
        aria-hidden
        onClick={(e) => {
          e.preventDefault()
          e.stopPropagation()
          closeDrawer()
        }}
        onTouchEnd={(e) => {
          e.preventDefault()
          e.stopPropagation()
          closeDrawer()
        }}
        role="button"
        tabIndex={-1}
        aria-label="Close menu"
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
            <span aria-hidden>×</span>
          </button>
          <div className="studio-brand">
            <div className="studio-brand__mark">E</div>
            <div>
              <strong>Vennuzo Studio</strong>
              <span>Organizer portal</span>
            </div>
          </div>

          <div className="studio-sidebar__intro">
            <p className="eyebrow">Organizer command center</p>
            <h2>{firstName}, keep every launch moving.</h2>
          </div>

          <div className="workspace-badge-card" style={{ '--workspace-accent': accentColor } as CSSProperties}>
            <span className="eyebrow">Workspace identity</span>
            <strong>{workspaceName}</strong>
            <small>
              {application?.audienceCity?.trim() || 'Accra'} • {application?.businessType?.trim() || 'Organizer workspace'}
            </small>
          </div>

          <nav className="studio-nav">
            <NavLink to="/studio/overview">
              <strong>Overview</strong>
            </NavLink>
            <NavLink to="/studio/events">
              <strong>Events</strong>
            </NavLink>
            <NavLink to="/studio/orders">
              <strong>Orders</strong>
            </NavLink>
            <NavLink to="/studio/contacts">
              <strong>Contacts</strong>
            </NavLink>
            <NavLink to="/studio/payments">
              <strong>Payments &amp; Payouts</strong>
            </NavLink>
            <NavLink to="/studio/promoters">
              <strong>Partners</strong>
            </NavLink>
            <NavLink to="/studio/events/new">
              <strong>Create event</strong>
            </NavLink>
            <NavLink to="/studio/promote">
              <strong>Promote event</strong>
            </NavLink>
            <NavLink to="/studio/settings">
              <strong>Settings</strong>
            </NavLink>
          </nav>

          <div className="studio-sidebar__meta">
            <span>Workspace status</span>
            <strong>{status === 'active' ? 'Live' : titleCaseStatus(status)}</strong>
            <small className={payoutReadiness.ready ? 'meta-chip meta-chip--ready' : 'meta-chip'}>
              {payoutReadiness.label}
            </small>
          </div>

          <div className="studio-sidebar__footer">
            <Link className="button button--primary button--full" to="/studio/events/new">
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
          <span className="studio-bottomnav__icon" aria-hidden>◉</span>
          <span>Overview</span>
        </NavLink>
        <NavLink to="/studio/events" end className="studio-bottomnav__item">
          <span className="studio-bottomnav__icon" aria-hidden>◎</span>
          <span>Events</span>
        </NavLink>
        <NavLink to="/studio/events/new" className="studio-bottomnav__item studio-bottomnav__item--primary">
          <span className="studio-bottomnav__icon" aria-hidden>+</span>
          <span>Create</span>
        </NavLink>
        <NavLink to="/studio/payments" className="studio-bottomnav__item">
          <span className="studio-bottomnav__icon" aria-hidden>¢</span>
          <span>Payments</span>
        </NavLink>
        <button
          type="button"
          className="studio-bottomnav__item"
          onClick={() => setMobileDrawerOpen(true)}
          aria-label="More menu"
        >
          <span className="studio-bottomnav__icon" aria-hidden>⋯</span>
          <span>More</span>
        </button>
      </nav>
    </div>
  )
}
