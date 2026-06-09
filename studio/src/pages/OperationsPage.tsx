import { useEffect, useMemo, useState, type FormEvent } from 'react'
import { Link, useSearchParams } from 'react-router-dom'
import { httpsCallable } from 'firebase/functions'
import {
  Banknote,
  Boxes,
  CheckCircle2,
  Download,
  Lock,
  Plus,
  ReceiptText,
  Sparkles,
  UserPlus,
  Users,
} from 'lucide-react'

import { functions } from '../firebaseFunctions'
import { formatMoney } from '../lib/formatters'
import { getErrorMessage } from '../lib/errorMessages'
import { listOrganizerEvents } from '../lib/portalData'
import { usePortalSession } from '../lib/portalSession'
import type { PortalEvent } from '../lib/types'

const createOrganizerFeedLink = httpsCallable<
  { eventId: string },
  { success: boolean; shareId: string; url: string }
>(functions, 'createOrganizerFeedLink')

const issueComplimentaryTickets = httpsCallable<
  {
    eventId: string
    selections: Record<string, number>
    buyerName: string
    buyerPhone: string
    buyerEmail: string
  },
  { success: boolean; orderId: string; ticketUrl: string }
>(functions, 'issueComplimentaryTickets')

const validateEventTicket = httpsCallable<
  { qrToken: string },
  TicketValidationResult
>(functions, 'validateEventTicket')

interface TicketValidationResult {
  success: boolean
  eventTitle: string
  orderId: string
  attendeeName: string
  tierName: string
  paymentStatus: string
  ticketStatus: string
  admitted: boolean
  requiresCash: boolean
  amountDue: number
}

const admitEventTicket = httpsCallable<{ qrToken: string }, { success: boolean }>(
  functions,
  'admitEventTicket',
)

const confirmCashForReservationTicket = httpsCallable<
  { qrToken: string; amountCollected?: number },
  { success: boolean }
>(functions, 'confirmCashForReservationTicket')

const recoverTicketOrder = httpsCallable<
  { orderId: string },
  { success: boolean; issued: number; ticketUrl: string }
>(functions, 'recoverTicketOrder')

const extractEventDetailsFromFlyer = httpsCallable<
  { organizationId: string; text?: string; imageUrl?: string },
  { success: boolean; extractionId: string; extraction: Record<string, unknown> }
>(functions, 'extractEventDetailsFromFlyer')

const createPromoMechanic = httpsCallable<
  {
    eventId: string
    type: string
    title: string
    description?: string
    code?: string
    reward?: string
  },
  { success: boolean; promoMechanicId: string }
>(functions, 'createPromoMechanic')

const getEventOpsWorkspace = httpsCallable<
  { eventId: string },
  EventOpsWorkspaceResult
>(functions, 'getEventOpsWorkspace')

const getEventOpsOnboardingVisuals = httpsCallable<
  { eventId: string },
  EventOpsOnboardingVisualsResult
>(functions, 'getEventOpsOnboardingVisuals')

const generateEventOpsOnboardingVisuals = httpsCallable<
  { eventId: string },
  EventOpsOnboardingVisualsResult
>(functions, 'generateEventOpsOnboardingVisuals')

const activateEventOpsPackage = httpsCallable<
  {
    eventId: string
    selectedPlan: EventOpsPlan
    paymentMode: 'merchant_collected' | 'vennuzo_controlled'
    staffAccessCode?: string
  },
  EventOpsWorkspaceResult & { chargeReference?: string }
>(functions, 'activateEventOpsPackage')

const saveEventOpsConfig = httpsCallable<
  {
    eventId: string
    selectedPlan: EventOpsPlan
    paymentMode: 'merchant_collected' | 'vennuzo_controlled'
    setupStarted: boolean
    setupComplete: boolean
    staffAccessCode?: string
  },
  EventOpsWorkspaceResult
>(functions, 'saveEventOpsConfig')

const createEventOpsInventoryItem = httpsCallable<
  {
    eventId: string
    name: string
    category: string
    costGhs: number
    sellingGhs: number
    stock: number
    linkedPackage?: string
    listed?: boolean
  },
  EventOpsWorkspaceResult
>(functions, 'createEventOpsInventoryItem')

const createEventOpsStaffCredential = httpsCallable<
  { eventId: string; name: string; role: string; station?: string },
  EventOpsWorkspaceResult
>(functions, 'createEventOpsStaffCredential')

const createEventOpsTab = httpsCallable<
  { eventId: string; staffId: string; itemId: string; customer: string; quantity: number },
  EventOpsWorkspaceResult
>(functions, 'createEventOpsTab')

const closeEventOpsTab = httpsCallable<
  { eventId: string; tabId: string; paymentMethod: string },
  EventOpsWorkspaceResult
>(functions, 'closeEventOpsTab')

const generateEventOpsReport = httpsCallable<
  { eventId: string },
  EventOpsWorkspaceResult & { reportId: string }
>(functions, 'generateEventOpsReport')

type EventOpsPlan = 'lite' | 'pro' | 'festival'
type EventOpsSetupStep = 'intro' | 'plan' | 'inventory' | 'staff' | 'payments' | 'review'
type EventOpsOrderStatus = 'open' | 'closed'

interface EventOpsInventoryItem {
  id: string
  name: string
  category: string
  costGhs: number
  sellingGhs: number
  stock: number
  linkedPackage: string
  listed: boolean
}

interface EventOpsStaffMember {
  id: string
  name: string
  role: string
  pin: string
  station: string
  active: boolean
}

interface EventOpsOrder {
  id: string
  staffId: string
  customer: string
  itemId: string
  quantity: number
  status: EventOpsOrderStatus
  paymentMethod: string
  createdAt: string
  closedAt?: string
}

interface EventOpsDraft {
  setupStarted: boolean
  setupComplete: boolean
  selectedPlan: EventOpsPlan
  staffAccessCode: string
  planPriceGhs?: number
  eventOpsPaid?: boolean
  eventOpsActivatedAt?: string | null
  eventOpsChargeReference?: string
  inventory: EventOpsInventoryItem[]
  staff: EventOpsStaffMember[]
  orders: EventOpsOrder[]
  paymentMode: 'merchant_collected' | 'vennuzo_controlled'
}

interface EventOpsOnboardingVisual {
  id: string
  title: string
  body: string
  imageUrl: string
  storagePath?: string
}

interface EventOpsWorkspaceResult {
  success: boolean
  config: {
    setupStarted: boolean
    setupComplete: boolean
    selectedPlan: EventOpsPlan
    staffAccessCode?: string
    planPriceGhs?: number
    eventOpsPaid?: boolean
    eventOpsActivatedAt?: string | null
    eventOpsChargeReference?: string
    paymentMode: 'merchant_collected' | 'vennuzo_controlled'
  }
  inventory: EventOpsInventoryItem[]
  staff: EventOpsStaffMember[]
  tabs: Array<EventOpsOrder & { totalAmount?: number }>
}

interface EventOpsOnboardingVisualsResult {
  success: boolean
  status: string
  visuals: EventOpsOnboardingVisual[]
  generationCount?: number
  generationsRemaining?: number
  updatedAt?: string | null
}

const eventOpsSteps: Array<{ id: EventOpsSetupStep; label: string }> = [
  { id: 'intro', label: 'Intro' },
  { id: 'plan', label: 'Package' },
  { id: 'inventory', label: 'Inventory' },
  { id: 'staff', label: 'Staff' },
  { id: 'payments', label: 'Payments' },
  { id: 'review', label: 'Review' },
]

const eventOpsPlanDetails: Record<EventOpsPlan, { label: string; price: string; meta: string }> = {
  lite: {
    label: 'Event Inventory Lite',
    price: 'GHS 250/event',
    meta: 'Up to 5 staff and 200 closed tabs/orders.',
  },
  pro: {
    label: 'Event Ops Pro',
    price: 'GHS 500/event',
    meta: 'Up to 15 staff, table package linkage, staff breakdowns, and PDF reports.',
  },
  festival: {
    label: 'Festival / Multi-Vendor Ops',
    price: 'From GHS 1,500/event',
    meta: 'Multiple bars, vendors, stations, custom roles, and setup support.',
  },
}

const sampleInventory: EventOpsInventoryItem[] = [
  {
    id: 'item_bottle_service',
    name: 'Moet Bottle Service',
    category: 'Drinks',
    costGhs: 620,
    sellingGhs: 950,
    stock: 24,
    linkedPackage: 'VIP Gold Table',
    listed: true,
  },
  {
    id: 'item_shisha',
    name: 'Premium Shisha',
    category: 'Experience',
    costGhs: 80,
    sellingGhs: 180,
    stock: 35,
    linkedPackage: 'Terrace Table',
    listed: true,
  },
  {
    id: 'item_platter',
    name: 'Chef Platter',
    category: 'Food',
    costGhs: 220,
    sellingGhs: 400,
    stock: 18,
    linkedPackage: 'Birthday Table',
    listed: true,
  },
]

const sampleStaff: EventOpsStaffMember[] = [
  { id: 'staff_ama', name: 'Ama Mensah', role: 'Waiter', pin: '1842', station: 'VIP', active: true },
  { id: 'staff_kojo', name: 'Kojo Annan', role: 'Bartender', pin: '5091', station: 'Main bar', active: true },
  { id: 'staff_esi', name: 'Esi Boateng', role: 'Floor lead', pin: '7720', station: 'Terrace', active: true },
]

function makeInitialEventOpsDraft(): EventOpsDraft {
  const now = new Date()
  return {
    setupStarted: false,
    setupComplete: false,
    selectedPlan: 'pro',
    staffAccessCode: '',
    planPriceGhs: eventOpsPlanDetails.pro.price.includes('500') ? 500 : 0,
    eventOpsPaid: false,
    eventOpsActivatedAt: null,
    eventOpsChargeReference: '',
    inventory: sampleInventory,
    staff: sampleStaff,
    paymentMode: 'merchant_collected',
    orders: [
      {
        id: 'tab_1001',
        staffId: 'staff_ama',
        customer: 'Table 4',
        itemId: 'item_bottle_service',
        quantity: 2,
        status: 'closed',
        paymentMethod: 'Merchant MoMo',
        createdAt: new Date(now.getTime() - 1000 * 60 * 48).toISOString(),
        closedAt: new Date(now.getTime() - 1000 * 60 * 42).toISOString(),
      },
      {
        id: 'tab_1002',
        staffId: 'staff_kojo',
        customer: 'Walk-in',
        itemId: 'item_shisha',
        quantity: 1,
        status: 'closed',
        paymentMethod: 'Cash',
        createdAt: new Date(now.getTime() - 1000 * 60 * 34).toISOString(),
        closedAt: new Date(now.getTime() - 1000 * 60 * 30).toISOString(),
      },
      {
        id: 'tab_1003',
        staffId: 'staff_esi',
        customer: 'Birthday Table',
        itemId: 'item_platter',
        quantity: 2,
        status: 'open',
        paymentMethod: 'Pending',
        createdAt: new Date(now.getTime() - 1000 * 60 * 12).toISOString(),
      },
    ],
  }
}

function getEventOpsStorageKey(organizationId: string | null, eventId: string) {
  return `vennuzo:event-ops:${organizationId || 'org'}:${eventId || 'event'}`
}

function readEventOpsDraft(organizationId: string | null, eventId: string): EventOpsDraft {
  if (typeof window === 'undefined') return makeInitialEventOpsDraft()
  try {
    const raw = window.localStorage.getItem(getEventOpsStorageKey(organizationId, eventId))
    if (!raw) return makeInitialEventOpsDraft()
    return { ...makeInitialEventOpsDraft(), ...JSON.parse(raw) } as EventOpsDraft
  } catch {
    return makeInitialEventOpsDraft()
  }
}

function writeEventOpsDraft(organizationId: string | null, eventId: string, draft: EventOpsDraft) {
  if (typeof window === 'undefined') return
  window.localStorage.setItem(getEventOpsStorageKey(organizationId, eventId), JSON.stringify(draft))
}

function normalizeStaffAccessCode(value: string) {
  return value
    .trim()
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '')
    .slice(0, 48)
}

function suggestedStaffAccessCode(event: PortalEvent | null) {
  const titleCode = normalizeStaffAccessCode(event?.title || '')
  if (titleCode.length >= 3) return titleCode
  return normalizeStaffAccessCode(event?.id || '')
}

function draftFromWorkspace(workspace: EventOpsWorkspaceResult): EventOpsDraft {
  return {
    setupStarted: workspace.config?.setupStarted === true,
    setupComplete: workspace.config?.setupComplete === true,
    selectedPlan: workspace.config?.selectedPlan || 'pro',
    staffAccessCode: workspace.config?.staffAccessCode || '',
    planPriceGhs: workspace.config?.planPriceGhs,
    eventOpsPaid: workspace.config?.eventOpsPaid === true,
    eventOpsActivatedAt: workspace.config?.eventOpsActivatedAt || null,
    eventOpsChargeReference: workspace.config?.eventOpsChargeReference || '',
    paymentMode: workspace.config?.paymentMode || 'merchant_collected',
    inventory: Array.isArray(workspace.inventory) ? workspace.inventory : [],
    staff: Array.isArray(workspace.staff) ? workspace.staff : [],
    orders: Array.isArray(workspace.tabs) ? workspace.tabs : [],
  }
}

function escapePdfText(value: string) {
  return value.replace(/[\\()]/g, (match) => `\\${match}`)
}

function buildEventOpsPdf(lines: string[]) {
  const content: string[] = [
    'q 0.05 0.09 0.16 rg 0 706 612 86 re f Q',
    'q 0.10 0.72 0.49 rg 0 702 612 4 re f Q',
    `BT /F2 20 Tf 52 756 Td (${escapePdfText(lines[0] || 'Vennuzo End-of-Event Report')}) Tj ET`,
    `BT /F1 10 Tf 52 734 Td (${escapePdfText(lines[1] || 'Event operations summary')}) Tj ET`,
  ]
  const bodyLines = lines.slice(2, 48)
  let y = 684
  bodyLines.forEach((line) => {
    const isSection = line.length > 0 && !line.includes(':') && !line.includes(' - ') && y < 675
    if (line === '') {
      y -= 12
      return
    }
    if (isSection) {
      content.push(`q 0.94 0.97 0.99 rg 44 ${y - 8} 524 24 re f Q`)
      content.push(`BT /F2 11 Tf 52 ${y} Td (${escapePdfText(line)}) Tj ET`)
      y -= 30
      return
    }
    content.push(`BT /F1 10 Tf 56 ${y} Td (${escapePdfText(line)}) Tj ET`)
    y -= 18
  })
  const text = content.join('\n')
  const objects = [
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F1 4 0 R /F2 5 0 R >> >> /Contents 6 0 R >>',
    '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>',
    '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Bold >>',
    `<< /Length ${text.length} >>\nstream\n${text}\nendstream`,
  ]
  let body = '%PDF-1.4\n'
  const offsets = [0]
  objects.forEach((object, index) => {
    offsets.push(body.length)
    body += `${index + 1} 0 obj\n${object}\nendobj\n`
  })
  const xref = body.length
  body += `xref\n0 ${objects.length + 1}\n0000000000 65535 f \n`
  offsets.slice(1).forEach((offset) => {
    body += `${String(offset).padStart(10, '0')} 00000 n \n`
  })
  body += `trailer\n<< /Size ${objects.length + 1} /Root 1 0 R >>\nstartxref\n${xref}\n%%EOF`
  return new Blob([body], { type: 'application/pdf' })
}

export function OperationsPage() {
  const { organizationId, user, profile } = usePortalSession()
  const [searchParams, setSearchParams] = useSearchParams()
  const queryEventId = searchParams.get('eventId') || ''
  const [events, setEvents] = useState<PortalEvent[]>([])
  const [selectedEventId, setSelectedEventId] = useState('')
  const [eventOpsStep, setEventOpsStep] = useState<EventOpsSetupStep>('intro')
  const [eventOpsDraft, setEventOpsDraft] = useState<EventOpsDraft>(() => makeInitialEventOpsDraft())
  const [eventOpsSyncing, setEventOpsSyncing] = useState(false)
  const [eventOpsBackendReady, setEventOpsBackendReady] = useState(false)
  const [eventOpsVisuals, setEventOpsVisuals] = useState<EventOpsOnboardingVisual[]>([])
  const [eventOpsVisualsLoading, setEventOpsVisualsLoading] = useState(false)
  const [eventOpsVisualsGenerating, setEventOpsVisualsGenerating] = useState(false)
  const [eventOpsVisualsRemaining, setEventOpsVisualsRemaining] = useState<number | null>(null)
  const [itemName, setItemName] = useState('')
  const [itemCategory, setItemCategory] = useState('Drinks')
  const [itemCost, setItemCost] = useState('0')
  const [itemSelling, setItemSelling] = useState('0')
  const [itemStock, setItemStock] = useState('1')
  const [itemPackage, setItemPackage] = useState('')
  const [staffName, setStaffName] = useState('')
  const [staffRole, setStaffRole] = useState('Waiter')
  const [staffStation, setStaffStation] = useState('')
  const [orderCustomer, setOrderCustomer] = useState('Walk-in')
  const [orderStaffId, setOrderStaffId] = useState(sampleStaff[0]?.id || '')
  const [orderItemId, setOrderItemId] = useState(sampleInventory[0]?.id || '')
  const [orderQuantity, setOrderQuantity] = useState('1')
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [message, setMessage] = useState<string | null>(null)
  const [feedUrl, setFeedUrl] = useState('')
  const [compName, setCompName] = useState('')
  const [compPhone, setCompPhone] = useState('')
  const [compEmail, setCompEmail] = useState('')
  const [compTierId, setCompTierId] = useState('')
  const [compQuantity, setCompQuantity] = useState(1)
  const [qrToken, setQrToken] = useState('')
  const [ticketResult, setTicketResult] = useState<TicketValidationResult | null>(null)
  const [recoveryOrderId, setRecoveryOrderId] = useState('')
  const [flyerText, setFlyerText] = useState('')
  const [flyerImageUrl, setFlyerImageUrl] = useState('')
  const [promoType, setPromoType] = useState('promo_code')
  const [promoTitle, setPromoTitle] = useState('')
  const [promoCode, setPromoCode] = useState('')
  const [promoReward, setPromoReward] = useState('')
  const [submitting, setSubmitting] = useState(false)
  const testerCanSkip = (user?.email || profile?.email || '').trim().toLowerCase() === 'angelonartey@hotmail.com'

  useEffect(() => {
    let cancelled = false
    if (!organizationId) return
    async function run() {
      setLoading(true)
      setError(null)
      try {
        const eventList = await listOrganizerEvents(organizationId ?? '')
        if (cancelled) return
        setEvents(eventList)
        setSelectedEventId((current) => {
          if (queryEventId && eventList.some((event) => event.id === queryEventId)) return queryEventId
          return current || eventList[0]?.id || ''
        })
      } catch (err) {
        if (!cancelled) setError(getErrorMessage(err, 'Could not load operations.'))
      } finally {
        if (!cancelled) setLoading(false)
      }
    }
    void run()
    return () => {
      cancelled = true
    }
  }, [organizationId, queryEventId])

  const selectedEvent = useMemo(
    () => events.find((item) => item.id === selectedEventId) ?? null,
    [events, selectedEventId],
  )
  const suggestedAccessCode = suggestedStaffAccessCode(selectedEvent)
  const staffAccessCode = eventOpsDraft.staffAccessCode || suggestedAccessCode
  const staffAppPath = selectedEventId ? `/staff/${encodeURIComponent(staffAccessCode || selectedEventId)}` : '/staff'
  const selectedTier = selectedEvent?.tiers.find((tier) => tier.tierId === compTierId) ?? selectedEvent?.tiers[0]
  const selectedPlan = eventOpsPlanDetails[eventOpsDraft.selectedPlan]
  const openTabs = eventOpsDraft.orders.filter((order) => order.status === 'open')
  const closedTabs = eventOpsDraft.orders.filter((order) => order.status === 'closed')
  const eventOpsRevenue = closedTabs.reduce((sum, order) => {
    const item = eventOpsDraft.inventory.find((entry) => entry.id === order.itemId)
    return sum + (item?.sellingGhs ?? 0) * order.quantity
  }, 0)
  const eventOpsCost = closedTabs.reduce((sum, order) => {
    const item = eventOpsDraft.inventory.find((entry) => entry.id === order.itemId)
    return sum + (item?.costGhs ?? 0) * order.quantity
  }, 0)
  const staffBreakdown = eventOpsDraft.staff.map((staff) => {
    const staffOrders = closedTabs.filter((order) => order.staffId === staff.id)
    const sales = staffOrders.reduce((sum, order) => {
      const item = eventOpsDraft.inventory.find((entry) => entry.id === order.itemId)
      return sum + (item?.sellingGhs ?? 0) * order.quantity
    }, 0)
    return { ...staff, orders: staffOrders.length, sales }
  })

  useEffect(() => {
    let cancelled = false
    if (!selectedEventId) {
      setEventOpsBackendReady(false)
      setEventOpsVisuals([])
      setEventOpsVisualsRemaining(null)
      return
    }
    const nextDraft = readEventOpsDraft(organizationId, selectedEventId)
    setEventOpsDraft(nextDraft)
    setEventOpsStep(nextDraft.setupComplete ? 'review' : 'intro')
    setOrderStaffId(nextDraft.staff[0]?.id || '')
    setOrderItemId(nextDraft.inventory[0]?.id || '')
    setEventOpsSyncing(true)
    getEventOpsWorkspace({ eventId: selectedEventId })
      .then((result) => {
        if (cancelled) return
        const backendDraft = draftFromWorkspace(result.data)
        const hydratedDraft =
          backendDraft.inventory.length || backendDraft.staff.length || backendDraft.orders.length || backendDraft.setupStarted
            ? backendDraft
            : nextDraft
        setEventOpsDraft(hydratedDraft)
        setEventOpsStep(hydratedDraft.setupComplete ? 'review' : 'intro')
        setOrderStaffId(hydratedDraft.staff[0]?.id || sampleStaff[0]?.id || '')
        setOrderItemId(hydratedDraft.inventory[0]?.id || sampleInventory[0]?.id || '')
        setEventOpsBackendReady(true)
      })
      .catch(() => {
        if (!cancelled) setEventOpsBackendReady(false)
      })
      .finally(() => {
        if (!cancelled) setEventOpsSyncing(false)
      })
    return () => {
      cancelled = true
    }
  }, [organizationId, selectedEventId])

  useEffect(() => {
    let cancelled = false
    if (!selectedEventId) {
      setEventOpsVisuals([])
      setEventOpsVisualsRemaining(null)
      return
    }
    setEventOpsVisualsLoading(true)
    getEventOpsOnboardingVisuals({ eventId: selectedEventId })
      .then((result) => {
        if (!cancelled) {
          setEventOpsVisuals(Array.isArray(result.data.visuals) ? result.data.visuals : [])
          setEventOpsVisualsRemaining(typeof result.data.generationsRemaining === 'number' ? result.data.generationsRemaining : null)
        }
      })
      .catch(() => {
        if (!cancelled) {
          setEventOpsVisuals([])
          setEventOpsVisualsRemaining(null)
        }
      })
      .finally(() => {
        if (!cancelled) setEventOpsVisualsLoading(false)
      })
    return () => {
      cancelled = true
    }
  }, [selectedEventId])

  useEffect(() => {
    if (!selectedEventId) return
    writeEventOpsDraft(organizationId, selectedEventId, eventOpsDraft)
  }, [eventOpsDraft, organizationId, selectedEventId])

  function updateEventOpsDraft(updater: (current: EventOpsDraft) => EventOpsDraft) {
    setEventOpsDraft((current) => updater(current))
  }

  function applyEventOpsWorkspace(workspace: EventOpsWorkspaceResult) {
    const nextDraft = draftFromWorkspace(workspace)
    setEventOpsDraft(nextDraft)
    setOrderStaffId(nextDraft.staff[0]?.id || sampleStaff[0]?.id || '')
    setOrderItemId(nextDraft.inventory[0]?.id || sampleInventory[0]?.id || '')
    setEventOpsBackendReady(true)
  }

  async function persistEventOpsConfig(nextDraft: EventOpsDraft) {
    if (!selectedEventId) return
    setEventOpsSyncing(true)
    try {
      const result = await saveEventOpsConfig({
        eventId: selectedEventId,
        selectedPlan: nextDraft.selectedPlan,
        paymentMode: nextDraft.paymentMode,
        setupStarted: nextDraft.setupStarted,
        setupComplete: nextDraft.setupComplete,
        staffAccessCode: nextDraft.staffAccessCode || suggestedAccessCode,
      })
      applyEventOpsWorkspace(result.data)
    } catch (err) {
      setEventOpsBackendReady(false)
      setError(getErrorMessage(err, 'Saved locally. Event Ops backend sync failed.'))
    } finally {
      setEventOpsSyncing(false)
    }
  }

  async function handleGenerateEventOpsVisuals() {
    if (!selectedEventId) return
    setEventOpsVisualsGenerating(true)
    try {
      await runAction(async () => {
        const result = await generateEventOpsOnboardingVisuals({ eventId: selectedEventId })
        setEventOpsVisuals(Array.isArray(result.data.visuals) ? result.data.visuals : [])
        setEventOpsVisualsRemaining(typeof result.data.generationsRemaining === 'number' ? result.data.generationsRemaining : null)
        setMessage('Gemini onboarding visuals generated for this Event Ops setup.')
      })
    } finally {
      setEventOpsVisualsGenerating(false)
    }
  }

  async function handleActivateEventOps() {
    if (!selectedEventId) return
    await runAction(async () => {
      const result = await activateEventOpsPackage({
        eventId: selectedEventId,
        selectedPlan: eventOpsDraft.selectedPlan,
        paymentMode: eventOpsDraft.paymentMode,
        staffAccessCode,
      })
      applyEventOpsWorkspace(result.data)
      setEventOpsStep('review')
      setMessage(
        result.data.chargeReference
          ? `Event Ops activated. Wallet charge reference: ${result.data.chargeReference}`
          : 'Event Ops is already activated for this event.',
      )
    })
  }

  function goToNextEventOpsStep() {
    const currentIndex = eventOpsSteps.findIndex((step) => step.id === eventOpsStep)
    const next = eventOpsSteps[Math.min(currentIndex + 1, eventOpsSteps.length - 1)]
    if (!next) return
    setEventOpsStep(next.id)
    if (next.id === 'review') {
      const nextDraft = { ...eventOpsDraft, setupStarted: true, setupComplete: true }
      setEventOpsDraft(nextDraft)
      void persistEventOpsConfig(nextDraft)
    }
  }

  async function handleAddInventoryItem(e: FormEvent) {
    e.preventDefault()
    const nameValue = itemName.trim()
    if (!nameValue) return
    const nextItem: EventOpsInventoryItem = {
      id: `item_${Date.now()}`,
      name: nameValue,
      category: itemCategory.trim() || 'General',
      costGhs: Number(itemCost || 0),
      sellingGhs: Number(itemSelling || 0),
      stock: Number(itemStock || 1),
      linkedPackage: itemPackage.trim(),
      listed: true,
    }
    if (selectedEventId) {
      setEventOpsSyncing(true)
      try {
        const result = await createEventOpsInventoryItem({
          eventId: selectedEventId,
          name: nextItem.name,
          category: nextItem.category,
          costGhs: nextItem.costGhs,
          sellingGhs: nextItem.sellingGhs,
          stock: nextItem.stock,
          linkedPackage: nextItem.linkedPackage || undefined,
          listed: nextItem.listed,
        })
        applyEventOpsWorkspace(result.data)
        setMessage('Inventory item added to Firestore and the event catalog.')
      } catch (err) {
        updateEventOpsDraft((current) => ({ ...current, inventory: [nextItem, ...current.inventory] }))
        setEventOpsBackendReady(false)
        setError(getErrorMessage(err, 'Saved locally. Could not sync inventory yet.'))
      } finally {
        setEventOpsSyncing(false)
      }
    } else {
      updateEventOpsDraft((current) => ({ ...current, inventory: [nextItem, ...current.inventory] }))
      setMessage('Inventory item added to the local event catalog.')
    }
    setItemName('')
    setItemCategory('Drinks')
    setItemCost('0')
    setItemSelling('0')
    setItemStock('1')
    setItemPackage('')
  }

  async function handleAddStaff(e: FormEvent) {
    e.preventDefault()
    const nameValue = staffName.trim()
    if (!nameValue) return
    const nextStaff: EventOpsStaffMember = {
      id: `staff_${Date.now()}`,
      name: nameValue,
      role: staffRole.trim() || 'Waiter',
      station: staffStation.trim() || 'Floor',
      pin: String(Math.floor(1000 + Math.random() * 9000)),
      active: true,
    }
    if (selectedEventId) {
      setEventOpsSyncing(true)
      try {
        const result = await createEventOpsStaffCredential({
          eventId: selectedEventId,
          name: nextStaff.name,
          role: nextStaff.role,
          station: nextStaff.station,
        })
        applyEventOpsWorkspace(result.data)
        setMessage(`${nextStaff.name} can now sign in with their staff PIN.`)
      } catch (err) {
        updateEventOpsDraft((current) => ({ ...current, staff: [nextStaff, ...current.staff] }))
        setEventOpsBackendReady(false)
        setError(getErrorMessage(err, 'Saved locally. Could not sync staff credential yet.'))
      } finally {
        setEventOpsSyncing(false)
      }
    } else {
      updateEventOpsDraft((current) => ({ ...current, staff: [nextStaff, ...current.staff] }))
      setMessage(`${nextStaff.name} can now sign in with PIN ${nextStaff.pin}.`)
    }
    setStaffName('')
    setStaffRole('Waiter')
    setStaffStation('')
    setOrderStaffId((current) => current || nextStaff.id)
  }

  async function handleCreateTab(e: FormEvent) {
    e.preventDefault()
    if (!orderStaffId || !orderItemId) return
    const nextOrder: EventOpsOrder = {
      id: `tab_${Date.now()}`,
      staffId: orderStaffId,
      customer: orderCustomer.trim() || 'Walk-in',
      itemId: orderItemId,
      quantity: Number(orderQuantity || 1),
      status: 'open',
      paymentMethod: 'Pending',
      createdAt: new Date().toISOString(),
    }
    if (selectedEventId) {
      setEventOpsSyncing(true)
      try {
        const result = await createEventOpsTab({
          eventId: selectedEventId,
          staffId: orderStaffId,
          itemId: orderItemId,
          customer: nextOrder.customer,
          quantity: nextOrder.quantity,
        })
        applyEventOpsWorkspace(result.data)
        setMessage('Open tab recorded in Firestore. Organizer push notification queued when a token is available.')
      } catch (err) {
        updateEventOpsDraft((current) => ({ ...current, orders: [nextOrder, ...current.orders] }))
        setEventOpsBackendReady(false)
        setError(getErrorMessage(err, 'Saved locally. Could not sync the open tab yet.'))
      } finally {
        setEventOpsSyncing(false)
      }
    } else {
      updateEventOpsDraft((current) => ({ ...current, orders: [nextOrder, ...current.orders] }))
      setMessage('Open tab recorded locally. Admins, bartenders, and owners would receive a push notification here.')
    }
    setOrderCustomer('Walk-in')
    setOrderQuantity('1')
  }

  async function closeTab(orderId: string, paymentMethod: string) {
    if (selectedEventId && eventOpsBackendReady) {
      setEventOpsSyncing(true)
      try {
        const result = await closeEventOpsTab({ eventId: selectedEventId, tabId: orderId, paymentMethod })
        applyEventOpsWorkspace(result.data)
        setMessage('Tab closed in Firestore after merchant-collected payment.')
        return
      } catch (err) {
        setEventOpsBackendReady(false)
        setError(getErrorMessage(err, 'Closed locally. Could not sync the tab close yet.'))
      } finally {
        setEventOpsSyncing(false)
      }
    }
    updateEventOpsDraft((current) => ({
      ...current,
      orders: current.orders.map((order) =>
        order.id === orderId
          ? { ...order, status: 'closed', paymentMethod, closedAt: new Date().toISOString() }
          : order,
      ),
    }))
    setMessage('Tab closed after merchant-collected payment.')
  }

  async function downloadEventOpsReport() {
    let backendReportId = ''
    if (selectedEventId && eventOpsBackendReady) {
      setEventOpsSyncing(true)
      try {
        const result = await generateEventOpsReport({ eventId: selectedEventId })
        backendReportId = result.data.reportId
        applyEventOpsWorkspace(result.data)
      } catch (err) {
        setEventOpsBackendReady(false)
        setError(getErrorMessage(err, 'Generating a local PDF. Could not save the report record yet.'))
      } finally {
        setEventOpsSyncing(false)
      }
    }
    const lines = [
      'Vennuzo End-of-Event Report',
      selectedEvent?.title || 'Selected event',
      `Generated: ${new Date().toLocaleString()}`,
      backendReportId ? `Report ID: ${backendReportId}` : 'Report mode: Local draft',
      `Package: ${selectedPlan.label} (${selectedPlan.price})`,
      `Activation: ${eventOpsDraft.eventOpsPaid ? 'Paid and active' : 'Not activated'}`,
      `Payment mode: Merchant-collected`,
      '',
      'Executive summary',
      `Closed tabs: ${closedTabs.length}`,
      `Open tabs: ${openTabs.length}`,
      `Recorded sales: ${formatMoney(eventOpsRevenue)}`,
      `Estimated cost: ${formatMoney(eventOpsCost)}`,
      `Estimated margin: ${formatMoney(eventOpsRevenue - eventOpsCost)}`,
      `Margin rate: ${eventOpsRevenue > 0 ? `${Math.round(((eventOpsRevenue - eventOpsCost) / eventOpsRevenue) * 100)}%` : '0%'}`,
      '',
      'Staff breakdown',
      ...staffBreakdown.map((staff) => `${staff.name} - ${staff.orders} closed tabs - ${formatMoney(staff.sales)}`),
      '',
      'Inventory',
      ...eventOpsDraft.inventory.map((item) => `${item.name} - ${item.stock} in stock - ${formatMoney(item.sellingGhs)} selling price`),
    ].slice(0, 38)
    const blob = buildEventOpsPdf(lines)
    const url = URL.createObjectURL(blob)
    const anchor = document.createElement('a')
    anchor.href = url
    anchor.download = `vennuzo-end-of-event-${(selectedEvent?.title || 'report').toLowerCase().replace(/[^a-z0-9]+/g, '-')}.pdf`
    anchor.click()
    URL.revokeObjectURL(url)
    setMessage('End-of-event PDF report generated.')
  }

  async function runAction(action: () => Promise<void>) {
    if (submitting) return
    setSubmitting(true)
    setError(null)
    setMessage(null)
    try {
      await action()
    } catch (err) {
      setError(getErrorMessage(err, 'Action failed.'))
    } finally {
      setSubmitting(false)
    }
  }

  function handleSelectEvent(eventId: string) {
    setSelectedEventId(eventId)
    if (eventId) {
      setSearchParams({ eventId })
    } else {
      setSearchParams({})
    }
  }

  async function handleFeedLink() {
    if (!selectedEventId) return
    await runAction(async () => {
      const result = await createOrganizerFeedLink({ eventId: selectedEventId })
      setFeedUrl(result.data.url)
      setMessage('Organizer feed link is ready.')
    })
  }

  async function handleComp(e: FormEvent) {
    e.preventDefault()
    if (!selectedEventId || !selectedTier) return
    await runAction(async () => {
      const result = await issueComplimentaryTickets({
        eventId: selectedEventId,
        selections: { [selectedTier.tierId]: compQuantity },
        buyerName: compName.trim(),
        buyerPhone: compPhone.trim(),
        buyerEmail: compEmail.trim(),
      })
      setMessage(`Comp tickets issued: ${result.data.ticketUrl}`)
      setCompName('')
      setCompPhone('')
      setCompEmail('')
      setCompQuantity(1)
    })
  }

  async function handleValidate(e: FormEvent) {
    e.preventDefault()
    await runAction(async () => {
      const result = await validateEventTicket({ qrToken: qrToken.trim() })
      setTicketResult(result.data)
      setMessage('Ticket validated.')
    })
  }

  async function handleRecover(e: FormEvent) {
    e.preventDefault()
    await runAction(async () => {
      const result = await recoverTicketOrder({ orderId: recoveryOrderId.trim() })
      setMessage(`Recovered ${result.data.issued} tickets: ${result.data.ticketUrl}`)
      setRecoveryOrderId('')
    })
  }

  async function handleExtract(e: FormEvent) {
    e.preventDefault()
    if (!organizationId) return
    await runAction(async () => {
      const result = await extractEventDetailsFromFlyer({
        organizationId,
        text: flyerText.trim() || undefined,
        imageUrl: flyerImageUrl.trim() || undefined,
      })
      setMessage(`Extraction saved: ${result.data.extractionId}`)
    })
  }

  async function handlePromo(e: FormEvent) {
    e.preventDefault()
    if (!selectedEventId) return
    await runAction(async () => {
      const result = await createPromoMechanic({
        eventId: selectedEventId,
        type: promoType,
        title: promoTitle.trim() || promoType.replace(/_/g, ' '),
        code: promoCode.trim() || undefined,
        reward: promoReward.trim() || undefined,
      })
      setMessage(`Promo created: ${result.data.promoMechanicId}`)
      setPromoTitle('')
      setPromoCode('')
      setPromoReward('')
    })
  }

  if (loading) return <div className="page-loader">Loading...</div>

  return (
    <div className="dashboard-stack">
      <section className="page-hero page-hero--events page-hero--organizer-ops">
        <div className="page-hero__content">
          <p className="eyebrow">Operations</p>
          <h2>Run doors, feeds, comps, recovery, and promo mechanics.</h2>
          <div className="hero-chip-row">
            <span>{selectedEvent?.title || 'Select event'}</span>
            <span>QR validation</span>
            <span>Public feed</span>
          </div>
        </div>
        <div className="page-hero__panel">
          <label className="search-field">
            <span>Event</span>
            <select value={selectedEventId} onChange={(e) => handleSelectEvent(e.target.value)}>
              {events.map((event) => (
                <option key={event.id} value={event.id}>{event.title}</option>
              ))}
            </select>
          </label>
          <Link className="button button--secondary" to="/studio/orders">Orders</Link>
        </div>
      </section>

      {error && <p className="checkout__error">{error}</p>}
      {message && <p className="checkout__info">{message}</p>}

      <section className="event-ops-shell">
        <div className="event-ops-intro">
          <div>
            <p className="eyebrow">Event Ops</p>
            <h3>Inventory, waiter tabs, merchant-collected payments, and end-of-event reports.</h3>
            <p>
              Set up what you sell, create waiter credentials, record open tabs, close tabs after customers pay,
              and generate a staff-by-staff report when the event ends.
            </p>
          </div>
          <div className="event-ops-intro__actions">
            <span className={`event-ops-sync ${eventOpsBackendReady ? 'event-ops-sync--live' : ''}`}>
              {eventOpsSyncing ? 'Syncing...' : eventOpsBackendReady ? 'Firestore live' : 'Local draft'}
            </span>
            <Link
              className="button button--secondary"
              to={selectedEventId ? `/staff/${selectedEventId}` : '/staff'}
              target="_blank"
            >
              Staff Mode
            </Link>
            <Link className="button button--secondary" to="/studio/team">
              <Users size={16} aria-hidden />
              Team
            </Link>
            <button
              className="button button--primary"
              onClick={() => {
                const nextDraft = { ...eventOpsDraft, setupStarted: true }
                setEventOpsDraft(nextDraft)
                void persistEventOpsConfig(nextDraft)
                if (selectedEventId && eventOpsVisuals.length === 0 && !eventOpsVisualsGenerating) {
                  void handleGenerateEventOpsVisuals()
                }
                setEventOpsStep('intro')
              }}
              type="button"
            >
              <Sparkles size={16} aria-hidden />
              Setup Event Ops
            </button>
            {testerCanSkip && (
              <button
                className="button button--secondary"
                onClick={() => {
                  const nextDraft = { ...eventOpsDraft, setupStarted: true, setupComplete: true }
                  setEventOpsDraft(nextDraft)
                  void persistEventOpsConfig(nextDraft)
                  setEventOpsStep('review')
                }}
                type="button"
              >
                Skip setup
              </button>
            )}
          </div>
        </div>

        <div className="event-ops-kpi-grid">
          <div className="event-ops-kpi">
            <ReceiptText size={18} aria-hidden />
            <span>Closed tabs</span>
            <strong>{closedTabs.length}</strong>
          </div>
          <div className="event-ops-kpi">
            <Banknote size={18} aria-hidden />
            <span>Recorded sales</span>
            <strong>{formatMoney(eventOpsRevenue)}</strong>
          </div>
          <div className="event-ops-kpi">
            <Users size={18} aria-hidden />
            <span>Staff</span>
            <strong>{eventOpsDraft.staff.length}</strong>
          </div>
          <div className="event-ops-kpi">
            <Boxes size={18} aria-hidden />
            <span>Catalog items</span>
            <strong>{eventOpsDraft.inventory.length}</strong>
          </div>
        </div>

        <div className="event-ops-workbench">
          <aside className="event-ops-steps" aria-label="Event Ops setup steps">
            {eventOpsSteps.map((step) => (
              <button
                className={`event-ops-step${eventOpsStep === step.id ? ' event-ops-step--active' : ''}`}
                key={step.id}
                onClick={() => setEventOpsStep(step.id)}
                type="button"
              >
                <span>{eventOpsSteps.findIndex((item) => item.id === step.id) + 1}</span>
                <strong>{step.label}</strong>
              </button>
            ))}
          </aside>

          <div className="event-ops-panel">
            {eventOpsStep === 'intro' && (
              <div className="event-ops-step-panel">
                <div className="panel__header">
                  <div>
                    <p className="eyebrow">Gemini visual intro</p>
                    <h3>How Event Ops works</h3>
                  </div>
                  <button
                    className="button button--secondary"
                    disabled={
                      !selectedEventId ||
                      eventOpsVisualsGenerating ||
                      submitting ||
                      eventOpsVisualsRemaining === 0
                    }
                    onClick={() => void handleGenerateEventOpsVisuals()}
                    type="button"
                  >
                    <Sparkles size={16} aria-hidden />
                    {eventOpsVisuals.length ? 'Regenerate visuals' : 'Generate visuals'}
                  </button>
                </div>
                {eventOpsVisualsRemaining !== null && (
                  <p className="text-subtle">
                    {eventOpsVisualsRemaining} included Gemini visual generation{eventOpsVisualsRemaining === 1 ? '' : 's'} remaining for this event.
                  </p>
                )}
                {eventOpsVisualsGenerating && (
                  <div className="event-ops-visual-status">
                    <Sparkles size={18} aria-hidden />
                    <span>Gemini is creating the onboarding graphics for this event. This can take a few minutes.</span>
                  </div>
                )}
                {eventOpsVisuals.length > 0 ? (
                  <div className="event-ops-visual-grid" aria-busy={eventOpsVisualsGenerating}>
                    {eventOpsVisuals.map((visual, index) => (
                      <article className="event-ops-visual-card" key={visual.id || visual.imageUrl}>
                        <img alt={`${visual.title} onboarding visual`} src={visual.imageUrl} />
                        <div>
                          <span>Step {index + 1}</span>
                          <h4>{visual.title}</h4>
                          <p>{visual.body}</p>
                        </div>
                      </article>
                    ))}
                  </div>
                ) : (
                  <>
                    <div className="event-ops-visual-empty">
                      <Sparkles size={22} aria-hidden />
                      <div>
                        <strong>
                          {eventOpsVisualsLoading ? 'Checking for Gemini visuals...' : 'Generate the Gemini-created intro'}
                        </strong>
                        <p>
                          The onboarding should show custom graphics for this event: command center, staff app,
                          merchant-collected payments, and end-of-event reporting.
                        </p>
                      </div>
                    </div>
                    <div className="event-ops-story-grid">
                      {[
                        ['Inventory', 'Create every bottle, food item, add-on, and table package item you want to sell.'],
                        ['Catalog', 'Choose what appears on the event hub for customers, waiters, or vendors to order.'],
                        ['Staff app', 'Give waiters special credentials so they see a focused order-taking app.'],
                        ['Close tabs', 'Vendors collect cash, MoMo, card, or bank their own way, then close the tab.'],
                        ['Report', 'Generate the end-of-event PDF with sales, stock, staff, and category breakdowns.'],
                      ].map(([title, body]) => (
                        <div className="event-ops-story-card" key={title}>
                          <span>{title}</span>
                          <p>{body}</p>
                        </div>
                      ))}
                    </div>
                  </>
                )}
                <div className="event-ops-staff-preview">
                  <div className="event-ops-phone">
                    <div className="event-ops-phone__top">Vennuzo Staff</div>
                    <button type="button">New order</button>
                    <button type="button">Open tabs</button>
                    <button type="button">Close paid tab</button>
                    <button type="button">My sales</button>
                  </div>
                  <div>
                    <h4>Separate waiter experience</h4>
                    <p>
                      Staff credentials do not open the organizer Studio. They open a focused order app for taking
                      orders, viewing assigned tabs, and closing paid tabs.
                    </p>
                  </div>
                </div>
                <div className="hero-actions">
                  <button className="button button--primary" onClick={goToNextEventOpsStep} type="button">
                    Continue
                  </button>
                  {testerCanSkip && (
                    <button
                      className="button button--secondary"
                      onClick={() => {
                        const nextDraft = { ...eventOpsDraft, setupStarted: true, setupComplete: true }
                        setEventOpsDraft(nextDraft)
                        void persistEventOpsConfig(nextDraft)
                        setEventOpsStep('review')
                      }}
                      type="button"
                    >
                      Skip to review
                    </button>
                  )}
                </div>
              </div>
            )}

            {eventOpsStep === 'plan' && (
              <div className="event-ops-step-panel">
                <div className="panel__header">
                  <div>
                    <p className="eyebrow">Pricing</p>
                    <h3>Pick the event operations package</h3>
                  </div>
                </div>
                <div className="event-ops-plan-grid">
                  {(Object.keys(eventOpsPlanDetails) as EventOpsPlan[]).map((plan) => (
                    <button
                      className={`event-ops-plan${eventOpsDraft.selectedPlan === plan ? ' event-ops-plan--selected' : ''}`}
                      key={plan}
                      onClick={() => {
                        const nextDraft = { ...eventOpsDraft, selectedPlan: plan }
                        setEventOpsDraft(nextDraft)
                        void persistEventOpsConfig(nextDraft)
                      }}
                      type="button"
                    >
                      <strong>{eventOpsPlanDetails[plan].label}</strong>
                      <span>{eventOpsPlanDetails[plan].price}</span>
                      <p>{eventOpsPlanDetails[plan].meta}</p>
                    </button>
                  ))}
                </div>
                <div className="event-ops-note">
                  <CheckCircle2 size={18} aria-hidden />
                  <p>Billing plans stay removed. This is priced per event because the value is operational, not subscription access.</p>
                </div>
                <button className="button button--primary" onClick={goToNextEventOpsStep} type="button">
                  Continue
                </button>
              </div>
            )}

            {eventOpsStep === 'inventory' && (
              <div className="event-ops-step-panel">
                <div className="panel__header">
                  <div>
                    <p className="eyebrow">Inventory</p>
                    <h3>Create what this event can sell</h3>
                  </div>
                </div>
                <form className="event-ops-form" onSubmit={handleAddInventoryItem}>
                  <label>
                    Item
                    <input value={itemName} onChange={(e) => setItemName(e.target.value)} placeholder="Don Julio 1942" required />
                  </label>
                  <label>
                    Category
                    <select value={itemCategory} onChange={(e) => setItemCategory(e.target.value)}>
                      <option>Drinks</option>
                      <option>Food</option>
                      <option>Experience</option>
                      <option>Table package</option>
                      <option>Merch</option>
                    </select>
                  </label>
                  <label>
                    Cost price
                    <input min={0} type="number" value={itemCost} onChange={(e) => setItemCost(e.target.value)} />
                  </label>
                  <label>
                    Selling price
                    <input min={0} type="number" value={itemSelling} onChange={(e) => setItemSelling(e.target.value)} />
                  </label>
                  <label>
                    Stock
                    <input min={0} type="number" value={itemStock} onChange={(e) => setItemStock(e.target.value)} />
                  </label>
                  <label>
                    Linked package
                    <input value={itemPackage} onChange={(e) => setItemPackage(e.target.value)} placeholder="VIP Gold Table" />
                  </label>
                  <button className="button button--primary" type="submit">
                    <Plus size={16} aria-hidden />
                    Add item
                  </button>
                </form>
                <div className="event-ops-table-wrap">
                  <table className="orders-table">
                    <thead>
                      <tr>
                        <th>Item</th>
                        <th>Category</th>
                        <th>Cost</th>
                        <th>Selling</th>
                        <th>Stock</th>
                        <th>Hub</th>
                      </tr>
                    </thead>
                    <tbody>
                      {eventOpsDraft.inventory.map((item) => (
                        <tr key={item.id}>
                          <td><strong>{item.name}</strong><br /><span className="cell-muted">{item.linkedPackage || 'No package link'}</span></td>
                          <td>{item.category}</td>
                          <td>{formatMoney(item.costGhs)}</td>
                          <td>{formatMoney(item.sellingGhs)}</td>
                          <td>{item.stock}</td>
                          <td>{item.listed ? 'Listed' : 'Hidden'}</td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                </div>
                <button className="button button--primary" onClick={goToNextEventOpsStep} type="button">
                  Continue
                </button>
              </div>
            )}

            {eventOpsStep === 'staff' && (
              <div className="event-ops-step-panel">
                <div className="panel__header">
                  <div>
                    <p className="eyebrow">Staff</p>
                    <h3>Create waiter credentials</h3>
                  </div>
                </div>
                <div className="event-ops-note event-ops-access-code">
                  <CheckCircle2 size={18} aria-hidden />
                  <div>
                    <strong>Staff app code</strong>
                    <p>Waiters can use this memorable event code with their staff PIN.</p>
                    <label>
                      Event code
                      <input
                        value={staffAccessCode}
                        onBlur={() => void persistEventOpsConfig({ ...eventOpsDraft, staffAccessCode })}
                        onChange={(e) => {
                          setEventOpsDraft({
                            ...eventOpsDraft,
                            staffAccessCode: normalizeStaffAccessCode(e.target.value),
                          })
                        }}
                        placeholder="map-night"
                      />
                    </label>
                    <Link className="button button--secondary" to={staffAppPath} target="_blank" rel="noopener noreferrer">
                      Open staff app
                    </Link>
                  </div>
                </div>
                <form className="event-ops-form" onSubmit={handleAddStaff}>
                  <label>
                    Name
                    <input value={staffName} onChange={(e) => setStaffName(e.target.value)} placeholder="Akua Owusu" required />
                  </label>
                  <label>
                    Role
                    <select value={staffRole} onChange={(e) => setStaffRole(e.target.value)}>
                      <option>Waiter</option>
                      <option>Bartender</option>
                      <option>Floor lead</option>
                      <option>Owner</option>
                      <option>Vendor</option>
                    </select>
                  </label>
                  <label>
                    Station
                    <input value={staffStation} onChange={(e) => setStaffStation(e.target.value)} placeholder="VIP / Main bar" />
                  </label>
                  <button className="button button--primary" type="submit">
                    <UserPlus size={16} aria-hidden />
                    Create credential
                  </button>
                </form>
                <div className="event-ops-staff-grid">
                  {eventOpsDraft.staff.map((staff) => (
                    <div className="event-ops-staff-card" key={staff.id}>
                      <strong>{staff.name}</strong>
                      <span>{staff.role} · {staff.station}</span>
                      <small>PIN {staff.pin}</small>
                      <Link
                        className="button button--secondary"
                        to={staffAppPath}
                        target="_blank"
                        rel="noopener noreferrer"
                      >
                        Open staff app
                      </Link>
                    </div>
                  ))}
                </div>
                <button className="button button--primary" onClick={goToNextEventOpsStep} type="button">
                  Continue
                </button>
              </div>
            )}

            {eventOpsStep === 'payments' && (
              <div className="event-ops-step-panel">
                <div className="panel__header">
                  <div>
                    <p className="eyebrow">Payments</p>
                    <h3>Merchant-collected mode is active</h3>
                  </div>
                </div>
                <div className="event-ops-payment-grid">
                  <button
                    className="event-ops-payment event-ops-payment--selected"
                    onClick={() => {
                      const nextDraft = { ...eventOpsDraft, paymentMode: 'merchant_collected' as const }
                      setEventOpsDraft(nextDraft)
                      void persistEventOpsConfig(nextDraft)
                    }}
                    type="button"
                  >
                    <Banknote size={22} aria-hidden />
                    <strong>Merchant-collected</strong>
                    <p>Vendors collect cash, MoMo, card, or transfer their own way. Staff close the tab when it is paid.</p>
                  </button>
                  <button className="event-ops-payment event-ops-payment--disabled" disabled type="button">
                    <Lock size={22} aria-hidden />
                    <strong>Vennuzo-controlled</strong>
                    <p>Hubtel checkout and automatic reconciliation for event inventory orders. Coming soon.</p>
                  </button>
                </div>
                <button className="button button--primary" onClick={goToNextEventOpsStep} type="button">
                  Continue
                </button>
              </div>
            )}

            {eventOpsStep === 'review' && (
              <div className="event-ops-step-panel">
                <div className="panel__header">
                  <div>
                    <p className="eyebrow">Run event</p>
                    <h3>Staff orders, close tabs, and reports</h3>
                  </div>
                  <button className="button button--secondary" onClick={() => void downloadEventOpsReport()} type="button">
                    <Download size={16} aria-hidden />
                    End-of-event PDF
                  </button>
                </div>
                <div className={`event-ops-activation${eventOpsDraft.eventOpsPaid ? ' event-ops-activation--paid' : ''}`}>
                  <div>
                    <span>{eventOpsDraft.eventOpsPaid ? 'Activated' : 'Paid activation'}</span>
                    <strong>{selectedPlan.label}</strong>
                    <p>
                      {eventOpsDraft.eventOpsPaid
                        ? `This event is activated${eventOpsDraft.eventOpsChargeReference ? ` with reference ${eventOpsDraft.eventOpsChargeReference}` : ''}.`
                        : `Charge ${selectedPlan.price} from the services wallet before running paid Event Ops for this event.`}
                    </p>
                  </div>
                  <button
                    className={eventOpsDraft.eventOpsPaid ? 'button button--secondary' : 'button button--primary'}
                    disabled={!selectedEventId || submitting || eventOpsDraft.eventOpsPaid}
                    onClick={() => void handleActivateEventOps()}
                    type="button"
                  >
                    {eventOpsDraft.eventOpsPaid ? 'Paid' : 'Activate package'}
                  </button>
                </div>
                <form className="event-ops-form" onSubmit={handleCreateTab}>
                  <label>
                    Customer/tab
                    <input value={orderCustomer} onChange={(e) => setOrderCustomer(e.target.value)} />
                  </label>
                  <label>
                    Staff
                    <select value={orderStaffId} onChange={(e) => setOrderStaffId(e.target.value)}>
                      {eventOpsDraft.staff.map((staff) => <option key={staff.id} value={staff.id}>{staff.name}</option>)}
                    </select>
                  </label>
                  <label>
                    Item
                    <select value={orderItemId} onChange={(e) => setOrderItemId(e.target.value)}>
                      {eventOpsDraft.inventory.map((item) => <option key={item.id} value={item.id}>{item.name}</option>)}
                    </select>
                  </label>
                  <label>
                    Quantity
                    <input min={1} type="number" value={orderQuantity} onChange={(e) => setOrderQuantity(e.target.value)} />
                  </label>
                  <button className="button button--primary" disabled={!orderStaffId || !orderItemId} type="submit">
                    <Plus size={16} aria-hidden />
                    Open tab
                  </button>
                </form>
                <div className="event-ops-run-grid">
                  <div>
                    <h4>Open tabs</h4>
                    {openTabs.length === 0 ? (
                      <p className="text-subtle">No open tabs.</p>
                    ) : openTabs.map((order) => {
                      const item = eventOpsDraft.inventory.find((entry) => entry.id === order.itemId)
                      const staff = eventOpsDraft.staff.find((entry) => entry.id === order.staffId)
                      return (
                        <div className="event-ops-tab-card" key={order.id}>
                          <strong>{order.customer}</strong>
                          <span>{item?.name || 'Item'} x {order.quantity} · {staff?.name || 'Staff'}</span>
                          <small>{formatMoney((item?.sellingGhs ?? 0) * order.quantity)}</small>
                          <div className="hero-actions">
                            <button className="button button--secondary" onClick={() => void closeTab(order.id, 'Cash')} type="button">Cash</button>
                            <button className="button button--secondary" onClick={() => void closeTab(order.id, 'Merchant MoMo')} type="button">MoMo</button>
                          </div>
                        </div>
                      )
                    })}
                  </div>
                  <div>
                    <h4>Staff sales breakdown</h4>
                    {staffBreakdown.map((staff) => (
                      <div className="event-ops-breakdown-row" key={staff.id}>
                        <span>{staff.name}</span>
                        <strong>{formatMoney(staff.sales)}</strong>
                        <small>{staff.orders} closed tabs</small>
                      </div>
                    ))}
                  </div>
                </div>
              </div>
            )}
          </div>
        </div>
      </section>

      <section className="content-grid">
        <article className="panel">
          <div className="panel__header">
            <div>
              <p className="eyebrow">Shared feed</p>
              <h3>RSVP and ticket list</h3>
            </div>
          </div>
          <button className="button button--primary" disabled={!selectedEventId || submitting} onClick={handleFeedLink} type="button">
            Create feed link
          </button>
          {feedUrl && (
            <p className="text-subtle" style={{ wordBreak: 'break-all' }}>
              {feedUrl}
            </p>
          )}
        </article>

        <article className="panel">
          <div className="panel__header">
            <div>
              <p className="eyebrow">Complimentary</p>
              <h3>Issue free tickets</h3>
            </div>
          </div>
          <form className="checkout__form" onSubmit={handleComp}>
            <label className="checkout__label">
              Tier
              <select className="checkout__input" value={compTierId} onChange={(e) => setCompTierId(e.target.value)}>
                {selectedEvent?.tiers.map((tier) => (
                  <option key={tier.tierId} value={tier.tierId}>{tier.name}</option>
                ))}
              </select>
            </label>
            <label className="checkout__label">
              Name
              <input className="checkout__input" value={compName} onChange={(e) => setCompName(e.target.value)} required />
            </label>
            <label className="checkout__label">
              Phone
              <input className="checkout__input" value={compPhone} onChange={(e) => setCompPhone(e.target.value)} required />
            </label>
            <label className="checkout__label">
              Email
              <input className="checkout__input" type="email" value={compEmail} onChange={(e) => setCompEmail(e.target.value)} required />
            </label>
            <label className="checkout__label">
              Quantity
              <input className="checkout__input" min={1} max={20} type="number" value={compQuantity} onChange={(e) => setCompQuantity(Number(e.target.value || 1))} />
            </label>
            <button className="button button--primary" disabled={submitting || !compName.trim() || !compPhone.trim() || !compEmail.trim()} type="submit">
              Issue tickets
            </button>
          </form>
        </article>
      </section>

      <section className="content-grid">
        <article className="panel">
          <div className="panel__header">
            <div>
              <p className="eyebrow">Door</p>
              <h3>Validate QR token</h3>
            </div>
          </div>
          <form className="checkout__form" onSubmit={handleValidate}>
            <label className="checkout__label">
              QR token
              <input className="checkout__input" value={qrToken} onChange={(e) => setQrToken(e.target.value)} required />
            </label>
            <button className="button button--primary" disabled={submitting || !qrToken.trim()} type="submit">
              Validate
            </button>
          </form>
          {ticketResult && (
            <div className="empty-card" style={{ marginTop: '1rem' }}>
              <h4>{ticketResult.attendeeName}</h4>
              <p>{ticketResult.eventTitle} · {ticketResult.tierName}</p>
              <p>{ticketResult.paymentStatus} · {ticketResult.ticketStatus} · {ticketResult.admitted ? 'admitted' : 'not admitted'}</p>
              {ticketResult.requiresCash && <p>Collect {formatMoney(ticketResult.amountDue)}</p>}
              <div className="hero-actions">
                <button className="button button--secondary" disabled={submitting} onClick={() => void runAction(async () => {
                  await admitEventTicket({ qrToken: qrToken.trim() })
                  setMessage('Ticket admitted.')
                })} type="button">Admit</button>
                {ticketResult.requiresCash && (
                  <button className="button button--primary" disabled={submitting} onClick={() => void runAction(async () => {
                    await confirmCashForReservationTicket({ qrToken: qrToken.trim(), amountCollected: ticketResult.amountDue })
                    setMessage('Cash collected and ticket admitted.')
                  })} type="button">Collect cash</button>
                )}
              </div>
            </div>
          )}
        </article>

        <article className="panel">
          <div className="panel__header">
            <div>
              <p className="eyebrow">Recovery</p>
              <h3>Reissue missing tickets</h3>
            </div>
          </div>
          <form className="checkout__form" onSubmit={handleRecover}>
            <label className="checkout__label">
              Order ID
              <input className="checkout__input" value={recoveryOrderId} onChange={(e) => setRecoveryOrderId(e.target.value)} required />
            </label>
            <button className="button button--secondary" disabled={submitting || !recoveryOrderId.trim()} type="submit">
              Recover
            </button>
          </form>
        </article>
      </section>

      <section className="content-grid">
        <article className="panel">
          <div className="panel__header">
            <div>
              <p className="eyebrow">Flyer extraction</p>
              <h3>Create event draft clues</h3>
            </div>
          </div>
          <form className="checkout__form" onSubmit={handleExtract}>
            <label className="checkout__label">
              Flyer image URL
              <input className="checkout__input" value={flyerImageUrl} onChange={(e) => setFlyerImageUrl(e.target.value)} />
            </label>
            <label className="checkout__label">
              Flyer text
              <textarea className="checkout__input" rows={5} value={flyerText} onChange={(e) => setFlyerText(e.target.value)} />
            </label>
            <button className="button button--secondary" disabled={submitting || (!flyerText.trim() && !flyerImageUrl.trim())} type="submit">
              Extract details
            </button>
          </form>
        </article>

        <article className="panel">
          <div className="panel__header">
            <div>
              <p className="eyebrow">Promo mechanics</p>
              <h3>Create campaign mechanic</h3>
            </div>
          </div>
          <form className="checkout__form" onSubmit={handlePromo}>
            <label className="checkout__label">
              Type
              <select className="checkout__input" value={promoType} onChange={(e) => setPromoType(e.target.value)}>
                <option value="promo_code">Promo code</option>
                <option value="raffle">Raffle</option>
                <option value="leaderboard">Leaderboard</option>
                <option value="referral_campaign">Referral campaign</option>
                <option value="challenge">Challenge</option>
                <option value="flash_offer">Flash offer</option>
                <option value="birthday_club">Birthday club</option>
                <option value="check_in_challenge">Check-in challenge</option>
              </select>
            </label>
            <label className="checkout__label">
              Title
              <input className="checkout__input" value={promoTitle} onChange={(e) => setPromoTitle(e.target.value)} />
            </label>
            <label className="checkout__label">
              Code
              <input className="checkout__input" value={promoCode} onChange={(e) => setPromoCode(e.target.value)} />
            </label>
            <label className="checkout__label">
              Reward
              <input className="checkout__input" value={promoReward} onChange={(e) => setPromoReward(e.target.value)} />
            </label>
            <button className="button button--primary" disabled={submitting || !selectedEventId} type="submit">
              Create promo
            </button>
          </form>
        </article>
      </section>
    </div>
  )
}
