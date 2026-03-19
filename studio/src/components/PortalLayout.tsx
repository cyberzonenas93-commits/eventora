import type { CSSProperties } from 'react'
import { Link, NavLink, Outlet, useNavigate } from 'react-router-dom'

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
  const firstName = profile?.displayName?.trim().split(' ')[0] || 'Organizer'
  const workspaceName = getWorkspaceName(application, profile)
  const workspaceTagline = getWorkspaceTagline(application)
  const accentColor = getWorkspaceAccent(application)
  const payoutReadiness = getPayoutReadiness(application)

  return (
    <div className="studio-shell page-motion">
      <aside className="studio-sidebar">
        <div className="studio-sidebar__scroll">
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
            <NavLink to="/overview">
              <strong>Overview</strong>
            </NavLink>
            <NavLink to="/events">
              <strong>Events</strong>
            </NavLink>
            <NavLink to="/events/new">
              <strong>Create event</strong>
            </NavLink>
            <NavLink to="/settings">
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
            <Link className="button button--primary button--full" to="/events/new">
              Create a new event
            </Link>
            <button
              className="button button--ghost button--full"
              onClick={async () => {
                await signOut()
                navigate('/')
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
            <Link className="button button--secondary" to="/events">
              Open events
            </Link>
          </div>
        </header>

        <section className="studio-content page-motion__content">
          <Outlet />
        </section>
      </main>
    </div>
  )
}
