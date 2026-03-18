import type { CSSProperties } from 'react'
import { titleCaseStatus } from '../lib/formatters'
import { getPayoutReadiness, getWorkspaceAccent, getWorkspaceName, getWorkspaceTagline } from '../lib/merchantWorkspace'
import { usePortalSession } from '../lib/portalSession'

export function SettingsPage() {
  const session = usePortalSession()
  const workspaceName = getWorkspaceName(session.application, session.profile)
  const workspaceTagline = getWorkspaceTagline(session.application)
  const payoutReadiness = getPayoutReadiness(session.application)
  const accentColor = getWorkspaceAccent(session.application)

  return (
    <div className="dashboard-stack">
      <section className="page-hero page-hero--settings">
        <div className="page-hero__content">
          <p className="eyebrow">Settings</p>
          <h2>Keep your workspace current.</h2>
        </div>
        <div className="page-hero__panel">
          <p className="eyebrow">Current status</p>
          <h3>{session.status === 'active' ? 'Live' : titleCaseStatus(session.status)}</h3>
          <div className={payoutReadiness.ready ? 'signal-card signal-card--ready' : 'signal-card'}>
            <strong>{payoutReadiness.label}</strong>
          </div>
        </div>
      </section>

      <section className="settings-grid">
        <article className="panel panel--feature">
          <div className="panel__header">
            <div>
              <p className="eyebrow">Workspace</p>
              <h3>Organizer identity preview</h3>
            </div>
          </div>
          <div
            className="workspace-preview-card"
            style={{ '--workspace-accent': accentColor } as CSSProperties}
          >
            <strong>{workspaceName}</strong>
            {workspaceTagline ? <p>{workspaceTagline}</p> : null}
            <small>
              {session.application?.audienceCity || 'Accra'} • {session.application?.businessType || 'Organizer workspace'}
            </small>
          </div>
        </article>

        <DetailCard
          eyebrow="Account"
          title="Portal identity"
          rows={[
            ['Name', session.profile?.displayName || 'Not set'],
            ['Email', session.profile?.email || 'Not set'],
            ['Phone', session.profile?.phone || 'Not provided'],
            ['Organizer status', session.status === 'active' ? 'Live' : titleCaseStatus(session.status)],
          ]}
        />

        <DetailCard
          eyebrow="Workspace profile"
          title="Brand and operations profile"
          rows={[
            ['Organizer name', session.application?.organizerName || 'Not set'],
            ['Business type', session.application?.businessType || 'Not set'],
            ['Audience city', session.application?.audienceCity || 'Not set'],
            ['Business address', session.application?.businessAddress || 'Not set'],
            ['Instagram', session.application?.instagram || 'Not provided'],
            ['Brand tagline', session.application?.brandTagline || 'Not set'],
          ]}
        />

        <DetailCard
          eyebrow="Payout"
          title="Settlement destination"
          rows={[
            ['Payout method', session.application?.payoutMethod || 'Not set'],
            ['Payout name', session.application?.accountName || 'Not set'],
            ['Network / bank', session.application?.network || session.application?.bankName || 'Not set'],
            [
              'Destination',
              session.application?.payoutPhone ||
                session.application?.accountNumber ||
                'Not set',
            ],
            [
              'Settlement preference',
              session.application?.settlementPreference || 'Not set',
            ],
          ]}
        />

        <DetailCard
          eyebrow="Operations"
          title="Workspace records"
          rows={[
            [
              'Registered business',
              session.application?.isRegisteredBusiness === 'yes' ? 'Yes' : 'No',
            ],
            ['TIN number', session.application?.tinNumber || 'Not provided'],
            ['Workspace note', session.application?.reviewNotes || 'No internal notes yet'],
          ]}
        />
      </section>
    </div>
  )
}

function DetailCard({
  eyebrow,
  title,
  rows,
}: {
  eyebrow: string
  title: string
  rows: Array<[string, string]>
}) {
  return (
    <article className="panel">
      <div className="panel__header">
        <div>
          <p className="eyebrow">{eyebrow}</p>
          <h3>{title}</h3>
        </div>
      </div>
      <dl className="settings-list">
        {rows.map(([label, value]) => (
          <div key={label}>
            <dt>{label}</dt>
            <dd>{value}</dd>
          </div>
        ))}
      </dl>
    </article>
  )
}
