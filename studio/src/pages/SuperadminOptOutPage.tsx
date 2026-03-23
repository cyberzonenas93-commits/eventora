import { useState } from 'react'
import { httpsCallable } from 'firebase/functions'

import { functions } from '../firebaseFunctions'
import { copy } from '../lib/copy'
import { getErrorMessage } from '../lib/errorMessages'

const recordSmsOptOut = httpsCallable<
  { phone: string; source?: string },
  { success: boolean; phone: string }
>(functions, 'recordSmsOptOut')

const BASE_URL = typeof window !== 'undefined' ? window.location.origin : 'https://vennuzo.web.app'

export function SuperadminOptOutPage() {
  const [phone, setPhone] = useState('')
  const [submitting, setSubmitting] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [notice, setNotice] = useState<string | null>(null)

  async function handleAddOptOut(e: React.FormEvent) {
    e.preventDefault()
    if (!phone.trim()) return
    setError(null)
    setNotice(null)
    setSubmitting(true)
    try {
      await recordSmsOptOut({ phone: phone.trim(), source: 'admin' })
      setNotice(copy.optOutRecorded)
      setPhone('')
    } catch (e) {
      setError(getErrorMessage(e, copy.recordOptOutFailed))
    } finally {
      setSubmitting(false)
    }
  }

  return (
    <>
      <section className="status-card superadmin-card">
        <div className="status-card__header">
          <p className="eyebrow">Superadmin</p>
          <h1>SMS opt-out & STOP webhook</h1>
        </div>
        <p>Public opt-out and webhook URLs. Use these for compliance and provider “Reply STOP” handling.</p>
        {error && <p className="form-error">{error}</p>}
        {notice && <p className="form-success">{notice}</p>}

        <article className="superadmin-admin-card" style={{ marginTop: '1rem' }}>
          <strong>Public opt-out page</strong>
          <p className="superadmin-admin-card__intro">
            Share this link so users can unsubscribe from Vennuzo SMS (e.g. in campaign footer).
          </p>
          <p style={{ wordBreak: 'break-all', fontFamily: 'monospace', marginTop: '0.5rem' }}>
            <a href={`${BASE_URL}/unsubscribe`} target="_blank" rel="noopener noreferrer">
              {BASE_URL}/unsubscribe
            </a>
          </p>
        </article>

        <article className="superadmin-admin-card" style={{ marginTop: '1rem' }}>
          <strong>STOP webhook (for providers)</strong>
          <p className="superadmin-admin-card__intro">
            When your SMS provider supports “Reply STOP” or inbound webhooks, configure them to POST to this URL with the subscriber’s phone number.
          </p>
          <p style={{ wordBreak: 'break-all', fontFamily: 'monospace', marginTop: '0.5rem' }}>
            POST {BASE_URL}/api/sms-opt-out
          </p>
          <p className="text-subtle" style={{ marginTop: '0.5rem' }}>
            Body (JSON): <code>{'{"phone": "+233XXXXXXXXX"}'}</code> or <code>{'{"phone": "0XX XXX XXXX"}'}</code>. Ghana numbers are normalized automatically. Response: 200 with <code>{'{"success": true}'}</code> or 400 with error message.
          </p>
        </article>

        <article className="superadmin-admin-card" style={{ marginTop: '1rem' }}>
          <strong>Add opt-out manually</strong>
          <p className="superadmin-admin-card__intro">
            Record a phone number as opted out (e.g. from support request).
          </p>
          <form onSubmit={handleAddOptOut} className="superadmin-admin-form" style={{ marginTop: '0.5rem' }}>
            <label className="input-group">
              <span className="input-group__label">Phone number</span>
              <input
                type="tel"
                value={phone}
                onChange={(e) => setPhone(e.target.value)}
                placeholder="0XX XXX XXXX or +233..."
                disabled={submitting}
              />
            </label>
            <button type="submit" className="button button--primary" disabled={submitting || !phone.trim()}>
              {submitting ? 'Adding…' : 'Add opt-out'}
            </button>
          </form>
        </article>
      </section>
    </>
  )
}
