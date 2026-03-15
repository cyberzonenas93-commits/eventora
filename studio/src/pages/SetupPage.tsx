import { useEffect, useMemo, useState } from 'react'
import { Navigate, useNavigate, useParams } from 'react-router-dom'

import {
  createEmptyApplication,
  saveOrganizerApplicationDraft,
  setupSteps,
  submitOrganizerApplication,
  uploadApplicationFile,
} from '../lib/portalData'
import { usePortalSession } from '../lib/portalSession'
import type { OrganizerApplication } from '../lib/types'

export function SetupPage() {
  const { step = 'account' } = useParams()
  const navigate = useNavigate()
  const session = usePortalSession()
  const [form, setForm] = useState<OrganizerApplication>(
    createEmptyApplication({
      userId: session.user?.uid || '',
      contactPerson: session.profile?.displayName || '',
      email: session.profile?.email || '',
      phone: session.profile?.phone || '',
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
        contactPerson:
          session.application?.contactPerson || session.profile?.displayName || '',
        email: session.application?.email || session.profile?.email || '',
        phone: session.application?.phone || session.profile?.phone || '',
      }),
    )
  }, [session.application, session.profile, session.user])

  const currentIndex = setupSteps.indexOf(step as (typeof setupSteps)[number])
  const safeStep = currentIndex === -1 ? 'account' : step

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
      case 'verification':
        return Boolean(
          form.governmentIdFileName.trim() &&
            (form.isRegisteredBusiness === 'no' ||
              form.businessRegistrationNumber.trim()),
        )
      case 'payout':
        return form.payoutMethod === 'mobile-money'
          ? Boolean(
              form.network.trim() &&
                form.payoutPhone.trim() &&
                form.settlementPreference.trim() &&
                form.agreedToPayoutTerms,
            )
          : Boolean(
              form.bankName.trim() &&
                form.accountName.trim() &&
                form.accountNumber.trim() &&
                form.settlementPreference.trim() &&
                form.agreedToPayoutTerms,
            )
      case 'review':
        return form.agreesToCompliance
      default:
        return false
    }
  }, [form, safeStep])

  if (!session.user) {
    return <Navigate replace to="/" />
  }

  if (session.status === 'approved') {
    return <Navigate replace to="/overview" />
  }

  const nextStep = setupSteps[Math.min(currentIndex + 1, setupSteps.length - 1)]
  const previousStep = setupSteps[Math.max(currentIndex - 1, 0)]

  async function handleSaveDraft() {
    setError('')
    setMessage('')
    setIsSaving(true)
    try {
      await saveOrganizerApplicationDraft(session.user!.uid, form)
      setMessage('Draft saved to Eventora Studio.')
    } catch (caughtError) {
      setError(
        caughtError instanceof Error
          ? caughtError.message
          : 'Could not save organizer draft.',
      )
    } finally {
      setIsSaving(false)
    }
  }

  async function handleSubmit() {
    setError('')
    setMessage('')
    setIsSaving(true)
    try {
      await submitOrganizerApplication(session.user!.uid, {
        ...form,
        status: 'submitted',
      })
      navigate('/review')
    } catch (caughtError) {
      setError(
        caughtError instanceof Error
          ? caughtError.message
          : 'Could not submit organizer application.',
      )
    } finally {
      setIsSaving(false)
    }
  }

  async function handleUpload(
    kind: 'logo' | 'government-id' | 'selfie',
    file: File | null,
  ) {
    if (!file || !session.user) {
      return
    }
    setUploadingField(kind)
    setError('')
    try {
      const uploaded = await uploadApplicationFile(session.user.uid, kind, file)
      setForm((current) => ({
        ...current,
        ...(kind === 'logo'
          ? { logoImageUrl: uploaded.downloadUrl, logoFileName: uploaded.fileName }
          : kind === 'government-id'
            ? {
                governmentIdUrl: uploaded.downloadUrl,
                governmentIdFileName: uploaded.fileName,
              }
            : { selfieUrl: uploaded.downloadUrl, selfieFileName: uploaded.fileName }),
      }))
    } catch (caughtError) {
      setError(
        caughtError instanceof Error ? caughtError.message : 'Could not upload file.',
      )
    } finally {
      setUploadingField('')
    }
  }

  return (
    <main className="setup-page">
      <aside className="setup-sidebar">
        <div className="studio-brand studio-brand--stacked">
          <div className="studio-brand__mark">E</div>
          <div>
            <strong>Eventora Studio</strong>
            <span>Organizer setup</span>
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
                <small>
                  {item === 'account'
                    ? 'Organizer identity'
                    : item === 'verification'
                      ? 'Documents and trust'
                      : item === 'payout'
                        ? 'Settlement destination'
                        : 'Final review'}
                </small>
              </div>
            </li>
          ))}
        </ol>

        <div className="setup-summary-card">
          <span className="eyebrow">Current status</span>
          <h3>{(session.status || 'draft').replace(/_/g, ' ')}</h3>
          <p>
            Save drafts at any time. When you submit, a superadmin reviews the
            application before Eventora unlocks organizer publishing and ticketing.
          </p>
        </div>
      </aside>

      <section className="setup-main">
        <header className="page-header">
          <div>
            <p className="eyebrow">Step {currentIndex + 1}</p>
            <h1>
              {safeStep === 'account'
                ? 'Tell us about your team'
                : safeStep === 'verification'
                  ? 'Upload your verification details'
                  : safeStep === 'payout'
                    ? 'Set your payout preferences'
                    : 'Review and submit'}
            </h1>
          </div>
        </header>

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
              <Field
                label="Business type"
                value={form.businessType}
                onChange={(value) => setForm((current) => ({ ...current, businessType: value }))}
                placeholder="Event Organizer, Festival, Venue, Community..."
              />
              <Field
                label="Instagram"
                value={form.instagram}
                onChange={(value) => setForm((current) => ({ ...current, instagram: value }))}
                placeholder="@eventora"
              />
              <Field
                label="Business address"
                value={form.businessAddress}
                onChange={(value) =>
                  setForm((current) => ({ ...current, businessAddress: value }))
                }
                wide
              />
              <FileField
                label="Logo or organizer mark"
                fileName={form.logoFileName}
                helper={uploadingField === 'logo' ? 'Uploading...' : 'PNG or JPG'}
                onChange={(file) => handleUpload('logo', file)}
              />
            </div>
          ) : null}

          {safeStep === 'verification' ? (
            <div className="form-grid">
              <FileField
                label="Government ID"
                fileName={form.governmentIdFileName}
                helper={
                  uploadingField === 'government-id'
                    ? 'Uploading...'
                    : 'National ID, passport, or driver licence'
                }
                onChange={(file) => handleUpload('government-id', file)}
              />
              <FileField
                label="Selfie / verification photo"
                fileName={form.selfieFileName}
                helper={uploadingField === 'selfie' ? 'Uploading...' : 'Optional but helpful'}
                onChange={(file) => handleUpload('selfie', file)}
              />
              <SelectField
                label="Registered business?"
                value={form.isRegisteredBusiness}
                options={[
                  { label: 'No', value: 'no' },
                  { label: 'Yes', value: 'yes' },
                ]}
                onChange={(value) =>
                  setForm((current) => ({
                    ...current,
                    isRegisteredBusiness: value as 'yes' | 'no',
                  }))
                }
              />
              <Field
                label="Business registration number"
                value={form.businessRegistrationNumber}
                onChange={(value) =>
                  setForm((current) => ({
                    ...current,
                    businessRegistrationNumber: value,
                  }))
                }
              />
              <Field
                label="TIN number"
                value={form.tinNumber}
                onChange={(value) => setForm((current) => ({ ...current, tinNumber: value }))}
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
                  <Field
                    label="Network"
                    value={form.network}
                    onChange={(value) => setForm((current) => ({ ...current, network: value }))}
                  />
                  <Field
                    label="Payout phone"
                    value={form.payoutPhone}
                    onChange={(value) =>
                      setForm((current) => ({ ...current, payoutPhone: value }))
                    }
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
                    label="Account name"
                    value={form.accountName}
                    onChange={(value) =>
                      setForm((current) => ({ ...current, accountName: value }))
                    }
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
                label="I agree to Eventora payout review and settlement controls."
                onChange={(checked) =>
                  setForm((current) => ({ ...current, agreedToPayoutTerms: checked }))
                }
                wide
              />
            </div>
          ) : null}

          {safeStep === 'review' ? (
            <div className="review-grid">
              <SummaryCard
                title="Organizer identity"
                rows={[
                  ['Organizer', form.organizerName || 'Not set'],
                  ['Contact', form.contactPerson || 'Not set'],
                  ['Email', form.email || 'Not set'],
                  ['Phone', form.phone || 'Not set'],
                  ['Business type', form.businessType || 'Not set'],
                ]}
              />
              <SummaryCard
                title="Verification"
                rows={[
                  ['ID file', form.governmentIdFileName || 'Missing'],
                  ['Selfie', form.selfieFileName || 'Not uploaded'],
                  ['Registered business', form.isRegisteredBusiness === 'yes' ? 'Yes' : 'No'],
                  ['Registration no.', form.businessRegistrationNumber || 'Not provided'],
                ]}
              />
              <SummaryCard
                title="Payout destination"
                rows={[
                  ['Method', form.payoutMethod],
                  [
                    'Destination',
                    form.payoutMethod === 'mobile-money'
                      ? `${form.network} • ${form.payoutPhone}`
                      : `${form.bankName} • ${form.accountNumber}`,
                  ],
                  ['Settlement', form.settlementPreference || 'Not set'],
                ]}
              />
              <CheckboxField
                checked={form.agreesToCompliance}
                label="I confirm these details are accurate and I agree to Eventora compliance review."
                onChange={(checked) =>
                  setForm((current) => ({ ...current, agreesToCompliance: checked }))
                }
                wide
              />
            </div>
          ) : null}

          {error ? <p className="form-error">{error}</p> : null}
          {message ? <p className="form-success">{message}</p> : null}

          <div className="setup-actions">
            <button
              className="button button--ghost"
              disabled={isSaving || currentIndex <= 0}
              onClick={() => navigate(`/setup/${previousStep}`)}
              type="button"
            >
              Back
            </button>
            <div className="setup-actions__right">
              <button
                className="button button--secondary"
                disabled={isSaving}
                onClick={handleSaveDraft}
                type="button"
              >
                {isSaving ? 'Saving...' : 'Save draft'}
              </button>
              {safeStep === 'review' ? (
                <button
                  className="button button--primary"
                  disabled={isSaving || !stepValid}
                  onClick={handleSubmit}
                  type="button"
                >
                  Submit for review
                </button>
              ) : (
                <button
                  className="button button--primary"
                  disabled={!stepValid}
                  onClick={() => navigate(`/setup/${nextStep}`)}
                  type="button"
                >
                  Continue
                </button>
              )}
            </div>
          </div>
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
      <input
        onChange={(event) => onChange(event.target.value)}
        placeholder={placeholder}
        type={type}
        value={value}
      />
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
  checked,
  label,
  onChange,
  wide = false,
}: {
  checked: boolean
  label: string
  onChange: (checked: boolean) => void
  wide?: boolean
}) {
  return (
    <label className={wide ? 'checkbox-field checkbox-field--wide' : 'checkbox-field'}>
      <input
        checked={checked}
        onChange={(event) => onChange(event.target.checked)}
        type="checkbox"
      />
      <span>{label}</span>
    </label>
  )
}

function SummaryCard({
  title,
  rows,
}: {
  title: string
  rows: Array<[string, string]>
}) {
  return (
    <div className="summary-card">
      <h3>{title}</h3>
      <dl>
        {rows.map(([label, value]) => (
          <div key={label}>
            <dt>{label}</dt>
            <dd>{value}</dd>
          </div>
        ))}
      </dl>
    </div>
  )
}
