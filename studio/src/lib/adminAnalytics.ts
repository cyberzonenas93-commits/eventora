import { httpsCallable } from 'firebase/functions'

import { functions } from '../firebaseFunctions'

export interface AdminAnalyticsDailyPoint {
  campaigns: number
  date: string
  eventsPublished: number
  orders: number
  pageViews: number
  revenue: number
  signups: number
  tickets: number
  visitors: number
}

export interface AdminAnalyticsOverview {
  campaignStatusCounts: Record<string, number>
  conversion: {
    averageOrderValue: number
    checkoutToOrderRate: number | null
    eventPublishRate: number
  }
  daily: AdminAnalyticsDailyPoint[]
  generatedAt: string
  last7: {
    campaigns: number
    paidOrders: number
    revenue: number
    supportTickets: number
    tickets: number
  }
  last30: {
    adminActions: number
    campaignSpend: number
    campaigns: number
    checkoutStarts: number
    newOrganizations: number
    paidOrders: number
    pageViews: number
    revenue: number
    signups: number
    supportTickets: number
    ticketOrdersTracked: number
    tickets: number
    visitors: number
  }
  topEvents: Array<{
    eventId: string
    orders: number
    revenue: number
    tickets: number
    title: string
  }>
  totals: {
    campaigns: number
    events: number
    organizations: number
    publishedEvents: number
    submittedApplications: number
    supportTickets: number
    ticketOrders: number
    users: number
  }
}

const getAdminAnalyticsOverviewCallable = httpsCallable<void, AdminAnalyticsOverview>(
  functions,
  'getAdminAnalyticsOverview',
)

export function getAdminAnalyticsOverview() {
  return getAdminAnalyticsOverviewCallable().then((result) => result.data)
}
