import { NavLink, Outlet } from 'react-router-dom'

export function SuperadminLayout() {
  return (
    <main className="status-page status-page--reference">
      <nav className="superadmin-nav" style={{ marginBottom: '1.5rem', display: 'flex', flexWrap: 'wrap', gap: '0.5rem' }}>
        <NavLink
          to="/superadmin/approvals"
          className={({ isActive }) => (isActive ? 'button button--secondary is-active' : 'button button--ghost')}
          end
        >
          Approvals
        </NavLink>
        <NavLink
          to="/superadmin/pricing"
          className={({ isActive }) => (isActive ? 'button button--secondary is-active' : 'button button--ghost')}
        >
          Pricing & packages
        </NavLink>
        <NavLink
          to="/superadmin/campaigns"
          className={({ isActive }) => (isActive ? 'button button--secondary is-active' : 'button button--ghost')}
        >
          Campaigns
        </NavLink>
        <NavLink
          to="/superadmin/optout"
          className={({ isActive }) => (isActive ? 'button button--secondary is-active' : 'button button--ghost')}
        >
          SMS opt-out & webhook
        </NavLink>
      </nav>
      <Outlet />
    </main>
  )
}
