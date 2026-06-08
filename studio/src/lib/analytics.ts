import {
  getAnalytics,
  isSupported,
  logEvent,
  setUserId,
  setUserProperties,
  type Analytics,
} from 'firebase/analytics'
import { httpsCallable } from 'firebase/functions'

import { app } from '../firebaseApp'
import { functions } from '../firebaseFunctions'

export type AnalyticsEventName =
  | 'page_view'
  | 'login'
  | 'sign_up'
  | 'logout'
  | 'public_search'
  | 'event_saved'
  | 'event_shared'
  | 'event_rsvp'
  | 'event_published'
  | 'checkout_started'
  | 'checkout_step'
  | 'checkout_abandoned'
  | 'payment_initiated'
  | 'payment_completed'
  | 'ticket_issued'
  | 'ticket_checked_in'
  | 'ticket_order_created'
  | 'ticket_purchase_returned'
  | 'campaign_launched'
  | 'billing_checkout_started'
  | 'wallet_topup_started'
  | 'payout_withdrawal_started'
  | 'organizer_application_saved'
  | 'organizer_application_submitted'
  | 'admin_action'
  | 'sms_opt_out_recorded'

type AnalyticsParams = Record<string, string | number | boolean | null | undefined>

const recordAnalyticsEvent = httpsCallable<
  {
    anonymousId: string
    area?: string
    name: AnalyticsEventName
    organizationId?: string | null
    params?: AnalyticsParams
    path?: string
    role?: string
  },
  { success: boolean }
>(functions, 'recordAnalyticsEvent')

let analyticsPromise: Promise<Analytics | null> | null = null
let anonymousIdCache = ''

export function initProductAnalytics() {
  void getWebAnalytics()
}

export async function identifyAnalyticsUser(
  uid: string | null,
  properties?: AnalyticsParams,
) {
  const analytics = await getWebAnalytics()
  if (!analytics) return
  setUserId(analytics, uid)
  if (properties) {
    setUserProperties(analytics, sanitizeParams(properties))
  }
}

export function trackPageView(input: {
  area?: string
  organizationId?: string | null
  path: string
  role?: string
  title?: string
}) {
  return trackEvent('page_view', {
    page_path: input.path,
    page_title: input.title ?? document.title,
  }, input)
}

export async function trackEvent(
  name: AnalyticsEventName,
  params: AnalyticsParams = {},
  context: {
    area?: string
    organizationId?: string | null
    path?: string
    role?: string
  } = {},
) {
  if (respectsDoNotTrack()) return

  const sanitizedParams = sanitizeParams(params)
  const path = sanitizePath(context.path ?? window.location.pathname)
  const area = context.area ?? areaFromPath(path)

  const analytics = await getWebAnalytics()
  const analyticsParams = {
    ...sanitizedParams,
    area,
    page_path: path,
  }
  if (analytics) {
    if (name === 'page_view') {
      logEvent(analytics, 'page_view', analyticsParams)
    } else if (name === 'login') {
      logEvent(analytics, 'login', analyticsParams)
    } else if (name === 'sign_up') {
      logEvent(analytics, 'sign_up', analyticsParams)
    } else {
      logEvent(analytics, name, analyticsParams)
    }
  }

  try {
    await recordAnalyticsEvent({
      anonymousId: getAnonymousId(),
      area,
      name,
      organizationId: context.organizationId ?? null,
      params: sanitizedParams,
      path,
      role: context.role,
    })
  } catch (error) {
    if (import.meta.env.DEV) {
      console.warn('[analytics]', error)
    }
  }
}

function getWebAnalytics() {
  if (analyticsPromise) return analyticsPromise
  analyticsPromise = (async () => {
    if (!app.options.measurementId) return null
    if (!(await isSupported())) return null
    return getAnalytics(app)
  })()
  return analyticsPromise
}

function getAnonymousId() {
  if (anonymousIdCache) return anonymousIdCache
  const storageKey = 'vennuzo_anonymous_id'
  try {
    const existing = window.localStorage.getItem(storageKey)
    if (existing) {
      anonymousIdCache = existing
      return anonymousIdCache
    }
    anonymousIdCache = crypto.randomUUID()
    window.localStorage.setItem(storageKey, anonymousIdCache)
    return anonymousIdCache
  } catch {
    anonymousIdCache = `session_${Math.random().toString(36).slice(2)}`
    return anonymousIdCache
  }
}

function sanitizeParams(params: AnalyticsParams) {
  return Object.entries(params).reduce<Record<string, string | number | boolean>>((next, [rawKey, value]) => {
    const key = rawKey.replace(/[^a-zA-Z0-9_]+/g, '_').slice(0, 40)
    if (!key || /email|phone|password|token|secret|address|name|note|message/i.test(key)) return next
    if (typeof value === 'boolean') next[key] = value
    if (typeof value === 'number' && Number.isFinite(value)) next[key] = value
    if (typeof value === 'string') next[key] = value.slice(0, 120)
    return next
  }, {})
}

function sanitizePath(path: string) {
  const normalized = path.split('?')[0].split('#')[0]
  return normalized.startsWith('/') ? normalized.slice(0, 180) : '/'
}

function areaFromPath(path: string) {
  if (path.startsWith('/admin')) return 'admin'
  if (path.startsWith('/studio')) return 'studio'
  if (path.startsWith('/checkout')) return 'checkout'
  if (path.startsWith('/events')) return 'public_events'
  return 'public'
}

function respectsDoNotTrack() {
  return navigator.doNotTrack === '1'
}
