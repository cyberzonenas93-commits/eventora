import { useEffect, useMemo, useState, type FormEvent } from 'react'
import { Link } from 'react-router-dom'
import { httpsCallable } from 'firebase/functions'
import { BarChart3, Link2, Trophy, UserPlus, type LucideIcon } from 'lucide-react'

import { functions } from '../firebaseFunctions'
import { formatMoney } from '../lib/formatters'
import { getErrorMessage } from '../lib/errorMessages'
import { listOrganizerEvents } from '../lib/portalData'
import { usePortalSession } from '../lib/portalSession'
import type { PortalEvent } from '../lib/types'

interface PartnerProfile {
  id: string
  name: string
  email?: string
  phone?: string
  type?: string
  commissionRate?: number
  status?: string
}

interface PartnerLink {
  id: string
  eventId: string
  eventTitle: string
  partnerProfileId: string
  partnerName: string
  refCode: string
  url: string
  clicks: number
  orders: number
  revenue: number
  status: string
}

const getPartnerDashboard = httpsCallable<
  { organizationId: string },
  { success: boolean; partners: PartnerProfile[]; links: PartnerLink[] }
>(functions, 'getPartnerDashboard')

const createPartnerProfile = httpsCallable<
  {
    organizationId: string
    name: string
    email?: string
    phone?: string
    type?: string
    commissionRate?: number
  },
  { success: boolean; partnerProfileId: string }
>(functions, 'createPartnerProfile')

const createPartnerEventLink = httpsCallable<
  { eventId: string; partnerProfileId: string; refCode?: string },
  { success: boolean; linkId: string; refCode: string; url: string }
>(functions, 'createPartnerEventLink')

export function PromotersPage() {
  const session = usePortalSession()
  const organizationId = session.organizationId ?? ''
  const [events, setEvents] = useState<PortalEvent[]>([])
  const [partners, setPartners] = useState<PartnerProfile[]>([])
  const [links, setLinks] = useState<PartnerLink[]>([])
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [message, setMessage] = useState<string | null>(null)
  const [partnerName, setPartnerName] = useState('')
  const [partnerEmail, setPartnerEmail] = useState('')
  const [partnerPhone, setPartnerPhone] = useState('')
  const [commissionRate, setCommissionRate] = useState('0')
  const [selectedPartnerId, setSelectedPartnerId] = useState('')
  const [selectedEventId, setSelectedEventId] = useState('')
  const [refCode, setRefCode] = useState('')
  const [submitting, setSubmitting] = useState(false)

  async function load() {
    if (!organizationId) return
    setLoading(true)
    setError(null)
    try {
      const [dashboard, eventList] = await Promise.all([
        getPartnerDashboard({ organizationId }).then((result) => result.data),
        listOrganizerEvents(organizationId),
      ])
      setPartners(dashboard.partners)
      setLinks(dashboard.links)
      setEvents(eventList)
      setSelectedPartnerId((current) => current || dashboard.partners[0]?.id || '')
      setSelectedEventId((current) => current || eventList[0]?.id || '')
    } catch (err) {
      setError(getErrorMessage(err, 'Could not load partners.'))
    } finally {
      setLoading(false)
    }
  }

  useEffect(() => {
    void load()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [organizationId])

  const totals = useMemo(
    () => ({
      clicks: links.reduce((sum, item) => sum + Number(item.clicks || 0), 0),
      orders: links.reduce((sum, item) => sum + Number(item.orders || 0), 0),
      revenue: links.reduce((sum, item) => sum + Number(item.revenue || 0), 0),
    }),
    [links],
  )

  async function handleCreatePartner(e: FormEvent) {
    e.preventDefault()
    if (!organizationId || submitting) return
    setSubmitting(true)
    setError(null)
    setMessage(null)
    try {
      await createPartnerProfile({
        organizationId,
        name: partnerName.trim(),
        email: partnerEmail.trim() || undefined,
        phone: partnerPhone.trim() || undefined,
        type: 'promoter',
        commissionRate: Number(commissionRate || 0),
      })
      setPartnerName('')
      setPartnerEmail('')
      setPartnerPhone('')
      setCommissionRate('0')
      setMessage('Partner created.')
      await load()
    } catch (err) {
      setError(getErrorMessage(err, 'Could not create partner.'))
    } finally {
      setSubmitting(false)
    }
  }

  async function handleCreateLink(e: FormEvent) {
    e.preventDefault()
    if (!selectedEventId || !selectedPartnerId || submitting) return
    setSubmitting(true)
    setError(null)
    setMessage(null)
    try {
      const result = await createPartnerEventLink({
        eventId: selectedEventId,
        partnerProfileId: selectedPartnerId,
        refCode: refCode.trim() || undefined,
      })
      setRefCode('')
      setMessage(`Partner link ready: ${result.data.url}`)
      await load()
    } catch (err) {
      setError(getErrorMessage(err, 'Could not create partner link.'))
    } finally {
      setSubmitting(false)
    }
  }

  return (
    <div className="dashboard-stack">
      <section className="page-hero page-hero--events page-hero--campaign-reach">
        <div className="page-hero__content">
          <p className="eyebrow">Partners</p>
          <h2>Partners and referrals</h2>
          <div className="hero-chip-row">
            <span>{partners.length} partners</span>
            <span>{totals.clicks} clicks</span>
            <span>{formatMoney(totals.revenue)} attributed</span>
          </div>
        </div>
        <div className="page-hero__panel">
          <Link className="button button--secondary" to="/studio/overview">
            Back to overview
          </Link>
        </div>
      </section>

      <section className="content-grid">
        <>
            {error && <p className="checkout__error">{error}</p>}
            {message && <p className="checkout__info">{message}</p>}
            <article className="panel">
              <div className="panel__header">
                <div>
                  <p className="eyebrow">Performance</p>
                  <h3>Partner dashboard</h3>
                </div>
              </div>
              <div className="partner-feature-grid">
                <FeatureCard icon={UserPlus} title="Partners" body={`${partners.length} active partner profiles`} />
                <FeatureCard icon={Link2} title="Clicks" body={`${totals.clicks} referral visits`} />
                <FeatureCard icon={BarChart3} title="Orders" body={`${totals.orders} attributed orders`} />
                <FeatureCard icon={Trophy} title="Revenue" body={formatMoney(totals.revenue)} />
              </div>
            </article>

            <article className="panel">
              <div className="panel__header">
                <div>
                  <p className="eyebrow">Invite</p>
                  <h3>Create partner</h3>
                </div>
              </div>
              <form className="checkout__form" onSubmit={handleCreatePartner}>
                <label className="checkout__label">
                  Name
                  <input className="checkout__input" value={partnerName} onChange={(e) => setPartnerName(e.target.value)} required />
                </label>
                <label className="checkout__label">
                  Email
                  <input className="checkout__input" type="email" value={partnerEmail} onChange={(e) => setPartnerEmail(e.target.value)} />
                </label>
                <label className="checkout__label">
                  Phone
                  <input className="checkout__input" value={partnerPhone} onChange={(e) => setPartnerPhone(e.target.value)} />
                </label>
                <label className="checkout__label">
                  Commission %
                  <input className="checkout__input" min={0} step="0.01" type="number" value={commissionRate} onChange={(e) => setCommissionRate(e.target.value)} />
                </label>
                <button className="button button--primary" disabled={submitting || !partnerName.trim()} type="submit">
                  Create partner
                </button>
              </form>
            </article>

            <article className="panel">
              <div className="panel__header">
                <div>
                  <p className="eyebrow">Links</p>
                  <h3>Create event referral link</h3>
                </div>
              </div>
              <form className="checkout__form" onSubmit={handleCreateLink}>
                <label className="checkout__label">
                  Event
                  <select className="checkout__input" value={selectedEventId} onChange={(e) => setSelectedEventId(e.target.value)}>
                    {events.map((event) => (
                      <option key={event.id} value={event.id}>{event.title}</option>
                    ))}
                  </select>
                </label>
                <label className="checkout__label">
                  Partner
                  <select className="checkout__input" value={selectedPartnerId} onChange={(e) => setSelectedPartnerId(e.target.value)}>
                    {partners.map((partner) => (
                      <option key={partner.id} value={partner.id}>{partner.name}</option>
                    ))}
                  </select>
                </label>
                <label className="checkout__label">
                  Referral code
                  <input className="checkout__input" placeholder="optional" value={refCode} onChange={(e) => setRefCode(e.target.value)} />
                </label>
                <button className="button button--primary" disabled={submitting || !selectedEventId || !selectedPartnerId} type="submit">
                  Create link
                </button>
              </form>
            </article>

            <article className="panel">
              <div className="panel__header">
                <div>
                  <p className="eyebrow">Referral links</p>
                  <h3>Live links</h3>
                </div>
              </div>
              {loading ? (
                <p className="text-subtle">Loading...</p>
              ) : links.length === 0 ? (
                <div className="empty-card">
                  <h4>No links yet</h4>
                  <p>Create an event referral link for each partner.</p>
                </div>
              ) : (
                <div className="orders-table-wrap">
                  <table className="orders-table">
                    <thead>
                      <tr>
                        <th>Partner</th>
                        <th>Event</th>
                        <th>Code</th>
                        <th>Clicks</th>
                        <th>Orders</th>
                        <th>Revenue</th>
                      </tr>
                    </thead>
                    <tbody>
                      {links.map((item) => (
                        <tr key={item.id}>
                          <td><strong>{item.partnerName}</strong></td>
                          <td>{item.eventTitle}</td>
                          <td className="cell-muted">{item.refCode}</td>
                          <td>{item.clicks}</td>
                          <td>{item.orders}</td>
                          <td>{formatMoney(item.revenue)}</td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                </div>
              )}
            </article>
        </>
      </section>
    </div>
  )
}

function FeatureCard({
  icon: Icon,
  title,
  body,
}: {
  icon: LucideIcon
  title: string
  body: string
}) {
  return (
    <div className="partner-feature-card">
      <span className="partner-feature-card__icon" aria-hidden>
        <Icon size={18} />
      </span>
      <strong>{title}</strong>
      <p>{body}</p>
    </div>
  )
}
