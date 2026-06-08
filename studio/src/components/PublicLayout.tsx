import { ArrowRight, BadgeCheck, CalendarDays, CreditCard, QrCode, ShieldCheck } from 'lucide-react'
import { Link, Outlet } from 'react-router-dom'

export function PublicLayout() {
  return (
    <div className="public-shell">
      <header className="public-header">
        <div className="public-header__inner">
          <Link to="/" className="public-header__brand" aria-label="Vennuzo home">
            <img src="/logo-mark.png" alt="" className="public-header__logo-img" />
            <span className="public-header__logo-text">Vennuzo</span>
          </Link>
          <nav className="public-header__nav" aria-label="Public navigation">
            <Link to="/events" className="public-header__link">
              <CalendarDays size={15} />
              Events
            </Link>
            <Link to="/studio" className="public-header__link public-header__link--organizer">
              <QrCode size={15} />
              Sell an event
            </Link>
            <span className="public-header__signal">
              <BadgeCheck size={14} />
              Secure checkout
            </span>
            <Link to="/studio" className="public-header__cta">
              Start selling
              <ArrowRight size={15} />
            </Link>
          </nav>
        </div>
      </header>
      <main className="public-main">
        <Outlet />
      </main>
      <footer className="public-footer">
        <div className="public-footer__inner">
          <div className="public-footer__brand">
            <Link to="/" className="public-footer__logo">
              <img src="/logo-mark.png" alt="" className="public-footer__logo-img" />
              <span>Vennuzo</span>
            </Link>
            <p>Discover standout events, book with confidence, and give guests a smoother way in.</p>
          </div>
          <div className="public-footer__links">
            <div>
              <strong>Marketplace</strong>
              <Link to="/events">Explore events</Link>
              <Link to="/studio">Launch an event</Link>
            </div>
            <div>
              <strong>Trust</strong>
              <span><ShieldCheck size={14} /> Trusted event pages</span>
              <span><CreditCard size={14} /> Secure payments</span>
              <span><QrCode size={14} /> QR entry</span>
            </div>
            <div>
              <strong>Company</strong>
              <a href="https://vennuzo-pages.web.app/support.html" target="_blank" rel="noopener noreferrer">Support</a>
              <a href="https://vennuzo-pages.web.app/privacy-policy.html" target="_blank" rel="noopener noreferrer">Privacy</a>
            </div>
          </div>
          <p className="public-footer__copy">&copy; 2026 Vennuzo. Built for events people want to discover, book, and remember.</p>
        </div>
      </footer>
    </div>
  )
}
