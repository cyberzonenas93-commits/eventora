import { Link, Outlet } from 'react-router-dom'

export function PublicLayout() {
  return (
    <div className="public-shell">
      <header className="public-header">
        <div className="public-header__inner">
          <Link to="/" className="public-header__brand">
            <span className="studio-brand__mark" aria-hidden>E</span>
            <span className="public-header__logo-text">Vennuzo</span>
          </Link>
          <nav className="public-header__nav">
            <Link to="/events" className="public-header__link">
              Events
            </Link>
            <Link to="/studio" className="public-header__cta">
              Organizer dashboard
            </Link>
          </nav>
        </div>
      </header>
      <main className="public-main">
        <Outlet />
      </main>
    </div>
  )
}
