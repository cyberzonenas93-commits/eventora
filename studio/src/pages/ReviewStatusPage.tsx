import { Link, Navigate } from 'react-router-dom'

import { titleCaseStatus } from '../lib/formatters'
import { usePortalSession } from '../lib/portalSession'

export function ReviewStatusPage() {
  const session = usePortalSession()

  if (!session.user) {
    return <Navigate replace to="/" />
  }

  if (session.status === 'approved') {
    return <Navigate replace to="/overview" />
  }

  if (!session.application) {
    return <Navigate replace to="/setup/account" />
  }

  const isRejected = session.status === 'rejected'

  return (
    <main className="status-page">
      <section className="status-card">
        <p className="eyebrow">Eventora Studio</p>
        <h1>
          {isRejected
            ? 'Your organizer application needs updates'
            : 'Your organizer application is with the Eventora team'}
        </h1>
        <p>
          Current status: <strong>{titleCaseStatus(session.status)}</strong>
        </p>
        <p>
          {isRejected
            ? 'Update your profile, fix the flagged details, and resubmit when ready.'
            : 'A superadmin is reviewing your verification and payout setup before organizer publishing is unlocked.'}
        </p>

        {session.application.reviewNotes ? (
          <div className="review-note">
            <strong>Review note</strong>
            <p>{session.application.reviewNotes}</p>
          </div>
        ) : null}

        <div className="status-actions">
          <Link className="button button--primary" to={isRejected ? '/setup/account' : '/'}>
            {isRejected ? 'Update application' : 'Back to studio home'}
          </Link>
        </div>
      </section>
    </main>
  )
}
