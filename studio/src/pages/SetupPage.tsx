import { useEffect, useMemo, useState, type CSSProperties } from 'react'
import { Navigate, useNavigate, useParams } from 'react-router-dom'

import { copy } from '../lib/copy'
import { getErrorMessage } from '../lib/errorMessages'
import { createEmptyApplication, setupSteps } from '../lib/organizerApplication'
import { getPayoutReadiness } from '../lib/merchantWorkspace'
import { usePortalSession } from '../lib/portalSession'
import { saveOrganizerApplicationDraft, uploadApplicationFile } from '../lib/portalData'
import type { OrganizerApplication } from '../lib/types'

const stepCopy = {
  account: {
    eyebrow: 'Workspace',
    title: 'Set up your organizer profile',
  },
  payout: {
    eyebrow: 'Payouts',
    title: 'Choose your payout destination',
  },
  launch: {
    eyebrow: 'Launch',
    title: 'Save and launch',
  },
} as const

export function SetupPage() {
  const { step = 'account' } = useParams()
  const navigate = useNavigate()
  const session = usePortalSession()
  const [form, setForm] = useState<OrganizerApplication>(
    createEmptyApplication({
      ...session.application,
      userId: session.user?.uid || '',
      organizationId: session.organizationId || `org_${session.user?.uid || ''}`,
      organizerName: session.application?.organizerName || session.profile?.displayName || '',
      contactPerson: session.application?.contactPerson || session.profile?.displayName || '',
      email: session.application?.email || session.profile?.email || '',
      phone: session.application?.phone || session.profile?.phone || '',
    }),
  )
  const [error, setError] = useState('')
  const [message, setMessage] = useState('')
  const [isSaving, setIsSaving] = useState(false)
  const [uploadingField, setUploadingField] = useState('')

  useEffect(() => {
    setForm(
      createEmptyApplication({
        ...session.application,
        userId: session.user?.uid || '',
        organizationId: session.organizationId || `org_${session.user?.uid || ''}`,
        organizerName: session.application?.organizerName || session.profile?.displayName || '',
        contactPerson: session.application?.contactPerson || session.profile?.displayName || '',
        email: session.application?.email || session.profile?.email || '',
        phone: session.application?.phone || session.profile?.phone || '',
      }),
    )
  }, [session.application, session.organizationId, session.profile, session.user])

  const currentIndex = setupSteps.indexOf(step as (typeof setupSteps)[number])
  const safeStep = currentIndex === -1 ? 'account' : step
  const activeStep = stepCopy[safeStep as keyof typeof stepCopy]
  const payoutReadiness = getPayoutReadiness(form)
  const completedSteps = [
    Boolean(
      form.organizerName.trim() &&
        form.contactPerson.trim() &&
        form.email.includes('@') &&
        form.phone.trim() &&
        form.businessType.trim(),
    ),
    payoutReadiness.ready,
    Boolean(form.organizerName.trim()),
  ]
  const completionCount = completedSteps.filter(Boolean).length
  const completionPercent = Math.round((completionCount / setupSteps.length) * 100)

  const stepValid = useMemo(() => {
    switch (safeStep) {
      case 'account':
        return Boolean(
          form.organizerName.trim() &&
            form.contactPerson.trim() &&
            form.email.includes('@') &&
            form.phone.trim() &&
            form.businessType.trim(),
        )
      case 'payout':
        return true
      case 'launch':
        return true
      default:
        return false
    }
  }, [form, safeStep])

  if (!session.user) {
    return <Navigate replace to="/" />
  }

  const nextStep = setupSteps[Math.min(currentIndex + 1, setupSteps.length - 1)]
  const previousStep = setupSteps[Math.max(currentIndex - 1, 0)]

  async function persistWorkspace(successMessage: string) {
    setError('')
    setMessage('')
    setIsSaving(true)
    try {
      await saveOrganizerApplicationDraft(session.user!.uid, {
        ...form,
        status: 'active',
        organizationId: session.organizationId || form.organizationId || `org_${session.user!.uid}`,
      })
      setMessage(successMessage)
      return true
    } catch (caughtError) {
      setError(getErrorMessage(caughtError, copy.setupSaveFailed))
      return false
    } finally {
      setIsSaving(false)
    }
  }

  async function handleCompleteSetup(destination: '/studio/overview' | '/studio/events/new') {
    const saved = await persistWorkspace('Workspace saved successfully.')
    if (saved) {
      navigate(destination)
    }
  }

  async function handleUpload(file: File | null) {
    if (!file || !session.user) {
      return
    }
    setUploadingField('logo')
    setError('')
    try {
      const uploaded = await uploadApplicationFile(session.user.uid, 'logo', file)
      setForm((current) => ({
        ...current,
        logoImageUrl: uploaded.downloadUrl,
        logoFileName: uploaded.fileName,
      }))
    } catch (caughtError) {
      setError(getErrorMessage(caughtError, copy.uploadFailed))
    } finally {
      setUploadingField('')
    }
  }

  return (
    <main className="setup-page setup-page--reference">
      <aside className="setup-sidebar">
        <div className="studio-brand studio-brand--stacked">
          <div className="studio-brand__mark">V</div>
          <div>
            <strong>Vennuzo Studio</strong>
            <span>Workspace setup</span>
          </div>
        </div>

        <div className="setup-sidebar__intro">
          <p className="eyebrow">Self-serve launch</p>
          <h2>Set up your workspace, then create events right away.</h2>
        </div>

        <div className="setup-progress-card">
          <div className="setup-progress-card__header">
            <div>
              <span className="eyebrow">Completion</span>
              <strong>{completionPercent}% ready</strong>
            </div>
            <small>
              {completionCount} of {setupSteps.length} sections complete
            </small>
          </div>
          <div className="setup-progress-bar">
            <span style={{ width: `${completionPercent}%` }} />
          </div>
        </div>

        <ol className="setup-steps">
          {setupSteps.map((item, index) => (
            <li
              className={item === safeStep ? 'is-active' : index < currentIndex ? 'is-complete' : ''}
              key={item}
            >
              <span>{index + 1}</span>
              <div>
                <strong>{item.replace(/^\w/, (letter) => letter.toUpperCase())}</strong>
              </div>
            </li>
          ))}
        </ol>

        <div className="setup-summary-card">
          <span className="eyebrow">Workspace status</span>
          <h3>Live</h3>
        </div>
      </aside>

      <section className="setup-main">
        <header className="setup-hero">
          <div className="setup-hero__content">
            <p className="eyebrow">
              {activeStep.eyebrow} • Step {currentIndex + 1}
            </p>
            <h1>{activeStep.title}</h1>
            <div className="hero-chip-row hero-chip-row--compact">
              <span>Live workspace</span>
            </div>
          </div>
          <div className="setup-hero__panel">
            <div className="setup-hero__metric">
              <span>Workspace</span>
              <strong>Live</strong>
            </div>
            <div className="setup-hero__metric">
              <span>Current step</span>
              <strong>{currentIndex + 1} / {setupSteps.length}</strong>
            </div>
            <div className="setup-hero__metric">
              <span>Payout status</span>
              <strong>{payoutReadiness.ready ? 'Ready' : 'Optional'}</strong>
            </div>
          </div>
        </header>

        <div className="setup-main-grid">
          <div className="setup-card">
            {safeStep === 'account' ? (
              <div className="form-grid">
                <Field
                  label="Organizer name"
                  value={form.organizerName}
                  onChange={(value) => setForm((current) => ({ ...current, organizerName: value }))}
                />
                <Field
                  label="Contact person"
                  value={form.contactPerson}
                  onChange={(value) => setForm((current) => ({ ...current, contactPerson: value }))}
                />
                <Field
                  label="Email"
                  type="email"
                  value={form.email}
                  onChange={(value) => setForm((current) => ({ ...current, email: value }))}
                />
                <Field
                  label="Phone"
                  value={form.phone}
                  onChange={(value) => setForm((current) => ({ ...current, phone: value }))}
                />
                <SelectField
                  label="Business type"
                  value={form.businessType}
                  options={[
                    { label: 'Select business type', value: '' },
                    { label: 'Event Organizer', value: 'Event Organizer' },
                    { label: 'Festival', value: 'Festival' },
                    { label: 'Venue', value: 'Venue' },
                    { label: 'Community', value: 'Community' },
                    { label: 'Nightlife Brand', value: 'Nightlife Brand' },
                    { label: 'Events partner', value: 'Events partner' },
                    { label: 'Creative Collective', value: 'Creative Collective' },
                  ]}
                  onChange={(value) => setForm((current) => ({ ...current, businessType: value }))}
                />
                <Field
                  label="Audience city"
                  value={form.audienceCity}
                  onChange={(value) => setForm((current) => ({ ...current, audienceCity: value }))}
                  placeholder="Accra"
                />
                <Field
                  label="Instagram"
                  value={form.instagram}
                  onChange={(value) => setForm((current) => ({ ...current, instagram: value }))}
                  placeholder="@vennuzo"
                />
                <Field
                  label="Brand tagline"
                  value={form.brandTagline}
                  onChange={(value) => setForm((current) => ({ ...current, brandTagline: value }))}
                  placeholder="Curating unforgettable nights for the city"
                  wide
                />
                <ColorField
                  label="Accent color"
                  value={form.brandAccentColor}
                  onChange={(value) => setForm((current) => ({ ...current, brandAccentColor: value }))}
                />
                <Field
                  label="Business address"
                  value={form.businessAddress}
                  onChange={(value) => setForm((current) => ({ ...current, businessAddress: value }))}
                  wide
                />
                <SelectField
                  label="Registered business?"
                  value={form.isRegisteredBusiness}
                  options={[
                    { label: 'No', value: 'no' },
                    { label: 'Yes', value: 'yes' },
                  ]}
                  onChange={(value) =>
                    setForm((current) => ({ ...current, isRegisteredBusiness: value as 'yes' | 'no' }))
                  }
                />
                {form.isRegisteredBusiness === 'yes' ? (
                  <>
                    <Field
                      label="Business registration number"
                      value={form.businessRegistrationNumber}
                      onChange={(value) =>
                        setForm((current) => ({ ...current, businessRegistrationNumber: value }))
                      }
                    />
                    <Field
                      label="TIN number"
                      value={form.tinNumber}
                      onChange={(value) => setForm((current) => ({ ...current, tinNumber: value }))}
                    />
                  </>
                ) : null}
                <FileField
                  label="Logo or organizer mark"
                  fileName={form.logoFileName}
                  helper={uploadingField === 'logo' ? 'Uploading...' : 'PNG or JPG'}
                  onChange={handleUpload}
                />
              </div>
            ) : null}

            {safeStep === 'payout' ? (
              <div className="form-grid">
                <SelectField
                  label="Payout method"
                  value={form.payoutMethod}
                  options={[
                    { label: 'Mobile money', value: 'mobile-money' },
                    { label: 'Bank transfer', value: 'bank-transfer' },
                  ]}
                  onChange={(value) =>
                    setForm((current) => ({
                      ...current,
                      payoutMethod: value as 'mobile-money' | 'bank-transfer',
                    }))
                  }
                />
                {form.payoutMethod === 'mobile-money' ? (
                  <>
                    <SelectField
                      label="Network"
                      value={form.network}
                      options={[
                        { label: 'Select network', value: '' },
                        { label: 'MTN Mobile Money', value: 'MTN Mobile Money' },
                        { label: 'Telecel Cash', value: 'Telecel Cash' },
                        { label: 'AirtelTigo Money', value: 'AirtelTigo Money' },
                      ]}
                      onChange={(value) => setForm((current) => ({ ...current, network: value }))}
                    />
                    <Field
                      label="Payout name"
                      value={form.accountName}
                      onChange={(value) => setForm((current) => ({ ...current, accountName: value }))}
                      placeholder="Full name on the wallet"
                    />
                    <Field
                      label="Payout phone"
                      value={form.payoutPhone}
                      onChange={(value) => setForm((current) => ({ ...current, payoutPhone: value }))}
                    />
                  </>
                ) : (
                  <>
                    <Field
                      label="Bank name"
                      value={form.bankName}
                      onChange={(value) => setForm((current) => ({ ...current, bankName: value }))}
                    />
                    <Field
                      label="Payout name"
                      value={form.accountName}
                      onChange={(value) => setForm((current) => ({ ...current, accountName: value }))}
                    />
                    <Field
                      label="Account number"
                      value={form.accountNumber}
                      onChange={(value) =>
                        setForm((current) => ({ ...current, accountNumber: value }))
                      }
                    />
                  </>
                )}
                <Field
                  label="Settlement preference"
                  value={form.settlementPreference}
                  onChange={(value) =>
                    setForm((current) => ({ ...current, settlementPreference: value }))
                  }
                  wide
                />
                <CheckboxField
                  checked={form.agreedToPayoutTerms}
                  label="I confirm these payout details are ready for live ticket sales."
                  onChange={(checked) =>
                    setForm((current) => ({ ...current, agreedToPayoutTerms: checked }))
                  }
                  wide
                />
              </div>
            ) : null}

            {safeStep === 'launch' ? (
              <div className="review-grid">
                <SummaryCard
                  title="Organizer identity"
                  rows={[
                    ['Organizer', form.organizerName || 'Not set'],
                    ['Contact', form.contactPerson || 'Not set'],
                    ['Email', form.email || 'Not set'],
                    ['Phone', form.phone || 'Not set'],
                    ['Business type', form.businessType || 'Not set'],
                    ['Audience city', form.audienceCity || 'Not set'],
                    ['Tagline', form.brandTagline || 'Not set'],
                  ]}
                />
                <SummaryCard
                  title="Payout profile"
                  rows={[
                    ['Method', form.payoutMethod],
                    ['Payout name', form.accountName || 'Not set'],
                    [
                      'Destination',
                      form.payoutMethod === 'mobile-money'
                        ? `${form.network || 'Network pending'} • ${form.payoutPhone || 'Phone pending'}`
                        : `${form.bankName || 'Bank pending'} • ${form.accountNumber || 'Account pending'}`,
                    ],
                    ['Settlement', form.settlementPreference || 'Not set'],
                  ]}
                />
                <SummaryCard
                  title="Next move"
                  rows={[
                    ['Workspace', 'Live'],
                    ['Logo', form.logoFileName || 'Optional'],
                    ['Payout readiness', payoutReadiness.label],
                    ['Recommended action', 'Create your first event'],
                  ]}
                />
              </div>
            ) : null}

            {error ? <p className="form-error">{error}</p> : null}
            {message ? <p className="form-success">{message}</p> : null}

            <div className="setup-actions">
              <button
                className="button button--ghost"
                disabled={isSaving || currentIndex <= 0}
                onClick={() => navigate(`/studio/setup/${previousStep}`)}
                type="button"
              >
                Back
              </button>
              <div className="setup-actions__right">
                <button
                  className="button button--secondary"
                  disabled={isSaving}
                  onClick={() => void persistWorkspace('Workspace saved successfully.')}
                  type="button"
                >
                  {isSaving ? 'Saving...' : 'Save workspace'}
                </button>
                {safeStep === 'launch' ? (
                  <>
                    <button
                      className="button button--secondary"
                      disabled={isSaving}
                      onClick={() => void handleCompleteSetup('/studio/overview')}
                      type="button"
                    >
                      Open dashboard
                    </button>
                    <button
                      className="button button--primary"
                      disabled={isSaving}
                      onClick={() => void handleCompleteSetup('/studio/events/new')}
                      type="button"
                    >
                      Create first event
                    </button>
                  </>
                ) : (
                  <button
                    className="button button--primary"
                    disabled={!stepValid}
                    onClick={() => navigate(`/studio/setup/${nextStep}`)}
                    type="button"
                  >
                    Continue
                  </button>
                )}
              </div>
            </div>
          </div>

          <aside className="setup-side-panel">
            <div className="setup-side-panel__card">
              <span className="eyebrow">Step outcome</span>
              <h3>{activeStep.title}</h3>
              <p>
                {safeStep === 'account'
                  ? 'Your brand details will show across Studio and event pages.'
                  : safeStep === 'payout'
                    ? 'Set where payouts should land.'
                    : 'Save and move into Studio.'}
              </p>
            </div>
            <div className="setup-side-panel__card">
              <span className="eyebrow">Ready now</span>
              <ul className="setup-check-list">
                {setupSteps.map((item, index) => (
                  <li className={completedSteps[index] ? 'is-complete' : 'is-pending'} key={item}>
                    <strong>{item.replace(/^\w/, (letter) => letter.toUpperCase())}</strong>
                    <span>{completedSteps[index] ? 'Done' : 'Pending'}</span>
                  </li>
                ))}
              </ul>
            </div>
            <div className="setup-side-panel__card">
              <span className="eyebrow">Workspace preview</span>
              <div
                className="workspace-preview-card"
                style={{ '--workspace-accent': form.brandAccentColor || '#f26b3d' } as CSSProperties}
              >
                <strong>{form.organizerName || 'Your organizer brand'}</strong>
                <p>{form.brandTagline || 'Add a short tagline.'}</p>
                <small>
                  {form.audienceCity || 'Accra'} • {form.businessType || 'Event organizer'}
                </small>
              </div>
            </div>
            <div className="setup-side-panel__card">
              <span className="eyebrow">Payout health</span>
              <div className={payoutReadiness.ready ? 'signal-card signal-card--ready' : 'signal-card'}>
                <strong>{payoutReadiness.label}</strong>
                <p>{payoutReadiness.detail}</p>
              </div>
            </div>
          </aside>
        </div>
      </section>
    </main>
  )
}

function Field({
  label,
  value,
  onChange,
  placeholder,
  type = 'text',
  wide = false,
}: {
  label: string
  value: string
  onChange: (value: string) => void
  placeholder?: string
  type?: string
  wide?: boolean
}) {
  return (
    <label className={wide ? 'field field--wide' : 'field'}>
      <span>{label}</span>
      <input onChange={(event) => onChange(event.target.value)} placeholder={placeholder} type={type} value={value} />
    </label>
  )
}

function ColorField({
  label,
  value,
  onChange,
}: {
  label: string
  value: string
  onChange: (value: string) => void
}) {
  return (
    <label className="field field--color">
      <span>{label}</span>
      <div className="color-field">
        <input onChange={(event) => onChange(event.target.value)} type="color" value={value} />
        <input onChange={(event) => onChange(event.target.value)} type="text" value={value} />
      </div>
    </label>
  )
}

function SelectField({
  label,
  value,
  options,
  onChange,
}: {
  label: string
  value: string
  options: Array<{ label: string; value: string }>
  onChange: (value: string) => void
}) {
  return (
    <label className="field">
      <span>{label}</span>
      <select onChange={(event) => onChange(event.target.value)} value={value}>
        {options.map((option) => (
          <option key={option.value} value={option.value}>
            {option.label}
          </option>
        ))}
      </select>
    </label>
  )
}

function FileField({
  label,
  fileName,
  helper,
  onChange,
}: {
  label: string
  fileName: string
  helper: string
  onChange: (file: File | null) => void
}) {
  return (
    <label className="field field--wide">
      <span>{label}</span>
      <input onChange={(event) => onChange(event.target.files?.[0] ?? null)} type="file" />
      <small>{fileName || helper}</small>
    </label>
  )
}

function CheckboxField({
  label,
  checked,
  onChange,
  wide = false,
}: {
  label: string
  checked: boolean
  onChange: (checked: boolean) => void
  wide?: boolean
}) {
  return (
    <label className={wide ? 'checkbox checkbox--wide' : 'checkbox'}>
      <input checked={checked} onChange={(event) => onChange(event.target.checked)} type="checkbox" />
      <span>{label}</span>
    </label>
  )
}

function SummaryCard({ title, rows }: { title: string; rows: Array<[string, string]> }) {
  return (
    <article className="summary-card">
      <strong>{title}</strong>
      <dl>
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
