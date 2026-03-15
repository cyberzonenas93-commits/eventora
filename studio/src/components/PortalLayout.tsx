import { NavLink, Outlet, useNavigate } from 'react-router-dom'

import { usePortalSession } from '../lib/portalSession'
import { titleCaseStatus } from '../lib/formatters'

export function PortalLayout() {
  const { profile, status, signOut } = usePortalSession()
  const navigate = useNavigate()

  return (
    <div className="studio-shell">
      <aside className="studio-sidebar">
        <div className="studio-brand">
          <div className="studio-brand__mark">E</div>
          <div>
            <strong>Eventora Studio</strong>
            <span>Organizer portal</span>
          </div>
        </div>

        <nav className="studio-nav">
          <NavLink to="/overview">Overview</NavLink>
          <NavLink to="/events">Events</NavLink>
          <NavLink to="/events/new">Create event</NavLink>
          <NavLink to="/settings">Settings</NavLink>
        </nav>

        <div className="studio-sidebar__footer">
          <div className="studio-sidebar__meta">
            <span>Status</span>
            <strong>{titleCaseStatus(status)}</strong>
          </div>
          <button
            className="button button--ghost"
            onClick={async () => {
              await signOut()
              navigate('/')
            }}
            type="button"
          >
            Sign out
          </button>
        </div>
      </aside>

      <main className="studio-main">
        <header className="studio-topbar">
          <div>
            <p className="eyebrow">Organizer workspace</p>
            <h1>{profile?.displayName || 'Eventora Studio'}</h1>
          </div>
          <div className="status-pill">{titleCaseStatus(status)}</div>
        </header>

        <section className="studio-content">
          <Outlet />
        </section>
      </main>
    </div>
  )
}
