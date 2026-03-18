import { useEffect, useMemo, useState } from 'react'
import { httpsCallable } from 'firebase/functions'
import { collection, onSnapshot, type Timestamp } from 'firebase/firestore'

import { db } from '../firebaseDb'
import { functions } from '../firebaseFunctions'
import { titleCaseStatus } from '../lib/formatters'
import { createEmptyApplication } from '../lib/organizerApplication'
import { usePortalSession } from '../lib/portalSession'
import type { OrganizerApplication, OrganizerApplicationStatus } from '../lib/types'

type QueueStatus = 'submitted' | 'under_review' | 'approved' | 'rejected' | 'all'

interface ApprovalApplication extends OrganizerApplication {
  id: string
  status: OrganizerApplicationStatus
  submittedAt: Timestamp | null
  reviewedAt: Timestamp | null
  updatedAt: Timestamp | null
  createdAt: Timestamp | null
}

interface AdminConsoleUser {
  id: string
  displayName: string
  email: string
  phone: string
  role: 'admin' | 'superadmin'
  status: string
  createdAt: Timestamp | null
  createdByName: string
}

const reviewOrganizerApplication = httpsCallable<
  { applicationId: string; decision: 'under_review' | 'approved' | 'rejected'; reviewNotes: string },
  { success: boolean }
>(functions, 'reviewOrganizerApplication')

const createAdminAccount = httpsCallable<
  {
    displayName: string
    email: string
    phone?: string
    password: string
    role: 'admin' | 'superadmin'
  },
  { success: boolean; uid: string; created: boolean; role: 'admin' | 'superadmin' }
>(functions, 'createAdminAccount')

export function SuperadminApprovalsPage() {
  const session = usePortalSession()
  const [applications, setApplications] = useState<ApprovalApplication[]>([])
  const [admins, setAdmins] = useState<AdminConsoleUser[]>([])
  const [filter, setFilter] = useState<QueueStatus>('all')
  const [loading, setLoading] = useState(true)
  const [adminsLoading, setAdminsLoading] = useState(true)
  const [busyId, setBusyId] = useState('')
  const [error, setError] = useState('')
  const [notice, setNotice] = useState('')
  const [adminError, setAdminError] = useState('')
  const [adminNotice, setAdminNotice] = useState('')
  const [adminBusy, setAdminBusy] = useState(false)
  const [showAdminPassword, setShowAdminPassword] = useState(false)
  const [selectedApplicationId, setSelectedApplicationId] = useState('')
  const [reviewNoteInput, setReviewNoteInput] = useState('')
  const [adminForm, setAdminForm] = useState({
    displayName: '',
    email: '',
    phone: '',
    password: '',
    role: 'admin' as 'admin' | 'superadmin',
  })

  useEffect(() => {
    const stop = onSnapshot(
      collection(db, 'organizer_applications'),
      (snapshot) => {
        setError('')
        const nextApplications = snapshot.docs
          .map((docSnap) => {
            const data = docSnap.data()
            const normalized = createEmptyApplication({
              ...data,
              userId: String(data.userId ?? docSnap.id),
              status: (data.status as OrganizerApplicationStatus | undefined) ?? 'draft',
            })

            return {
              id: docSnap.id,
              ...normalized,
              submittedAt: (data.submittedAt as Timestamp | null | undefined) ?? null,
              reviewedAt: (data.reviewedAt as Timestamp | null | undefined) ?? null,
              updatedAt: (data.updatedAt as Timestamp | null | undefined) ?? null,
              createdAt: (data.createdAt as Timestamp | null | undefined) ?? null,
            }
          })
          .sort((left, right) => {
            const leftTime =
              left.updatedAt?.toMillis() ??
              left.submittedAt?.toMillis() ??
              left.createdAt?.toMillis() ??
              0
            const rightTime =
              right.updatedAt?.toMillis() ??
              right.submittedAt?.toMillis() ??
              right.createdAt?.toMillis() ??
              0

            return rightTime - leftTime
          })

        setApplications(nextApplications)
        setSelectedApplicationId((current) => {
          if (current && nextApplications.some((application) => application.id === current)) {
            return current
          }

          return nextApplications[0]?.id ?? ''
        })
        setReviewNoteInput((current) => {
          if (current) {
            return current
          }
          return nextApplications[0]?.reviewNotes ?? ''
        })
        setLoading(false)
      },
      () => {
        setError('Could not load organizer applications.')
        setLoading(false)
      },
    )

    return () => stop()
  }, [])

  useEffect(() => {
    const stop = onSnapshot(
      collection(db, 'admins'),
      (snapshot) => {
        setAdminError('')
        const nextAdmins = snapshot.docs
          .map((docSnap) => {
            const data = docSnap.data()
            const role: AdminConsoleUser['role'] =
              String(data.role ?? '').toLowerCase() === 'superadmin'
                ? 'superadmin'
                : 'admin'

            return {
              id: docSnap.id,
              displayName: String(data.displayName ?? 'Admin'),
              email: String(data.email ?? ''),
              phone: String(data.phone ?? ''),
              role,
              status: String(data.status ?? 'active'),
              createdAt: (data.createdAt as Timestamp | null | undefined) ?? null,
              createdByName: String(data.createdByName ?? ''),
            }
          })
          .sort((left, right) => {
            if (left.role !== right.role) {
              return left.role === 'superadmin' ? -1 : 1
            }

            const leftTime = left.createdAt?.toMillis() ?? 0
            const rightTime = right.createdAt?.toMillis() ?? 0
            return rightTime - leftTime
          })

        setAdmins(nextAdmins)
        setAdminsLoading(false)
      },
      () => {
        setAdminError('Could not load admin accounts.')
        setAdminsLoading(false)
      },
    )

    return () => stop()
  }, [])

  const filteredApplications = useMemo(
    () => applications.filter((application) => (filter === 'all' ? true : application.status === filter)),
    [applications, filter],
  )
  const selectedApplication =
    applications.find((application) => application.id === selectedApplicationId) ??
    filteredApplications[0] ??
    applications[0] ??
    null
  const superadminCount = admins.filter((admin) => admin.role === 'superadmin').length
  const activeAdminCount = admins.filter((admin) => admin.status === 'active').length

  async function handleDecision(
    applicationId: string,
    decision: 'under_review' | 'approved' | 'rejected',
  ) {
    setBusyId(applicationId)
    setError('')
    setNotice('')
    try {
      await reviewOrganizerApplication({
        applicationId,
        decision,
        reviewNotes: reviewNoteInput.trim(),
      })
      setNotice(
        decision === 'approved'
          ? 'Application approved successfully.'
          : decision === 'rejected'
            ? 'Application rejected successfully.'
            : 'Application moved into review successfully.',
      )
    } catch (caughtError) {
      setError(
        caughtError instanceof Error
          ? caughtError.message
          : 'Could not update organizer application.',
      )
    } finally {
      setBusyId('')
    }
  }

  async function handleCreateAdmin() {
    setAdminError('')
    setAdminNotice('')

    if (adminForm.displayName.trim().length < 2) {
      setAdminError('Enter the admin’s name to continue.')
      return
    }

    if (!adminForm.email.includes('@')) {
      setAdminError('Enter a valid admin email address.')
      return
    }

    if (adminForm.password.length < 8) {
      setAdminError('Use a temporary password with at least 8 characters.')
      return
    }

    setAdminBusy(true)
    try {
      const result = await createAdminAccount({
        displayName: adminForm.displayName.trim(),
        email: adminForm.email.trim(),
        phone: adminForm.phone.trim(),
        password: adminForm.password,
        role: adminForm.role,
      })

      setAdminNotice(
        result.data.created
          ? `${adminForm.displayName.trim()} can now sign in to the admin console.`
          : `${adminForm.displayName.trim()} was promoted into the admin console.`,
      )
      setAdminForm({
        displayName: '',
        email: '',
        phone: '',
        password: '',
        role: 'admin',
      })
      setShowAdminPassword(false)
    } catch (caughtError) {
      setAdminError(
        caughtError instanceof Error ? caughtError.message : 'Could not create admin account.',
      )
    } finally {
      setAdminBusy(false)
    }
  }

  return (
    <main className="status-page status-page--reference">
      <section className="status-card superadmin-card">
        <div className="status-card__header">
          <div>
            <p className="eyebrow">Superadmin</p>
            <h1>Organizer approval queue</h1>
          </div>
          <div className="status-pill status-pill--approved">Web dashboard</div>
        </div>

        <p>
          Every organizer submission from Eventora Studio lands here. Superadmins can
          move it into review, approve it, or reject it with notes.
        </p>

        {!session.isSuperAdmin ? (
          <div className="review-note">
            <strong>Read-only admin access</strong>
            <p>
              Your account can monitor the queue, but only superadmins can approve
              organizer applications or onboard more admins.
            </p>
          </div>
        ) : null}

        <div className="status-summary-grid">
          <div className="signal-card signal-card--plain">
            <span className="eyebrow">Signed in as</span>
            <strong>{session.profile?.displayName || session.user?.email || 'Superadmin'}</strong>
            <p>This is the Studio entrypoint for organizer application review.</p>
          </div>
          <div className="signal-card signal-card--ready">
            <span className="eyebrow">Queue size</span>
            <strong>{applications.length} applications</strong>
            <p>{filteredApplications.length} visible in the current filter.</p>
          </div>
          <div className="signal-card signal-card--plain">
            <span className="eyebrow">Admin access</span>
            <strong>{activeAdminCount} active admins</strong>
            <p>{superadminCount} superadmins can provision more access from here.</p>
          </div>
        </div>

        <div className="superadmin-filters">
          {(['submitted', 'under_review', 'approved', 'rejected', 'all'] as QueueStatus[]).map((option) => (
            <button
              className={filter === option ? 'is-active' : ''}
              key={option}
              onClick={() => setFilter(option)}
              type="button"
            >
              {option === 'all' ? 'All' : titleCaseStatus(option)}
            </button>
          ))}
        </div>

        {notice ? <p className="form-success">{notice}</p> : null}
        {error ? <p className="form-error">{error}</p> : null}

        {loading ? (
          <div className="page-loader page-loader--inline">Loading approval queue...</div>
        ) : filteredApplications.length === 0 ? (
          <div className="review-note">
            <strong>No organizer applications here yet</strong>
            <p>When Eventora Studio submissions arrive, this queue will populate automatically.</p>
          </div>
        ) : (
          <div className="superadmin-review-shell">
            <aside className="superadmin-review-sidebar">
              <div className="superadmin-review-sidebar__header">
                <div>
                  <span className="eyebrow">Application list</span>
                  <strong>{filteredApplications.length} in view</strong>
                </div>
                <small>Choose one application to review in full.</small>
              </div>

              <div className="superadmin-review-list">
                {filteredApplications.map((application) => {
                  const isSelected = selectedApplication?.id === application.id
                  return (
                    <button
                      className={`superadmin-review-list__item ${isSelected ? 'is-selected' : ''}`}
                      key={application.id}
                      onClick={() => {
                        setSelectedApplicationId(application.id)
                        setReviewNoteInput(application.reviewNotes)
                        setNotice('')
                        setError('')
                      }}
                      type="button"
                    >
                      <div className="superadmin-review-list__item-header">
                        <strong>{application.organizerName || 'Unnamed organizer'}</strong>
                        <span className={`status-pill status-pill--${application.status}`}>
                          {titleCaseStatus(application.status)}
                        </span>
                      </div>
                      <p>
                        {[application.contactPerson, application.email]
                          .filter(Boolean)
                          .join(' • ') || 'No contact details yet'}
                      </p>
                      <div className="superadmin-review-list__item-meta">
                        <span>{application.businessType || 'Business type not set'}</span>
                        <span>{formatTimestamp(application.submittedAt)}</span>
                      </div>
                    </button>
                  )
                })}
              </div>
            </aside>

            <section className="superadmin-review-main">
              {selectedApplication ? (
                <>
                  <article className="superadmin-detail-card">
                    <div className="superadmin-detail-card__header">
                      <div>
                        <span className="eyebrow">Selected application</span>
                        <h2>{selectedApplication.organizerName || 'Unnamed organizer'}</h2>
                        <p>
                          {[
                            selectedApplication.contactPerson,
                            selectedApplication.email,
                            selectedApplication.phone,
                          ]
                            .filter(Boolean)
                            .join(' • ') || 'No contact details yet'}
                        </p>
                      </div>
                      <div className={`status-pill status-pill--${selectedApplication.status}`}>
                        {titleCaseStatus(selectedApplication.status)}
                      </div>
                    </div>

                    <div className="superadmin-detail-hero">
                      <div className="superadmin-detail-hero__summary">
                        <span>Business type</span>
                        <strong>{selectedApplication.businessType || 'Not set'}</strong>
                      </div>
                      <div className="superadmin-detail-hero__summary">
                        <span>Settlement</span>
                        <strong>{selectedApplication.settlementPreference || 'Not set'}</strong>
                      </div>
                      <div className="superadmin-detail-hero__summary">
                        <span>Submitted</span>
                        <strong>{formatTimestamp(selectedApplication.submittedAt)}</strong>
                      </div>
                    </div>

                    <div className="superadmin-detail-grid">
                      <section className="summary-card">
                        <h3>Organizer profile</h3>
                        <dl>
                          <DetailRow label="Organizer name" value={selectedApplication.organizerName} />
                          <DetailRow label="Contact person" value={selectedApplication.contactPerson} />
                          <DetailRow label="Business type" value={selectedApplication.businessType} />
                          <DetailRow label="Audience city" value={selectedApplication.audienceCity} />
                          <DetailRow label="Business address" value={selectedApplication.businessAddress} />
                          <DetailRow label="Instagram" value={selectedApplication.instagram} />
                          <DetailRow label="Brand tagline" value={selectedApplication.brandTagline} />
                          <DetailRow label="Accent color" value={selectedApplication.brandAccentColor} />
                        </dl>
                      </section>

                      <section className="summary-card">
                        <h3>Verification details</h3>
                        <dl>
                          <DetailRow
                            label="Registered business"
                            value={selectedApplication.isRegisteredBusiness === 'yes' ? 'Yes' : 'No'}
                          />
                          <DetailRow
                            label="Registration number"
                            value={selectedApplication.businessRegistrationNumber}
                          />
                          <DetailRow label="TIN number" value={selectedApplication.tinNumber} />
                          <DetailRow label="Review notes" value={selectedApplication.reviewNotes} />
                          <DetailLink
                            label="Logo upload"
                            url={selectedApplication.logoImageUrl}
                            fallback={selectedApplication.logoFileName}
                          />
                          <DetailLink
                            label="Government ID"
                            url={selectedApplication.governmentIdUrl}
                            fallback={selectedApplication.governmentIdFileName}
                          />
                          <DetailLink
                            label="Selfie"
                            url={selectedApplication.selfieUrl}
                            fallback={selectedApplication.selfieFileName}
                          />
                        </dl>
                      </section>

                      <section className="summary-card">
                        <h3>Payout setup</h3>
                        <dl>
                          <DetailRow label="Settlement preference" value={selectedApplication.settlementPreference} />
                          <DetailRow label="Payout method" value={selectedApplication.payoutMethod} />
                          <DetailRow label="Payout name" value={selectedApplication.accountName} />
                          <DetailRow label="Bank name" value={selectedApplication.bankName} />
                          <DetailRow label="Account number" value={selectedApplication.accountNumber} />
                          <DetailRow label="Network" value={selectedApplication.network} />
                          <DetailRow label="Payout phone" value={selectedApplication.payoutPhone} />
                        </dl>
                      </section>

                      <section className="summary-card">
                        <h3>Application record</h3>
                        <dl>
                          <DetailRow label="Application ID" value={selectedApplication.id} />
                          <DetailRow label="User ID" value={selectedApplication.userId} />
                          <DetailRow label="Organization ID" value={selectedApplication.organizationId} />
                          <DetailRow label="Submitted" value={formatTimestamp(selectedApplication.submittedAt)} />
                          <DetailRow label="Reviewed" value={formatTimestamp(selectedApplication.reviewedAt)} />
                          <DetailRow
                            label="Payout terms accepted"
                            value={selectedApplication.agreedToPayoutTerms ? 'Yes' : 'No'}
                          />
                          <DetailRow
                            label="Compliance confirmed"
                            value={selectedApplication.agreesToCompliance ? 'Yes' : 'No'}
                          />
                        </dl>
                      </section>
                    </div>
                  </article>

                  <section className="summary-card superadmin-action-card">
                    <div className="superadmin-action-card__header">
                      <div>
                        <span className="eyebrow">Review action</span>
                        <h3>Decision and reviewer note</h3>
                      </div>
                      <small>
                        Status updates and reviewer notes are saved back to the organizer record.
                      </small>
                    </div>
                    <label className="field field--wide">
                      <span>Review note</span>
                      <textarea
                        onChange={(event) => setReviewNoteInput(event.target.value)}
                        placeholder="Add a note for the organizer or your internal review trail"
                        rows={5}
                        value={reviewNoteInput}
                      />
                    </label>
                    <div className="hero-actions">
                      <button
                        className="button button--secondary"
                        disabled={busyId === selectedApplication.id || !session.isSuperAdmin}
                        onClick={() => handleDecision(selectedApplication.id, 'under_review')}
                        type="button"
                      >
                        {busyId === selectedApplication.id ? 'Working...' : 'Mark under review'}
                      </button>
                      <button
                        className="button button--primary"
                        disabled={busyId === selectedApplication.id || !session.isSuperAdmin}
                        onClick={() => handleDecision(selectedApplication.id, 'approved')}
                        type="button"
                      >
                        {busyId === selectedApplication.id ? 'Working...' : 'Approve application'}
                      </button>
                      <button
                        className="button button--ghost"
                        disabled={busyId === selectedApplication.id || !session.isSuperAdmin}
                        onClick={() => handleDecision(selectedApplication.id, 'rejected')}
                        type="button"
                      >
                        Reject application
                      </button>
                    </div>
                  </section>
                </>
              ) : (
                <div className="review-note">
                  <strong>Select an application</strong>
                  <p>Choose an organizer from the queue to open the full review workspace.</p>
                </div>
              )}
            </section>
          </div>
        )}
      </section>

      <section className="status-card superadmin-card">
        <div className="status-card__header">
          <div>
            <p className="eyebrow">Admin Management</p>
            <h1>Onboard another admin</h1>
          </div>
          <div className="status-pill status-pill--approved">Superadmin only</div>
        </div>

        <p>
          Create admin credentials from inside the console. This provisions Firebase Auth
          access and registers the user in the Eventora admin directory.
        </p>

        <div className="superadmin-admin-grid">
          <article className="superadmin-admin-card">
            <strong>Create admin account</strong>
            {session.isSuperAdmin ? (
              <>
                <div className="auth-form auth-form--reference superadmin-admin-form">
                  <label className="field">
                    <span>Full Name *</span>
                    <input
                      onChange={(event) =>
                        setAdminForm((current) => ({
                          ...current,
                          displayName: event.target.value,
                        }))
                      }
                      placeholder="e.g. Ama Owusu"
                      value={adminForm.displayName}
                    />
                  </label>

                  <label className="field">
                    <span>Email Address *</span>
                    <input
                      onChange={(event) =>
                        setAdminForm((current) => ({
                          ...current,
                          email: event.target.value,
                        }))
                      }
                      placeholder="admin@eventora.com"
                      type="email"
                      value={adminForm.email}
                    />
                  </label>

                  <label className="field">
                    <span>Phone Number</span>
                    <input
                      onChange={(event) =>
                        setAdminForm((current) => ({
                          ...current,
                          phone: event.target.value,
                        }))
                      }
                      placeholder="024 123 4567"
                      value={adminForm.phone}
                    />
                  </label>

                  <label className="field">
                    <span>Admin Role *</span>
                    <select
                      onChange={(event) =>
                        setAdminForm((current) => ({
                          ...current,
                          role: event.target.value === 'superadmin' ? 'superadmin' : 'admin',
                        }))
                      }
                      value={adminForm.role}
                    >
                      <option value="admin">Admin</option>
                      <option value="superadmin">Superadmin</option>
                    </select>
                    <small>Only superadmins can create or approve other admins.</small>
                  </label>

                  <label className="field">
                    <span>Temporary Password *</span>
                    <div className="password-field">
                      <input
                        onChange={(event) =>
                          setAdminForm((current) => ({
                            ...current,
                            password: event.target.value,
                          }))
                        }
                        placeholder="Create a temporary password"
                        type={showAdminPassword ? 'text' : 'password'}
                        value={adminForm.password}
                      />
                      <button
                        className="password-toggle"
                        onClick={() => setShowAdminPassword((current) => !current)}
                        type="button"
                      >
                        {showAdminPassword ? 'Hide' : 'Show'}
                      </button>
                    </div>
                    <small>Share this securely. The admin can change it later.</small>
                  </label>
                </div>

                {adminError ? <p className="form-error">{adminError}</p> : null}
                {adminNotice ? <p className="form-success">{adminNotice}</p> : null}

                <div className="hero-actions">
                  <button
                    className="button button--primary"
                    disabled={adminBusy}
                    onClick={handleCreateAdmin}
                    type="button"
                  >
                    {adminBusy ? 'Creating admin...' : 'Create admin account'}
                  </button>
                </div>
              </>
            ) : (
              <div className="review-note">
                <strong>Superadmin access required</strong>
                <p>
                  Standard admins can view the directory, but only superadmins can create
                  new admin accounts or assign superadmin access.
                </p>
              </div>
            )}
          </article>

          <article className="superadmin-admin-card">
            <strong>Current admin directory</strong>
            <p className="superadmin-admin-card__intro">
              Everyone who can access the Eventora admin console is listed here.
            </p>

            {adminsLoading ? (
              <div className="page-loader page-loader--inline">Loading admin directory...</div>
            ) : admins.length === 0 ? (
              <div className="review-note">
                <strong>No admins found yet</strong>
                <p>Your first admin accounts will appear here after they are created.</p>
              </div>
            ) : (
              <div className="superadmin-admin-list">
                {admins.map((admin) => (
                  <article className="superadmin-admin-list__item" key={admin.id}>
                    <div>
                      <strong>{admin.displayName || admin.email}</strong>
                      <p>{[admin.email, admin.phone].filter(Boolean).join(' • ')}</p>
                    </div>
                    <div className="superadmin-admin-list__meta">
                      <span className={`status-pill status-pill--${admin.role === 'superadmin' ? 'approved' : 'submitted'}`}>
                        {admin.role === 'superadmin' ? 'Superadmin' : 'Admin'}
                      </span>
                      <small>
                        Added {formatTimestamp(admin.createdAt)}
                        {admin.createdByName ? ` by ${admin.createdByName}` : ''}
                      </small>
                    </div>
                  </article>
                ))}
              </div>
            )}
          </article>
        </div>
      </section>
    </main>
  )
}

function formatTimestamp(value: Timestamp | null) {
  if (!value) {
    return 'No timestamp yet'
  }

  return value.toDate().toLocaleString('en-US', {
    dateStyle: 'medium',
    timeStyle: 'short',
  })
}

function DetailRow({ label, value }: { label: string; value: string }) {
  return (
    <div>
      <dt>{label}</dt>
      <dd>{value || 'Not provided'}</dd>
    </div>
  )
}

function DetailLink({
  label,
  url,
  fallback,
}: {
  label: string
  url: string
  fallback: string
}) {
  return (
    <div>
      <dt>{label}</dt>
      <dd>
        {url ? (
          <a className="text-link" href={url} rel="noreferrer" target="_blank">
            Open file
          </a>
        ) : (
          fallback || 'Not uploaded'
        )}
      </dd>
    </div>
  )
}
