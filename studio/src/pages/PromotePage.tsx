import { useEffect, useMemo, useState, type ChangeEvent } from 'react'
import { Link, useSearchParams } from 'react-router-dom'
import { httpsCallable } from 'firebase/functions'
import {
  BarChart3,
  Bell,
  Brain,
  CalendarClock,
  Gauge,
  Goal,
  Link2,
  Maximize2,
  MessageSquareText,
  MousePointerClick,
  RadioTower,
  Repeat2,
  Send,
  ShieldCheck,
  Sparkles,
  Split,
  Target,
  TrendingUp,
  UploadCloud,
  UsersRound,
  WalletCards,
  Zap,
} from 'lucide-react'

import { functions } from '../firebaseFunctions'
import { trackEvent } from '../lib/analytics'
import { copy } from '../lib/copy'
import { formatDateTime, formatMoney } from '../lib/formatters'
import { getErrorMessage } from '../lib/errorMessages'
import { listOrganizerCampaigns, listOrganizerEvents } from '../lib/portalData'
import { usePortalSession } from '../lib/portalSession'
import type { PortalCampaign, PortalEvent } from '../lib/types'

const launchEventNotificationCampaign = httpsCallable<
  {
    eventId: string
    message: string
    channels: string[]
    audienceSources?: string[]
    audienceSourceName?: string
    title?: string
    shareLinkEnabled?: boolean
    scheduledAt?: string
    name?: string
    packageId?: string
    objective?: CampaignObjective
    audienceStrategy?: AudienceStrategy
    optimizationGoal?: OptimizationGoal
    bidStrategy?: BidStrategy
    budgetCapGhs?: number
    frequencyCap?: number
    creativeMode?: CreativeMode
  },
  { campaignId: string; jobsCreated: number; status: string }
>(functions, 'launchEventNotificationCampaign')

const getEventAudienceEstimate = httpsCallable<
  { eventId: string; packageId?: string; audienceSources?: string[]; audienceSourceName?: string; channels?: string[] },
  {
    pushCount: number
    smsCount: number
    uploadedCount?: number
    platformPushUnitPriceGhs: number
    platformSmsUnitPriceGhs: number
    featuredPlacementPriceGhs?: number
    announcementPlacementPriceGhs?: number
    estimatedPushCostGhs: number
    estimatedSmsCostGhs: number
    estimatedPlacementCostGhs?: number
    estimatedTotalCostGhs: number
  }
>(functions, 'getEventAudienceEstimate')

const importAudienceContacts = httpsCallable<
  {
    organizationId: string
    sourceName?: string
    contacts: Array<{
      displayName?: string
      email?: string
      phone?: string
      marketingConsent: boolean
      smsConsent?: boolean
    }>
  },
  {
    importedCount: number
    skippedCount: number
    pushMatchedCount: number
    smsEligibleCount: number
  }
>(functions, 'importAudienceContacts')

const listPromoPackages = httpsCallable<
  void,
  { packages: { id: string; name: string; description?: string; defaultSmsRateGhs: number; smsMarginMultiplier: number; minSpend?: number; order: number }[] }
>(functions, 'listPromoPackages')

type AudienceImportContact = {
  displayName?: string
  email?: string
  phone?: string
  marketingConsent: boolean
  smsConsent?: boolean
}

type CampaignObjective =
  | 'sell_tickets'
  | 'drive_rsvps'
  | 'fill_tables'
  | 'boost_awareness'
  | 'retarget_interest'
  | 'last_call'

type AudienceStrategy =
  | 'recommended'
  | 'high_intent'
  | 'owned_crm'
  | 'broad_discovery'
  | 'retargeting'

type OptimizationGoal = 'conversions' | 'reach' | 'clicks' | 'rsvps' | 'tables'
type BidStrategy = 'lowest_cost' | 'balanced' | 'premium_attention'
type CreativeMode = 'single' | 'ab_test'

const OBJECTIVES: {
  id: CampaignObjective
  label: string
  description: string
  Icon: typeof Target
  recommendedGoal: OptimizationGoal
  recommendedStrategy: AudienceStrategy
}[] = [
  {
    id: 'sell_tickets',
    label: 'Sell tickets',
    description: 'Prioritize buyers and high-intent guests who are closest to checkout.',
    Icon: Target,
    recommendedGoal: 'conversions',
    recommendedStrategy: 'high_intent',
  },
  {
    id: 'drive_rsvps',
    label: 'Drive RSVPs',
    description: 'Move interested guests onto the list for free or RSVP-based events.',
    Icon: Goal,
    recommendedGoal: 'rsvps',
    recommendedStrategy: 'recommended',
  },
  {
    id: 'fill_tables',
    label: 'Fill tables',
    description: 'Push premium packages to previous buyers and imported VIP contacts.',
    Icon: Sparkles,
    recommendedGoal: 'tables',
    recommendedStrategy: 'owned_crm',
  },
  {
    id: 'boost_awareness',
    label: 'Boost awareness',
    description: 'Use placements and share links to get the event in front of more people.',
    Icon: RadioTower,
    recommendedGoal: 'reach',
    recommendedStrategy: 'broad_discovery',
  },
  {
    id: 'retarget_interest',
    label: 'Retarget interest',
    description: 'Re-engage RSVPs, ticket buyers, and CRM contacts who already know you.',
    Icon: Repeat2,
    recommendedGoal: 'clicks',
    recommendedStrategy: 'retargeting',
  },
  {
    id: 'last_call',
    label: 'Last call',
    description: 'Send a time-sensitive reminder before the event closes.',
    Icon: Zap,
    recommendedGoal: 'conversions',
    recommendedStrategy: 'high_intent',
  },
]

const AUDIENCE_STRATEGIES: {
  id: AudienceStrategy
  label: string
  description: string
  sources: Array<'event_rsvps' | 'ticket_buyers' | 'uploaded_contacts'>
  channels: Array<'push' | 'sms' | 'featured' | 'announcement'>
}[] = [
  {
    id: 'recommended',
    label: 'Recommended mix',
    description: 'Balanced push, SMS, RSVPs, buyers, and any imported list.',
    sources: ['event_rsvps', 'ticket_buyers', 'uploaded_contacts'],
    channels: ['push', 'sms'],
  },
  {
    id: 'high_intent',
    label: 'High intent',
    description: 'Focus on RSVPs and buyers with direct push/SMS delivery.',
    sources: ['event_rsvps', 'ticket_buyers'],
    channels: ['push', 'sms'],
  },
  {
    id: 'owned_crm',
    label: 'Owned CRM',
    description: 'Use imported contacts plus past buyers for VIP and table offers.',
    sources: ['ticket_buyers', 'uploaded_contacts'],
    channels: ['sms', 'push'],
  },
  {
    id: 'broad_discovery',
    label: 'Discovery boost',
    description: 'Use sponsored placements and light direct delivery for visibility.',
    sources: ['event_rsvps'],
    channels: ['featured', 'announcement', 'push'],
  },
  {
    id: 'retargeting',
    label: 'Retargeting',
    description: 'Re-message known guests with a share link and conversion copy.',
    sources: ['event_rsvps', 'ticket_buyers', 'uploaded_contacts'],
    channels: ['push', 'sms'],
  },
]

function parseBooleanFlag(value: string | undefined, fallback: boolean) {
  if (value == null || value.trim() === '') return fallback
  return ['yes', 'true', '1', 'y', 'opted in', 'opt-in', 'subscribed'].includes(
    value.trim().toLowerCase(),
  )
}

function parseDelimitedRows(input: string) {
  const rows: string[][] = []
  let row: string[] = []
  let cell = ''
  let quoted = false
  for (let index = 0; index < input.length; index += 1) {
    const char = input[index]
    const next = input[index + 1]
    if (char === '"' && quoted && next === '"') {
      cell += '"'
      index += 1
      continue
    }
    if (char === '"') {
      quoted = !quoted
      continue
    }
    if ((char === ',' || char === '\t') && !quoted) {
      row.push(cell.trim())
      cell = ''
      continue
    }
    if ((char === '\n' || char === '\r') && !quoted) {
      if (char === '\r' && next === '\n') index += 1
      row.push(cell.trim())
      if (row.some(Boolean)) rows.push(row)
      row = []
      cell = ''
      continue
    }
    cell += char
  }
  row.push(cell.trim())
  if (row.some(Boolean)) rows.push(row)
  return rows
}

function normalizeHeader(value: string) {
  return value.trim().toLowerCase().replace(/[^a-z0-9]/g, '')
}

function parseAudienceCsv(input: string) {
  const rows = parseDelimitedRows(input)
  if (rows.length === 0) return { contacts: [] as AudienceImportContact[], rowCount: 0 }
  const header = rows[0].map(normalizeHeader)
  const knownHeaders = new Set([
    'name',
    'fullname',
    'displayname',
    'email',
    'emailaddress',
    'phone',
    'phonenumber',
    'mobile',
    'consent',
    'marketingconsent',
    'smsconsent',
  ])
  const hasHeader = header.some((cell) => knownHeaders.has(cell))
  const dataRows = hasHeader ? rows.slice(1) : rows
  const findIndex = (...names: string[]) => header.findIndex((cell) => names.includes(cell))
  const nameIndex = hasHeader ? findIndex('name', 'fullname', 'displayname') : 0
  const emailIndex = hasHeader ? findIndex('email', 'emailaddress') : 1
  const phoneIndex = hasHeader ? findIndex('phone', 'phonenumber', 'mobile') : 2
  const consentIndex = hasHeader ? findIndex('consent', 'marketingconsent') : -1
  const smsConsentIndex = hasHeader ? findIndex('smsconsent') : -1
  const contacts = dataRows
    .map((row) => ({
      displayName: nameIndex >= 0 ? row[nameIndex] : undefined,
      email: emailIndex >= 0 ? row[emailIndex] : undefined,
      phone: phoneIndex >= 0 ? row[phoneIndex] : undefined,
      marketingConsent: parseBooleanFlag(consentIndex >= 0 ? row[consentIndex] : undefined, false),
      smsConsent: parseBooleanFlag(smsConsentIndex >= 0 ? row[smsConsentIndex] : undefined, false),
    }))
    .filter((contact) => contact.email || contact.phone)
    .slice(0, 500)
  return { contacts, rowCount: dataRows.length }
}

function getSuggestedMessage(objective: CampaignObjective, event: PortalEvent) {
  const location = [event.venue, event.city].filter(Boolean).join(', ')
  const when = event.startAt ? formatDateTime(event.startAt) : ''
  const base = `${event.title}${when ? ` is happening ${when}` : ''}${location ? ` at ${location}` : ''}.`
  switch (objective) {
    case 'drive_rsvps':
      return `${base} RSVP now so the host can keep your spot ready.`
    case 'fill_tables':
      return `${base} Table packages are available for groups. Reserve your table before the best spots go.`
    case 'boost_awareness':
      return `${base} Share it with your people and see what is happening on Vennuzo.`
    case 'retarget_interest':
      return `${base} You showed interest before. Open the event page and finish your plan today.`
    case 'last_call':
      return `${base} Last call: secure your entry before sales close.`
    case 'sell_tickets':
    default:
      return `${base} Tickets are available now. Book yours on Vennuzo.`
  }
}

export function PromotePage() {
  const [searchParams] = useSearchParams()
  const prefilledEventId = searchParams.get('eventId') ?? undefined
  const prefilledAudienceSourceName = searchParams.get('audienceSourceName') ?? ''
  const session = usePortalSession()
  const { organizationId } = session
  const [events, setEvents] = useState<PortalEvent[]>([])
  const [loading, setLoading] = useState(true)
  const [submitting, setSubmitting] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [success, setSuccess] = useState<{ campaignId: string; status: string } | null>(null)

  const [eventId, setEventId] = useState(prefilledEventId ?? '')
  const [objective, setObjective] = useState<CampaignObjective>('sell_tickets')
  const [audienceStrategy, setAudienceStrategy] = useState<AudienceStrategy>('recommended')
  const [optimizationGoal, setOptimizationGoal] = useState<OptimizationGoal>('conversions')
  const [bidStrategy, setBidStrategy] = useState<BidStrategy>('balanced')
  const [creativeMode, setCreativeMode] = useState<CreativeMode>('single')
  const [budgetCapGhs, setBudgetCapGhs] = useState('')
  const [frequencyCap, setFrequencyCap] = useState(2)
  const [title, setTitle] = useState('')
  const [message, setMessage] = useState('')
  const [channelPush, setChannelPush] = useState(true)
  const [channelSms, setChannelSms] = useState(true)
  const [channelFeatured, setChannelFeatured] = useState(false)
  const [channelAnnouncement, setChannelAnnouncement] = useState(false)
  const [sourceRsvps, setSourceRsvps] = useState(true)
  const [sourceTicketBuyers, setSourceTicketBuyers] = useState(true)
  const [sourceUploaded, setSourceUploaded] = useState(false)
  const [audienceSourceName, setAudienceSourceName] = useState(prefilledAudienceSourceName)
  const [shareLinkEnabled, setShareLinkEnabled] = useState(true)
  const [estimate, setEstimate] = useState<{
    pushCount: number
    smsCount: number
    uploadedCount?: number
    platformPushUnitPriceGhs: number
    platformSmsUnitPriceGhs: number
    featuredPlacementPriceGhs?: number
    announcementPlacementPriceGhs?: number
    estimatedPushCostGhs: number
    estimatedSmsCostGhs: number
    estimatedPlacementCostGhs?: number
    estimatedTotalCostGhs: number
  } | null>(null)
  const [estimateLoading, setEstimateLoading] = useState(false)
  const [audienceVersion, setAudienceVersion] = useState(0)
  const [audienceImporting, setAudienceImporting] = useState(false)
  const [audienceImportResult, setAudienceImportResult] = useState<{
    importedCount: number
    skippedCount: number
    pushMatchedCount: number
    smsEligibleCount: number
  } | null>(null)
  const [campaigns, setCampaigns] = useState<PortalCampaign[]>([])
  const [packages, setPackages] = useState<{ id: string; name: string; description?: string; defaultSmsRateGhs: number; smsMarginMultiplier: number; platformPushUnitPriceGhs?: number; minSpend?: number; order: number }[]>([])
  const [packageId, setPackageId] = useState('')
  const [scheduleNow, setScheduleNow] = useState(true)
  const [scheduledAt, setScheduledAt] = useState('')

  const selectedEvent = events.find((e) => e.id === eventId)
  const channels = useMemo(() => {
    const selectedChannels: string[] = []
    if (channelPush) selectedChannels.push('push')
    if (channelSms) selectedChannels.push('sms')
    if (channelFeatured) selectedChannels.push('featured')
    if (channelAnnouncement) selectedChannels.push('announcement')
    return selectedChannels
  }, [channelAnnouncement, channelFeatured, channelPush, channelSms])
  const audienceSources: string[] = []
  if (sourceRsvps) audienceSources.push('event_rsvps')
  if (sourceTicketBuyers) audienceSources.push('ticket_buyers')
  if (sourceUploaded) audienceSources.push('uploaded_contacts')
  const audienceSourcesKey = audienceSources.join(',')
  const usesDirectAudience = channelPush || channelSms
  const objectiveConfig = OBJECTIVES.find((item) => item.id === objective) ?? OBJECTIVES[0]
  const strategyConfig = AUDIENCE_STRATEGIES.find((item) => item.id === audienceStrategy) ?? AUDIENCE_STRATEGIES[0]

  useEffect(() => {
    if (prefilledAudienceSourceName) {
      setAudienceSourceName(prefilledAudienceSourceName)
      setSourceUploaded(true)
      return
    }
    const rawHandoff = window.sessionStorage.getItem('vennuzo:crmCampaignHandoff')
    if (!rawHandoff) return
    try {
      const handoff = JSON.parse(rawHandoff) as { sourceName?: string }
      if (handoff.sourceName) {
        setAudienceSourceName(handoff.sourceName)
        setSourceUploaded(true)
      }
    } catch {
      window.sessionStorage.removeItem('vennuzo:crmCampaignHandoff')
    }
  }, [prefilledAudienceSourceName])

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
  }, [eventId, organizationId, prefilledEventId])

  useEffect(() => {
    if (!eventId) {
      setEstimate(null)
      return
    }
    let cancelled = false
    setEstimateLoading(true)
    getEventAudienceEstimate({
      eventId,
      packageId: packageId || undefined,
      channels,
      audienceSources: audienceSourcesKey ? audienceSourcesKey.split(',') : [],
      audienceSourceName: audienceSourceName || undefined,
    })
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
  }, [audienceSourceName, audienceSourcesKey, audienceVersion, channels, eventId, packageId])

  async function handleAudienceUpload(event: ChangeEvent<HTMLInputElement>) {
    const file = event.target.files?.[0]
    event.target.value = ''
    if (!file || !organizationId) return
    setError(null)
    setAudienceImportResult(null)
    setAudienceImporting(true)
    try {
      const text = await file.text()
      const parsed = parseAudienceCsv(text)
      if (parsed.contacts.length === 0) {
        setError('No usable audience contacts were found. Use CSV columns like name, email, phone, consent.')
        return
      }
      const result = await importAudienceContacts({
        organizationId,
        sourceName: file.name,
        contacts: parsed.contacts,
      })
      setAudienceImportResult(result.data)
      setAudienceSourceName(file.name)
      setSourceUploaded(true)
      setAudienceVersion((current) => current + 1)
    } catch (e: unknown) {
      setError(getErrorMessage(e, 'Audience upload failed. Check the CSV and try again.'))
    } finally {
      setAudienceImporting(false)
    }
  }

  function applyAudienceStrategy(nextStrategy: AudienceStrategy) {
    const config = AUDIENCE_STRATEGIES.find((item) => item.id === nextStrategy)
    if (!config) return
    setAudienceStrategy(nextStrategy)
    setSourceRsvps(config.sources.includes('event_rsvps'))
    setSourceTicketBuyers(config.sources.includes('ticket_buyers'))
    setSourceUploaded(config.sources.includes('uploaded_contacts'))
    setChannelPush(config.channels.includes('push'))
    setChannelSms(config.channels.includes('sms'))
    setChannelFeatured(config.channels.includes('featured'))
    setChannelAnnouncement(config.channels.includes('announcement'))
  }

  function applyObjective(nextObjective: CampaignObjective) {
    const config = OBJECTIVES.find((item) => item.id === nextObjective)
    setObjective(nextObjective)
    if (!config) return
    setOptimizationGoal(config.recommendedGoal)
    applyAudienceStrategy(config.recommendedStrategy)
    if (!title.trim() && selectedEvent?.title) {
      setTitle(`${selectedEvent.title}: ${config.label}`)
    }
    if (!message.trim() && selectedEvent) {
      setMessage(getSuggestedMessage(nextObjective, selectedEvent))
    }
  }

  async function handleSubmit() {
    if (!eventId || !message.trim() || channels.length === 0) {
      setError(copy.selectEventMessageAndChannel)
      return
    }
    if (usesDirectAudience && audienceSources.length === 0) {
      setError('Choose at least one owned audience source for push or SMS.')
      return
    }
    const parsedBudgetCap = Number(budgetCapGhs || 0)
    if (budgetCapGhs.trim() && (!Number.isFinite(parsedBudgetCap) || parsedBudgetCap <= 0)) {
      setError('Enter a valid budget cap or leave the field empty.')
      return
    }
    if (estimate && parsedBudgetCap > 0 && estimate.estimatedTotalCostGhs > parsedBudgetCap) {
      setError(`This setup is estimated at ${formatMoney(estimate.estimatedTotalCostGhs)}, above your ${formatMoney(parsedBudgetCap)} cap. Increase the cap or narrow the audience.`)
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
        audienceSources,
        audienceSourceName: audienceSourceName || undefined,
        title: title.trim() || undefined,
        shareLinkEnabled,
        name: title.trim() || (selectedEvent?.title ? `${selectedEvent.title} campaign` : undefined),
        packageId: packageId || undefined,
        scheduledAt: scheduledAtIso,
        objective,
        audienceStrategy,
        optimizationGoal,
        bidStrategy,
        budgetCapGhs: parsedBudgetCap > 0 ? parsedBudgetCap : undefined,
        frequencyCap,
        creativeMode,
      })
	      setSuccess({
	        campaignId: result.data.campaignId,
	        status: result.data.status,
	      })
	      void trackEvent('campaign_launched', {
	        channel_count: channels.length,
	        has_sms: channels.includes('sms'),
	        has_push: channels.includes('push'),
	        scheduled: Boolean(scheduledAtIso),
	        status: result.data.status,
	        objective,
	        optimization_goal: optimizationGoal,
	      }, {
	        area: 'studio',
	        organizationId,
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

  const launchDisabled =
    submitting ||
    !eventId ||
    !message.trim() ||
    channels.length === 0 ||
    (usesDirectAudience && audienceSources.length === 0)
  const selectedPackage = packages.find((item) => item.id === packageId)
  const selectedSourceCount = audienceSources.length
  const directReachLabel = estimate
    ? `${estimate.pushCount} push-ready · ${estimate.smsCount} SMS-ready`
    : eventId
      ? 'Estimating reachable audience'
      : 'Choose an event to estimate reach'
  const selectedChannelLabels = [
    channelPush ? 'Push' : '',
    channelSms ? 'SMS' : '',
    channelFeatured ? 'Featured' : '',
    channelAnnouncement ? 'Announcement' : '',
  ].filter(Boolean)
  const scheduleLabel = scheduleNow
    ? 'Send immediately'
    : scheduledAt
      ? new Date(scheduledAt).toLocaleString([], {
          dateStyle: 'medium',
          timeStyle: 'short',
        })
      : 'Schedule time needed'
  const messageLength = message.trim().length
  const estimatedReach = estimate
    ? estimate.pushCount + estimate.smsCount + (channelFeatured ? 1800 : 0) + (channelAnnouncement ? 900 : 0)
    : 0
  const objectiveMultiplier: Record<CampaignObjective, number> = {
    sell_tickets: 0.055,
    drive_rsvps: 0.09,
    fill_tables: 0.028,
    boost_awareness: 0.16,
    retarget_interest: 0.07,
    last_call: 0.06,
  }
  const strategyMultiplier: Record<AudienceStrategy, number> = {
    recommended: 1,
    high_intent: 1.25,
    owned_crm: 1.12,
    broad_discovery: 0.72,
    retargeting: 1.18,
  }
  const projectedResults = Math.max(0, Math.round(
    estimatedReach * objectiveMultiplier[objective] * strategyMultiplier[audienceStrategy],
  ))
  const costPerProjectedResult = estimate && projectedResults > 0
    ? estimate.estimatedTotalCostGhs / projectedResults
    : 0
  const funnelSteps = [
    { label: 'Reach', value: estimatedReach },
    { label: optimizationGoal === 'reach' ? 'Engaged' : 'Clicks', value: Math.round(estimatedReach * 0.22) },
    { label: optimizationGoal === 'rsvps' ? 'RSVPs' : optimizationGoal === 'tables' ? 'Table leads' : 'Actions', value: projectedResults },
  ]

  return (
    <div className="dashboard-stack">
      <section className="page-hero page-hero--events page-hero--campaign-reach">
        <div className="page-hero__content">
          <p className="eyebrow">Reach console</p>
          <h2>Build a focused campaign without guessing who receives it.</h2>
          <div className="hero-chip-row">
            <span>{directReachLabel}</span>
            <span>{selectedChannelLabels.length ? selectedChannelLabels.join(' + ') : 'Choose delivery channels'}</span>
            <span>{scheduleLabel}</span>
            {audienceSourceName ? <span>CRM list: {audienceSourceName}</span> : null}
            {estimate ? <span>{formatMoney(estimate.estimatedTotalCostGhs)} estimated hold</span> : null}
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

      <section className="campaign-workbench">
        <article className="campaign-builder">
          <div className="campaign-builder__header">
            <div>
              <p className="eyebrow">Campaign builder</p>
              <h3>Choose the outcome, audience, channel mix, and optimization rules.</h3>
            </div>
            <span>{objectiveConfig.label}</span>
          </div>

          <div className="campaign-step">
            <div className="campaign-step__rail"><span>1</span></div>
            <div className="campaign-step__body">
              <div className="campaign-step__title">
                <strong>Choose campaign objective</strong>
                <small>{objectiveConfig.description}</small>
              </div>
              <div className="campaign-objective-grid">
                {OBJECTIVES.map(({ id, label, description, Icon }) => (
                  <button
                    key={id}
                    type="button"
                    className={`campaign-objective-card${objective === id ? ' campaign-objective-card--active' : ''}`}
                    onClick={() => applyObjective(id)}
                  >
                    <Icon size={18} aria-hidden />
                    <strong>{label}</strong>
                    <span>{description}</span>
                  </button>
                ))}
              </div>
              <div className="campaign-optimization-grid">
                <label className="field">
                  <span>Optimization goal</span>
                  <select value={optimizationGoal} onChange={(e) => setOptimizationGoal(e.target.value as OptimizationGoal)}>
                    <option value="conversions">Ticket purchases</option>
                    <option value="rsvps">RSVPs</option>
                    <option value="tables">Table leads</option>
                    <option value="clicks">Link clicks</option>
                    <option value="reach">Reach</option>
                  </select>
                </label>
                <label className="field">
                  <span>Bid strategy</span>
                  <select value={bidStrategy} onChange={(e) => setBidStrategy(e.target.value as BidStrategy)}>
                    <option value="balanced">Balanced delivery</option>
                    <option value="lowest_cost">Lowest cost first</option>
                    <option value="premium_attention">Premium attention</option>
                  </select>
                </label>
                <label className="field">
                  <span>Budget cap</span>
                  <input
                    type="number"
                    min="0"
                    step="1"
                    value={budgetCapGhs}
                    onChange={(e) => setBudgetCapGhs(e.target.value)}
                    placeholder="No cap"
                  />
                </label>
                <label className="field">
                  <span>Frequency cap</span>
                  <select value={frequencyCap} onChange={(e) => setFrequencyCap(Number(e.target.value))}>
                    <option value={1}>1 touch per person</option>
                    <option value={2}>2 touches per person</option>
                    <option value={3}>3 touches per person</option>
                    <option value={5}>5 touches per person</option>
                  </select>
                </label>
              </div>
            </div>
          </div>

          <div className="campaign-step">
            <div className="campaign-step__rail"><span>2</span></div>
            <div className="campaign-step__body">
              <div className="campaign-step__title">
                <strong>Choose event and pricing</strong>
                <small>{selectedEvent ? selectedEvent.title : 'Pick the event this campaign belongs to.'}</small>
              </div>
              <div className="campaign-field-row">
                <label className="field">
                  <span>Event *</span>
                  <select value={eventId} onChange={(e) => setEventId(e.target.value)}>
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
                    <select value={packageId} onChange={(e) => setPackageId(e.target.value)}>
                      <option value="">Default rates</option>
                      {packages.map((p) => (
                        <option key={p.id} value={p.id}>
                          {p.name}
                        </option>
                      ))}
                    </select>
                  </label>
                ) : null}
              </div>
            </div>
          </div>

          <div className="campaign-step">
            <div className="campaign-step__rail"><span>3</span></div>
            <div className="campaign-step__body">
              <div className="campaign-step__title">
                <strong>Write the message</strong>
                <small>{messageLength ? `${messageLength} characters` : 'Short, specific messages work best for SMS and push.'}</small>
              </div>
              <div className="campaign-message-grid">
                <div className="campaign-message-fields">
                  <label className="field">
                    <span>Notification title</span>
                    <input
                      type="text"
                      value={title}
                      onChange={(e) => setTitle(e.target.value)}
                      placeholder={selectedEvent?.title ? `${selectedEvent.title} update` : 'Event update'}
                    />
                  </label>
                  <label className="field">
                    <span>Message *</span>
                    <textarea
                      value={message}
                      onChange={(e) => setMessage(e.target.value)}
                      placeholder="Remind guests why the event matters today. Add the action you want them to take."
                      rows={5}
                    />
                  </label>
                  <div className="campaign-creative-toolbar">
                    <button type="button" className={creativeMode === 'single' ? 'is-active' : ''} onClick={() => setCreativeMode('single')}>
                      <MousePointerClick size={14} aria-hidden />
                      Single creative
                    </button>
                    <button type="button" className={creativeMode === 'ab_test' ? 'is-active' : ''} onClick={() => setCreativeMode('ab_test')}>
                      <Split size={14} aria-hidden />
                      A/B test
                    </button>
                    <button type="button" onClick={() => selectedEvent && setMessage(getSuggestedMessage(objective, selectedEvent))}>
                      <Brain size={14} aria-hidden />
                      Draft from objective
                    </button>
                  </div>
                </div>
                <div className="campaign-preview-card" aria-label="Campaign message preview">
                  <span>Preview</span>
                  <strong>{title.trim() || selectedEvent?.title || 'Vennuzo update'}</strong>
                  <p>{message.trim() || 'Your audience will see the campaign message here.'}</p>
                  {shareLinkEnabled ? <small>Share link included</small> : <small>No share link</small>}
                </div>
              </div>
            </div>
          </div>

          <div className="campaign-step">
            <div className="campaign-step__rail"><span>4</span></div>
            <div className="campaign-step__body">
              <div className="campaign-step__title">
                <strong>Pick delivery channels</strong>
                <small>{selectedChannelLabels.length ? selectedChannelLabels.join(', ') : 'Select at least one channel.'}</small>
              </div>
              <div className="channel-picker channel-picker--premium">
                <label className={channelPush ? 'channel-card channel-card--active' : 'channel-card'}>
                  <input type="checkbox" checked={channelPush} onChange={(e) => setChannelPush(e.target.checked)} />
                  <span className="channel-card__icon" aria-hidden><Bell size={18} /></span>
                  <span>
                    <strong>Push notification</strong>
                    <small>{estimate ? `${estimate.pushCount} matched users` : 'Matched Vennuzo users with push enabled'}</small>
                    <em>{estimate ? formatMoney(estimate.estimatedPushCostGhs) : 'Preference-gated'}</em>
                  </span>
                </label>
                <label className={channelSms ? 'channel-card channel-card--active' : 'channel-card'}>
                  <input type="checkbox" checked={channelSms} onChange={(e) => setChannelSms(e.target.checked)} />
                  <span className="channel-card__icon" aria-hidden><MessageSquareText size={18} /></span>
                  <span>
                    <strong>SMS</strong>
                    <small>{estimate ? `${estimate.smsCount} consented numbers` : 'Hubtel SMS to opted-in contacts'}</small>
                    <em>{estimate ? formatMoney(estimate.estimatedSmsCostGhs) : 'Wallet billed'}</em>
                  </span>
                </label>
                <label className={channelFeatured ? 'channel-card channel-card--active' : 'channel-card'}>
                  <input type="checkbox" checked={channelFeatured} onChange={(e) => setChannelFeatured(e.target.checked)} />
                  <span className="channel-card__icon" aria-hidden><Sparkles size={18} /></span>
                  <span>
                    <strong>Featured placement</strong>
                    <small>Sponsored discovery slot on web and app surfaces</small>
                    <em>{estimate ? formatMoney(estimate.featuredPlacementPriceGhs ?? 0) : 'Placement rate'}</em>
                  </span>
                </label>
                <label className={channelAnnouncement ? 'channel-card channel-card--active' : 'channel-card'}>
                  <input type="checkbox" checked={channelAnnouncement} onChange={(e) => setChannelAnnouncement(e.target.checked)} />
                  <span className="channel-card__icon" aria-hidden><Maximize2 size={18} /></span>
                  <span>
                    <strong>Announcement</strong>
                    <small>High-attention app spotlight for eligible visitors</small>
                    <em>{estimate ? formatMoney(estimate.announcementPlacementPriceGhs ?? 0) : 'Placement rate'}</em>
                  </span>
                </label>
              </div>
            </div>
          </div>

          {usesDirectAudience ? (
            <div className="campaign-step">
              <div className="campaign-step__rail"><span>5</span></div>
              <div className="campaign-step__body">
                <div className="campaign-step__title">
                  <strong>Select audience strategy</strong>
                  <small>{strategyConfig.description}</small>
                </div>
                <div className="campaign-strategy-grid">
                  {AUDIENCE_STRATEGIES.map((strategy) => (
                    <button
                      key={strategy.id}
                      type="button"
                      className={`campaign-strategy-card${audienceStrategy === strategy.id ? ' campaign-strategy-card--active' : ''}`}
                      onClick={() => applyAudienceStrategy(strategy.id)}
                    >
                      <strong>{strategy.label}</strong>
                      <span>{strategy.description}</span>
                    </button>
                  ))}
                </div>
                <div className="campaign-step__title campaign-step__title--compact">
                  <strong>Owned audience sources</strong>
                  <small>{selectedSourceCount ? `${selectedSourceCount} source${selectedSourceCount === 1 ? '' : 's'} selected` : 'Push and SMS need at least one owned source.'}</small>
                </div>
                <div className="audience-source-grid">
                  <label className={sourceRsvps ? 'audience-source-card audience-source-card--active' : 'audience-source-card'}>
                    <input type="checkbox" checked={sourceRsvps} onChange={(e) => setSourceRsvps(e.target.checked)} />
                    <span className="audience-source-card__icon" aria-hidden><UsersRound size={18} /></span>
                    <span>
                      <strong>Event RSVPs</strong>
                      <small>Guests who saved a spot for this event.</small>
                    </span>
                  </label>
                  <label className={sourceTicketBuyers ? 'audience-source-card audience-source-card--active' : 'audience-source-card'}>
                    <input type="checkbox" checked={sourceTicketBuyers} onChange={(e) => setSourceTicketBuyers(e.target.checked)} />
                    <span className="audience-source-card__icon" aria-hidden><ShieldCheck size={18} /></span>
                    <span>
                      <strong>Ticket buyers</strong>
                      <small>Paid, complimentary, reserved, and cash-at-gate buyers.</small>
                    </span>
                  </label>
                  <label className={sourceUploaded ? 'audience-source-card audience-source-card--active' : 'audience-source-card'}>
                    <input type="checkbox" checked={sourceUploaded} onChange={(e) => setSourceUploaded(e.target.checked)} />
                    <span className="audience-source-card__icon" aria-hidden><UploadCloud size={18} /></span>
                    <span>
                      <strong>Imported list</strong>
                      <small>{audienceSourceName ? audienceSourceName : 'CSV contacts with explicit consent.'}</small>
                    </span>
                  </label>
                </div>
                <div className="audience-import-card audience-import-card--quiet">
                  <div>
                    <span className="eyebrow">Upload audience</span>
                    <strong>Bring in a consented CSV list</strong>
                    <p>Accepted columns: name, email, phone, consent, smsConsent. Push only reaches matched Vennuzo accounts; phone-only contacts are SMS-only.</p>
                    {audienceImportResult ? (
                      <p className="audience-import-card__result">
                        Imported {audienceImportResult.importedCount}. SMS-ready {audienceImportResult.smsEligibleCount}. Push-matched {audienceImportResult.pushMatchedCount}. Skipped {audienceImportResult.skippedCount}.
                      </p>
                    ) : null}
                  </div>
                  <label className="button button--secondary audience-import-card__button">
                    <UploadCloud size={16} aria-hidden />
                    {audienceImporting ? 'Importing...' : 'Upload CSV'}
                    <input type="file" accept=".csv,text/csv,text/plain" disabled={audienceImporting} onChange={(e) => void handleAudienceUpload(e)} />
                  </label>
                </div>
              </div>
            </div>
          ) : null}

          <div className="campaign-step">
            <div className="campaign-step__rail"><span>{usesDirectAudience ? 6 : 5}</span></div>
            <div className="campaign-step__body">
              <div className="campaign-step__title">
                <strong>Confirm timing and link</strong>
                <small>{scheduleLabel}</small>
              </div>
              <div className="campaign-option-row">
                <label className="checkbox campaign-share-toggle">
                  <input type="checkbox" checked={shareLinkEnabled} onChange={(e) => setShareLinkEnabled(e.target.checked)} />
                  <Link2 size={16} aria-hidden />
                  <span>Include event share link</span>
                </label>
                <div className="schedule-picker">
                  <label className="checkbox">
                    <input type="radio" name="schedule" checked={scheduleNow} onChange={() => setScheduleNow(true)} />
                    <span>Send now</span>
                  </label>
                  <label className="checkbox">
                    <input type="radio" name="schedule" checked={!scheduleNow} onChange={() => setScheduleNow(false)} />
                    <span>Schedule</span>
                  </label>
                  {!scheduleNow && (
                    <label className="input-group">
                      <span>Scheduled send time</span>
                      <input type="datetime-local" value={scheduledAt} onChange={(e) => setScheduledAt(e.target.value)} min={new Date().toISOString().slice(0, 16)} />
                    </label>
                  )}
                </div>
              </div>
            </div>
          </div>
        </article>

        <aside className="campaign-summary-panel">
          <div className="campaign-summary-card campaign-forecast-card">
            <span className="eyebrow"><BarChart3 size={14} aria-hidden /> Forecast</span>
            <div className="campaign-forecast-card__hero">
              <strong>{projectedResults}</strong>
              <span>{optimizationGoal === 'rsvps' ? 'projected RSVPs' : optimizationGoal === 'tables' ? 'projected table leads' : optimizationGoal === 'reach' ? 'projected engagements' : 'projected actions'}</span>
            </div>
            <div className="campaign-funnel">
              {funnelSteps.map((step) => (
                <div key={step.label}>
                  <span>{step.label}</span>
                  <strong>{step.value.toLocaleString()}</strong>
                </div>
              ))}
            </div>
            <p>
              Optimizing for {optimizationGoal.replace(/_/g, ' ')} with {bidStrategy.replace(/_/g, ' ')}
              {costPerProjectedResult > 0 ? ` · about ${formatMoney(costPerProjectedResult)} per projected result.` : '.'}
            </p>
          </div>

          <div className="campaign-summary-card campaign-summary-card--primary">
            <span className="eyebrow"><WalletCards size={14} aria-hidden /> Launch summary</span>
            <strong>{estimate ? formatMoney(estimate.estimatedTotalCostGhs) : 'GHS 0'}</strong>
            <p>{estimateLoading ? 'Refreshing estimate...' : 'Estimated wallet hold for selected paid delivery.'}</p>
            {estimate ? (
              <div className="campaign-cost-grid">
                <span>Push <strong>{channelPush ? formatMoney(estimate.estimatedPushCostGhs) : 'GHS 0'}</strong></span>
                <span>SMS <strong>{channelSms ? formatMoney(estimate.estimatedSmsCostGhs) : 'GHS 0'}</strong></span>
                <span>Placement <strong>{formatMoney(estimate.estimatedPlacementCostGhs ?? 0)}</strong></span>
              </div>
            ) : null}
          </div>

          <div className="campaign-summary-card">
            <span className="eyebrow"><Gauge size={14} aria-hidden /> Delivery plan</span>
            <div className="campaign-reach-metrics">
              <span><strong>{estimate?.pushCount ?? 0}</strong> push</span>
              <span><strong>{estimate?.smsCount ?? 0}</strong> SMS</span>
              <span><strong>{estimatedReach.toLocaleString()}</strong> total est.</span>
            </div>
            <p>
              {strategyConfig.label}: {strategyConfig.description} Frequency cap: {frequencyCap} touch{frequencyCap === 1 ? '' : 'es'} per person.
            </p>
          </div>

          <div className="campaign-summary-card">
            <span className="eyebrow"><CalendarClock size={14} aria-hidden /> Readiness</span>
            <ul className="campaign-check-list">
              <li className={objective ? 'is-ready' : ''}>Objective selected</li>
              <li className={eventId ? 'is-ready' : ''}>Event selected</li>
              <li className={message.trim() ? 'is-ready' : ''}>Message written</li>
              <li className={channels.length > 0 ? 'is-ready' : ''}>Channel selected</li>
              <li className={!usesDirectAudience || audienceSources.length > 0 ? 'is-ready' : ''}>Audience source selected</li>
              <li className={!budgetCapGhs.trim() || !estimate || Number(budgetCapGhs) >= estimate.estimatedTotalCostGhs ? 'is-ready' : ''}>Budget cap clears estimate</li>
            </ul>
          </div>

          <div className="campaign-summary-card">
            <span className="eyebrow"><TrendingUp size={14} aria-hidden /> Optimization notes</span>
            <ul className="campaign-insight-list">
              <li>High-intent sources should be used before broad placements when conversion is the goal.</li>
              <li>{creativeMode === 'ab_test' ? 'A/B test mode is marked for performance reporting.' : 'Single creative mode will keep reporting cleaner.'}</li>
              <li>{channelFeatured || channelAnnouncement ? 'Placement delivery can lift discovery, but direct channels usually convert better.' : 'Add featured or announcement placement when awareness is the primary goal.'}</li>
            </ul>
          </div>

          {selectedPackage ? (
            <div className="campaign-summary-card">
              <span className="eyebrow">Package</span>
              <strong>{selectedPackage.name}</strong>
              {selectedPackage.description ? <p>{selectedPackage.description}</p> : null}
            </div>
          ) : null}

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

          <div className="campaign-actions campaign-actions--sticky">
            <button type="button" className="button button--primary" disabled={launchDisabled} onClick={() => void handleSubmit()}>
              <Send size={16} aria-hidden />
              {submitting ? 'Launching...' : 'Launch campaign'}
            </button>
            <Link className="button button--ghost" to="/studio/events">Cancel</Link>
          </div>

          {campaigns.length > 0 ? (
            <div className="campaign-summary-card">
              <span className="eyebrow"><CalendarClock size={14} aria-hidden /> Recent campaigns</span>
              <ul className="campaign-insight-list campaign-insight-list--cards">
                {campaigns.slice(0, 5).map((c) => (
                  <li key={c.id}>
                    <strong>{c.name}</strong>
                    <span>{c.eventTitle}</span>
                    <small>{c.status}{c.walletReservationAmount > 0 ? ` · ${formatMoney(c.totalSmsCharged ?? 0)} charged` : ''}</small>
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
