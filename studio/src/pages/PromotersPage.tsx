import { Link } from 'react-router-dom'

export function PromotersPage() {
  return (
    <div className="dashboard-stack">
      <section className="page-hero page-hero--events">
        <div className="page-hero__content">
          <p className="eyebrow">Partners</p>
          <h2>Partners and referrals</h2>
          <div className="hero-chip-row">
            <span>Coming soon</span>
          </div>
        </div>
        <div className="page-hero__panel">
          <Link className="button button--secondary" to="/studio/overview">
            Back to overview
          </Link>
        </div>
      </section>

      <section className="content-grid">
        <article className="panel">
          <div className="panel__header">
            <div>
              <p className="eyebrow">Partners &amp; referrals</p>
              <h3>Partner and referral programs</h3>
            </div>
          </div>
          <div className="empty-card">
            <h4>Coming soon</h4>
            <p>
              Partner and referral programs will be available here. You&apos;ll be able to invite partners and track referral performance.
            </p>
          </div>
        </article>
      </section>
    </div>
  )
}
