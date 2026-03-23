import { useEffect, useState } from 'react'
import { httpsCallable } from 'firebase/functions'

import { functions } from '../firebaseFunctions'
import { copy } from '../lib/copy'
import { getErrorMessage } from '../lib/errorMessages'
import { formatDateTime, formatMoney } from '../lib/formatters'

const listAdminCampaigns = httpsCallable<
  { limit?: number; status?: string },
  {
    campaigns: Array<{
      id: string
      eventId: string
      eventTitle: string
      organizationId: string
      status: string
      channels: string[]
      pushAudience: number
      smsAudience: number
      walletReservationAmount: number
      totalSmsCharged?: number
      createdAt: string
      scheduledAt?: string
      createdBy: string
    }>
  }
>(functions, 'listAdminCampaigns')

export function SuperadminCampaignsPage() {
  const [campaigns, setCampaigns] = useState<Array<{
    id: string
    eventId: string
    eventTitle: string
    organizationId: string
    status: string
    channels: string[]
    pushAudience: number
    smsAudience: number
    walletReservationAmount: number
    totalSmsCharged?: number
    createdAt: string
    scheduledAt?: string
    createdBy: string
  }>>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [statusFilter, setStatusFilter] = useState('')

  useEffect(() => {
    let cancelled = false
    setLoading(true)
    listAdminCampaigns({ limit: 50, status: statusFilter || undefined })
      .then((r) => {
        if (!cancelled) setCampaigns(r.data.campaigns)
      })
      .catch((e) => {
        if (!cancelled) setError(getErrorMessage(e, copy.campaignsLoadFailed))
      })
      .finally(() => {
        if (!cancelled) setLoading(false)
      })
    return () => { cancelled = true }
  }, [statusFilter])

  if (loading) return <div className="page-loader">{copy.loading}</div>

  return (
    <>
      <section className="status-card superadmin-card">
        <div className="status-card__header">
          <p className="eyebrow">Superadmin</p>
          <h1>Campaigns</h1>
        </div>
        <p>All promotion campaigns across organizers. Organizers can schedule from the Promote page.</p>
        {error && <p className="form-error">{error}</p>}

        <div className="superadmin-filters" style={{ marginTop: '1rem' }}>
          {['', 'live', 'scheduled', 'completed'].map((s) => (
            <button
              key={s || 'all'}
              type="button"
              className={statusFilter === s ? 'is-active' : ''}
              onClick={() => setStatusFilter(s)}
            >
              {s || 'All'}
            </button>
          ))}
        </div>

        <div className="superadmin-queue" style={{ marginTop: '1rem' }}>
          {campaigns.length === 0 ? (
            <p className="text-subtle">No campaigns match the filter.</p>
          ) : (
            <table style={{ width: '100%', borderCollapse: 'collapse', fontSize: '0.9rem' }}>
              <thead>
                <tr style={{ borderBottom: '2px solid var(--color-border, #eee)', textAlign: 'left' }}>
                  <th style={{ padding: '0.5rem' }}>Event</th>
                  <th style={{ padding: '0.5rem' }}>Org</th>
                  <th style={{ padding: '0.5rem' }}>Status</th>
                  <th style={{ padding: '0.5rem' }}>Channels</th>
                  <th style={{ padding: '0.5rem' }}>Audience</th>
                  <th style={{ padding: '0.5rem' }}>SMS cost</th>
                  <th style={{ padding: '0.5rem' }}>Created / Scheduled</th>
                </tr>
              </thead>
              <tbody>
                {campaigns.map((c) => (
                  <tr key={c.id} style={{ borderBottom: '1px solid var(--color-border, #eee)' }}>
                    <td style={{ padding: '0.5rem' }}>{c.eventTitle || c.eventId}</td>
                    <td style={{ padding: '0.5rem' }} className="text-subtle">{c.organizationId}</td>
                    <td style={{ padding: '0.5rem' }}>{c.status}</td>
                    <td style={{ padding: '0.5rem' }}>{c.channels.join(', ') || '—'}</td>
                    <td style={{ padding: '0.5rem' }}>P: {c.pushAudience} · S: {c.smsAudience}</td>
                    <td style={{ padding: '0.5rem' }}>
                      {c.walletReservationAmount > 0 ? formatMoney(c.walletReservationAmount) : '—'}
                      {c.totalSmsCharged != null && c.totalSmsCharged > 0 && (
                        <span className="text-subtle"> (charged {formatMoney(c.totalSmsCharged)})</span>
                      )}
                    </td>
                    <td style={{ padding: '0.5rem' }}>
                      {formatDateTime(c.createdAt)}
                      {c.scheduledAt && (
                        <><br /><span className="text-subtle">Sched: {formatDateTime(c.scheduledAt)}</span></>
                      )}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </div>
      </section>
    </>
  )
}
