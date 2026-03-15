import { titleCaseStatus } from '../lib/formatters'
import { usePortalSession } from '../lib/portalSession'

export function SettingsPage() {
  const session = usePortalSession()

  return (
    <div className="dashboard-stack">
      <section className="hero-card hero-card--compact">
        <div>
          <p className="eyebrow">Settings</p>
          <h2>Organizer identity, review state, and payout details at a glance.</h2>
        </div>
      </section>

      <section className="settings-grid">
        <article className="panel">
          <div className="panel__header">
            <div>
              <p className="eyebrow">Account</p>
              <h3>Portal identity</h3>
            </div>
          </div>
          <dl className="settings-list">
            <div>
              <dt>Name</dt>
              <dd>{session.profile?.displayName || 'Not set'}</dd>
            </div>
            <div>
              <dt>Email</dt>
              <dd>{session.profile?.email || 'Not set'}</dd>
            </div>
            <div>
              <dt>Phone</dt>
              <dd>{session.profile?.phone || 'Not provided'}</dd>
            </div>
            <div>
              <dt>Organizer status</dt>
              <dd>{titleCaseStatus(session.status)}</dd>
            </div>
          </dl>
        </article>

        <article className="panel">
          <div className="panel__header">
            <div>
              <p className="eyebrow">Organizer application</p>
              <h3>Review and payout summary</h3>
            </div>
          </div>
          <dl className="settings-list">
            <div>
              <dt>Organizer name</dt>
              <dd>{session.application?.organizerName || 'Not set'}</dd>
            </div>
            <div>
              <dt>Business type</dt>
              <dd>{session.application?.businessType || 'Not set'}</dd>
            </div>
            <div>
              <dt>Payout method</dt>
              <dd>{session.application?.payoutMethod || 'Not set'}</dd>
            </div>
            <div>
              <dt>Settlement preference</dt>
              <dd>{session.application?.settlementPreference || 'Not set'}</dd>
            </div>
            <div>
              <dt>Review notes</dt>
              <dd>{session.application?.reviewNotes || 'No review note yet'}</dd>
            </div>
          </dl>
        </article>
      </section>
    </div>
  )
}
