import { useEffect, useState } from 'react'
import { Link, useSearchParams } from 'react-router-dom'
import { httpsCallable } from 'firebase/functions'

import { functions } from '../firebaseFunctions'
import { copy } from '../lib/copy'
import { formatMoney } from '../lib/formatters'
import { getErrorMessage } from '../lib/errorMessages'
import { listOrganizerCampaigns, listOrganizerEvents } from '../lib/portalData'
import { usePortalSession } from '../lib/portalSession'
import type { PortalCampaign, PortalEvent } from '../lib/types'

const launchEventNotificationCampaign = httpsCallable<
  {
    eventId: string
    message: string
    channels: string[]
    title?: string
    shareLinkEnabled?: boolean
    scheduledAt?: string
    name?: string
    packageId?: string
  },
  { campaignId: string; jobsCreated: number; status: string }
>(functions, 'launchEventNotificationCampaign')

const getEventAudienceEstimate = httpsCallable<
  { eventId: string; packageId?: string },
  {
    pushCount: number
    smsCount: number
    platformSmsUnitPriceGhs: number
    estimatedSmsCostGhs: number
  }
>(functions, 'getEventAudienceEstimate')

const listPromoPackages = httpsCallable<
  void,
  { packages: { id: string; name: string; description?: string; defaultSmsRateGhs: number; smsMarginMultiplier: number; minSpend?: number; order: number }[] }
>(functions, 'listPromoPackages')

export function PromotePage() {
  const [searchParams] = useSearchParams()
  const prefilledEventId = searchParams.get('eventId') ?? undefined
  const session = usePortalSession()
  const { organizationId } = session
  const [events, setEvents] = useState<PortalEvent[]>([])
  const [loading, setLoading] = useState(true)
  const [submitting, setSubmitting] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [success, setSuccess] = useState<{ campaignId: string; status: string } | null>(null)

  const [eventId, setEventId] = useState(prefilledEventId ?? '')
  const [title, setTitle] = useState('')
  const [message, setMessage] = useState('')
  const [channelPush, setChannelPush] = useState(true)
  const [channelSms, setChannelSms] = useState(true)
  const [shareLinkEnabled, setShareLinkEnabled] = useState(true)
  const [estimate, setEstimate] = useState<{
    pushCount: number
    smsCount: number
    platformSmsUnitPriceGhs: number
    estimatedSmsCostGhs: number
  } | null>(null)
  const [estimateLoading, setEstimateLoading] = useState(false)
  const [campaigns, setCampaigns] = useState<PortalCampaign[]>([])
  const [packages, setPackages] = useState<{ id: string; name: string; description?: string; defaultSmsRateGhs: number; smsMarginMultiplier: number; minSpend?: number; order: number }[]>([])
  const [packageId, setPackageId] = useState('')
  const [scheduleNow, setScheduleNow] = useState(true)
  const [scheduledAt, setScheduledAt] = useState('')

  useEffect(() => {
    let cancelled = false
    if (!organizationId) return
    async function run() {
      setLoading(true)
      try {
        const [list, campaignList, packagesRes] = await Promise.all([
          listOrganizerEvents(organizationId ?? ''),
          listOrganizerCampaigns(organizationId ?? '', 15),
          listPromoPackages().then((r) => r.data.packages).catch(() => []),
        ])
        if (!cancelled) {
          setEvents(list)
          setCampaigns(campaignList)
          setPackages(packagesRes)
          if (prefilledEventId && list.some((e) => e.id === prefilledEventId) && !eventId) {
            setEventId(prefilledEventId)
          } else if (!eventId && list.length > 0) {
            setEventId(list[0].id)
          }
        }
      } finally {
        if (!cancelled) setLoading(false)
      }
    }
    void run()
    return () => {
      cancelled = true
    }
  }, [organizationId, prefilledEventId])

  useEffect(() => {
    if (!eventId) {
      setEstimate(null)
      return
    }
    let cancelled = false
    setEstimateLoading(true)
    getEventAudienceEstimate({ eventId, packageId: packageId || undefined })
      .then((r) => {
        if (!cancelled) {
          setEstimate(r.data)
        }
      })
      .catch(() => {
        if (!cancelled) setEstimate(null)
      })
      .finally(() => {
        if (!cancelled) setEstimateLoading(false)
      })
    return () => {
      cancelled = true
    }
  }, [eventId, packageId])

  const selectedEvent = events.find((e) => e.id === eventId)
  const channels: string[] = []
  if (channelPush) channels.push('push')
  if (channelSms) channels.push('sms')

  async function handleSubmit() {
    if (!eventId || !message.trim() || channels.length === 0) {
      setError(copy.selectEventMessageAndChannel)
      return
    }
    setError(null)
    setSuccess(null)
    setSubmitting(true)
    try {
      const scheduledAtIso =
        scheduleNow || !scheduledAt.trim()
          ? undefined
          : new Date(scheduledAt.trim()).toISOString()
      const result = await launchEventNotificationCampaign({
        eventId,
        message: message.trim(),
        channels,
        title: title.trim() || undefined,
        shareLinkEnabled,
        name: title.trim() || selectedEvent?.title ? `${selectedEvent?.title ?? 'Event'} campaign` : undefined,
        packageId: packageId || undefined,
        scheduledAt: scheduledAtIso,
      })
      setSuccess({
        campaignId: result.data.campaignId,
        status: result.data.status,
      })
      if (organizationId) {
        const next = await listOrganizerCampaigns(organizationId, 15)
        setCampaigns(next)
      }
    } catch (e: unknown) {
      const msg = getErrorMessage(e, copy.campaignLaunchFailed)
      setError(
        typeof msg === 'string' && msg.toLowerCase().includes('insufficient')
          ? `${msg} ${copy.campaignLaunchInsufficient}`
          : msg,
      )
    } finally {
      setSubmitting(false)
    }
  }

  if (loading) {
    return <div className="page-loader">{copy.loading}</div>
  }

  return (
    <div className="dashboard-stack">
      <section className="page-hero page-hero--events">
        <div className="page-hero__content">
          <p className="eyebrow">Promote event</p>
          <h2>Send push and SMS to your audience.</h2>
          <div className="hero-chip-row">
            <span>Push + SMS campaigns</span>
            <span>Audience: RSVPs & ticket buyers</span>
          </div>
        </div>
        <div className="page-hero__panel">
          <Link className="button button--secondary" to="/studio/overview">
            Back to overview
          </Link>
          <Link className="button button--secondary" to="/studio/events">
            View events
          </Link>
        </div>
      </section>

      <section className="content-grid">
        <article className="panel">
          <div className="panel__header">
            <div>
              <p className="eyebrow">Campaign</p>
              <h3>Launch promotion</h3>
            </div>
          </div>

          <div className="form-grid" style={{ marginTop: '1rem' }}>
            <label className="field">
              <span>Event *</span>
              <select
                value={eventId}
                onChange={(e) => setEventId(e.target.value)}
              >
                <option value="">Select event</option>
                {events.map((e) => (
                  <option key={e.id} value={e.id}>
                    {e.title} ({e.status})
                  </option>
                ))}
              </select>
            </label>

            {packages.length > 0 ? (
              <label className="field">
                <span>Pricing package</span>
                <select
                  value={packageId}
                  onChange={(e) => setPackageId(e.target.value)}
                >
                  <option value="">Default</option>
                  {packages.map((p) => (
                    <option key={p.id} value={p.id}>
                      {p.name}
                    </option>
                  ))}
                </select>
              </label>
            ) : null}

            <label className="field field--wide">
              <span>Notification title (optional)</span>
              <input
                type="text"
                value={title}
                onChange={(e) => setTitle(e.target.value)}
                placeholder={selectedEvent?.title ? `${selectedEvent.title} update` : 'Event update'}
              />
            </label>

            <label className="field field--wide">
              <span>Message *</span>
              <textarea
                value={message}
                onChange={(e) => setMessage(e.target.value)}
                placeholder="Remind your audience about the event, share the link, or add a call to action. Keep it short for SMS."
                rows={4}
              />
            </label>

            <div className="field field--wide">
              <span>Channels *</span>
              <div style={{ display: 'flex', gap: '1rem', marginTop: '0.5rem' }}>
                <label className="checkbox">
                  <input
                    type="checkbox"
                    checked={channelPush}
                    onChange={(e) => setChannelPush(e.target.checked)}
                  />
                  <span>Push notification</span>
                </label>
                <label className="checkbox">
                  <input
                    type="checkbox"
                    checked={channelSms}
                    onChange={(e) => setChannelSms(e.target.checked)}
                  />
                  <span>SMS</span>
                </label>
              </div>
            </div>

            <label className="checkbox checkbox--wide">
              <input
                type="checkbox"
                checked={shareLinkEnabled}
                onChange={(e) => setShareLinkEnabled(e.target.checked)}
              />
              <span>Include share link in campaign payload (for deep link)</span>
            </label>

            <div className="field field--wide">
              <span>Schedule</span>
              <div style={{ display: 'flex', flexWrap: 'wrap', gap: '0.75rem', alignItems: 'center', marginTop: '0.5rem' }}>
                <label className="checkbox">
                  <input
                    type="radio"
                    name="schedule"
                    checked={scheduleNow}
                    onChange={() => setScheduleNow(true)}
                  />
                  <span>Send now</span>
                </label>
                <label className="checkbox">
                  <input
                    type="radio"
                    name="schedule"
                    checked={!scheduleNow}
                    onChange={() => setScheduleNow(false)}
                  />
                  <span>Schedule for later</span>
                </label>
                {!scheduleNow && (
                  <label className="input-group" style={{ marginLeft: '0.5rem' }}>
                    <input
                      type="datetime-local"
                      value={scheduledAt}
                      onChange={(e) => setScheduledAt(e.target.value)}
                      min={new Date().toISOString().slice(0, 16)}
                    />
                  </label>
                )}
              </div>
              {!scheduleNow && (
                <p className="text-subtle" style={{ marginTop: '0.35rem', fontSize: '0.9rem' }}>
                  Campaign will run at the scheduled time (Africa/Accra). You can change or cancel it from Recent campaigns until it starts.
                </p>
              )}
            </div>
          </div>

          {eventId && (estimateLoading ? (
            <p className="text-subtle">Loading audience estimate…</p>
          ) : estimate ? (
            <p className="text-subtle" style={{ marginTop: '0.5rem' }}>
              ~{estimate.pushCount} push · ~{estimate.smsCount} SMS
              {channelSms && estimate.smsCount > 0 && (
                <> · Est. cost <strong>{formatMoney(estimate.estimatedSmsCostGhs)}</strong> (SMS)</>
              )}
            </p>
          ) : null)}
          {error ? (
            <p className="form-error">
              {error}
              {error.toLowerCase().includes('insufficient') ? (
                <><br /><Link to="/studio/payments">Go to Payments & Payouts to load wallet</Link></>
              ) : null}
            </p>
          ) : null}
          {success ? (
            <p className="form-success">
              Campaign launched. Status: {success.status}. Campaign ID: {success.campaignId}
            </p>
          ) : null}

          <div style={{ marginTop: '1.5rem', display: 'flex', gap: '0.75rem' }}>
            <button
              type="button"
              className="button button--primary"
              disabled={submitting || !eventId || !message.trim() || channels.length === 0}
              onClick={() => void handleSubmit()}
            >
              {submitting ? 'Launching…' : 'Launch campaign'}
            </button>
            <Link className="button button--ghost" to="/studio/events">
              Cancel
            </Link>
          </div>
        </article>

        <aside className="setup-side-panel">
          <div className="setup-side-panel__card">
            <span className="eyebrow">Audience</span>
            <p>
              Recipients are event RSVPs and ticket buyers. Push goes to users with the app and notifications enabled; SMS goes to valid Ghana mobile numbers we have on file. You never see contact details.
            </p>
          </div>
          <div className="setup-side-panel__card">
            <span className="eyebrow">Wallet & pricing</span>
            <p>
              SMS campaigns are charged from your campaign wallet at the estimated rate shown. Load your wallet in <Link to="/studio/payments">Payments & Payouts</Link>. Push is free.
            </p>
          </div>
          {campaigns.length > 0 ? (
            <div className="setup-side-panel__card">
              <span className="eyebrow">Recent campaigns</span>
              <ul style={{ margin: 0, paddingLeft: '1.25rem', fontSize: '0.9rem' }}>
                {campaigns.slice(0, 8).map((c) => (
                  <li key={c.id} style={{ marginBottom: '0.35rem' }}>
                    <strong>{c.name}</strong>
                    {' · '}
                    {c.eventTitle}
                    {' · '}
                    <span className="text-subtle">{c.status}</span>
                    {c.walletReservationAmount > 0 && (
                      <span className="text-subtle"> · {formatMoney(c.totalSmsCharged ?? 0)} charged</span>
                    )}
                  </li>
                ))}
              </ul>
            </div>
          ) : null}
        </aside>
      </section>
    </div>
  )
}
