import { Link, Outlet } from 'react-router-dom'

export function PublicLayout() {
  return (
    <div className="public-shell">
      <header className="public-header">
        <div className="public-header__inner">
          <Link to="/" className="public-header__brand">
            <img src="/logo.jpg" alt="Vennuzo" className="public-header__logo-img" />
            <span className="public-header__logo-text">Vennuzo</span>
          </Link>
          <nav className="public-header__nav">
            <Link to="/events" className="public-header__link">Events</Link>
            <Link to="/studio" className="public-header__link">Create event</Link>
            <Link to="/studio" className="public-header__cta">Sign in</Link>
          </nav>
        </div>
      </header>
      <main className="public-main">
        <Outlet />
      </main>
      <footer className="public-footer">
        <div className="public-footer__inner">
          <div className="public-footer__brand">
            <img src="/logo.jpg" alt="Vennuzo" className="public-footer__logo-img" />
            <p>Discover, book, and share events.</p>
          </div>
          <div className="public-footer__links">
            <Link to="/events">Events</Link>
            <Link to="/studio">For organizers</Link>
            <a href="https://vennuzo-pages.web.app/support.html" target="_blank" rel="noopener noreferrer">Support</a>
            <a href="https://vennuzo-pages.web.app/privacy-policy.html" target="_blank" rel="noopener noreferrer">Privacy</a>
          </div>
          <p className="public-footer__copy">&copy; 2026 Vennuzo</p>
        </div>
      </footer>
    </div>
  )
}
