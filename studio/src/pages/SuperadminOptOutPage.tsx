import { useState } from 'react'
import { httpsCallable } from 'firebase/functions'

import { functions } from '../firebaseFunctions'
import { canPerformAdminAction } from '../lib/adminRoles'
import { copy } from '../lib/copy'
import { getErrorMessage } from '../lib/errorMessages'
import { trackEvent } from '../lib/analytics'
import { usePortalSession } from '../lib/portalSession'

const recordSmsOptOut = httpsCallable<
  { phone: string; source?: string },
  { success: boolean; phone: string }
>(functions, 'recordSmsOptOut')

const BASE_URL = typeof window !== 'undefined' ? window.location.origin : 'https://vennuzo.web.app'

export function SuperadminOptOutPage() {
  const session = usePortalSession()
  const canRecordOptOut = canPerformAdminAction(session.adminRole, 'record_sms_opt_out')
  const [phone, setPhone] = useState('')
  const [submitting, setSubmitting] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [notice, setNotice] = useState<string | null>(null)

  async function handleAddOptOut(e: React.FormEvent) {
    e.preventDefault()
    if (!canRecordOptOut) return
    if (!phone.trim()) return
    setError(null)
    setNotice(null)
    setSubmitting(true)
    try {
      await recordSmsOptOut({ phone: phone.trim(), source: 'admin' })
      setNotice(copy.optOutRecorded)
      void trackEvent('sms_opt_out_recorded', {
        source: 'admin',
      }, {
        area: 'admin',
        role: session.adminRole,
      })
      void trackEvent('admin_action', {
        action: 'sms_opt_out_recorded',
      }, {
        area: 'admin',
        role: session.adminRole,
      })
      setPhone('')
    } catch (e) {
      setError(getErrorMessage(e, copy.recordOptOutFailed))
    } finally {
      setSubmitting(false)
    }
  }

  if (!canRecordOptOut) {
    return (
      <div className="page-loader">
        <p>This admin role cannot update SMS opt-outs.</p>
        <p className="text-subtle">Choose another work area from the admin sidebar.</p>
      </div>
    )
  }

  return (
    <>
      <section className="status-card superadmin-card">
        <div className="status-card__header">
	          <p className="eyebrow">SMS preferences</p>
	          <h1>SMS opt-out list</h1>
	        </div>
	        <p>Use this page when someone asks not to receive Vennuzo SMS messages.</p>
        {error && <p className="form-error">{error}</p>}
        {notice && <p className="form-success">{notice}</p>}

        <article className="superadmin-admin-card" style={{ marginTop: '1rem' }}>
	          <strong>Unsubscribe page</strong>
	          <p className="superadmin-admin-card__intro">
	            Share this link when a customer wants to unsubscribe themselves.
	          </p>
          <p style={{ wordBreak: 'break-all', fontFamily: 'monospace', marginTop: '0.5rem' }}>
            <a href={`${BASE_URL}/unsubscribe`} target="_blank" rel="noopener noreferrer">
              {BASE_URL}/unsubscribe
            </a>
          </p>
        </article>

	        <article className="superadmin-admin-card" style={{ marginTop: '1rem' }}>
	          <strong>Add opt-out manually</strong>
	          <p className="superadmin-admin-card__intro">
	            Record a phone number after a customer or organizer asks support for help.
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
