import { useEffect, useMemo, useState } from 'react'
import { Link } from 'react-router-dom'
import {
  Activity,
  AlertTriangle,
  ArrowRight,
  BadgeCheck,
  CalendarDays,
  Database,
  LifeBuoy,
  Megaphone,
  ReceiptText,
  Sparkles,
  Users,
  type LucideIcon,
} from 'lucide-react'

import {
  adminCollectionGroups,
  adminCollections,
  getAdminConsoleOverview,
  getAdminGroupLabel,
  getAdminRecordSubtitle,
  getAdminRecordTitle,
  type AdminCollectionId,
  type AdminOverview,
} from '../lib/adminConsole'
import { copy } from '../lib/copy'
import { getErrorMessage } from '../lib/errorMessages'
import { formatDateTime } from '../lib/formatters'
import { canPerformAdminAction, canReadAdminCollection } from '../lib/adminRoles'
import { usePortalSession } from '../lib/portalSession'

const groupIcons: Record<string, LucideIcon> = {
  Identity: Users,
  'Organizer Ops': BadgeCheck,
  Events: CalendarDays,
  Tickets: ReceiptText,
  Safety: AlertTriangle,
  Social: Activity,
  Marketing: Megaphone,
  Creative: Sparkles,
  Billing: ReceiptText,
  System: Database,
}

const metricCards: Array<{
  key: string
  label: string
  collectionId: AdminCollectionId
  icon: LucideIcon
}> = [
  { key: 'users', label: 'People', collectionId: 'users', icon: Users },
  { key: 'organizations', label: 'Organizers', collectionId: 'organizations', icon: BadgeCheck },
  { key: 'events', label: 'Events', collectionId: 'events', icon: CalendarDays },
  { key: 'event_ticket_orders', label: 'Ticket orders', collectionId: 'event_ticket_orders', icon: ReceiptText },
  { key: 'support_tickets', label: 'Support tickets', collectionId: 'support_tickets', icon: LifeBuoy },
  { key: 'promotion_campaigns', label: 'Promotions', collectionId: 'promotion_campaigns', icon: Megaphone },
  { key: 'event_reports', label: 'Safety reports', collectionId: 'event_reports', icon: AlertTriangle },
  { key: 'flyer_jobs', label: 'Creative requests', collectionId: 'flyer_jobs', icon: Sparkles },
]

export function AdminDashboardPage() {
  const session = usePortalSession()
  const [overview, setOverview] = useState<AdminOverview | null>(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    let cancelled = false
    async function loadOverview() {
      setLoading(true)
      setError(null)
      try {
        const nextOverview = await getAdminConsoleOverview()
        if (!cancelled) setOverview(nextOverview)
      } catch (caughtError) {
        if (!cancelled) setError(getErrorMessage(caughtError, copy.loadFailed))
      } finally {
        if (!cancelled) setLoading(false)
      }
    }
    void loadOverview()
    return () => {
      cancelled = true
    }
  }, [])

  const collectionsByGroup = useMemo(
    () =>
      adminCollectionGroups
        .map((group) => ({
          group,
          collections: adminCollections.filter(
            (collection) =>
              collection.group === group && canReadAdminCollection(session.adminRole, collection.id),
          ),
        }))
        .filter(({ collections }) => collections.length > 0),
    [session.adminRole],
  )
  const visibleMetrics = useMemo(
    () => metricCards.filter((metric) => canReadAdminCollection(session.adminRole, metric.collectionId)),
    [session.adminRole],
  )
  const firstReadableCollection = collectionsByGroup[0]?.collections[0]?.id ?? 'events'
  const canReviewOrganizers = canPerformAdminAction(session.adminRole, 'review_organizers')
  const canReadSafetyReports = canReadAdminCollection(session.adminRole, 'event_reports')
  const canManageSupport = canPerformAdminAction(session.adminRole, 'manage_support')
  const canReadMessages = canReadAdminCollection(session.adminRole, 'notification_jobs')

  if (loading) {
    return <div className="page-loader">{copy.loading}</div>
  }

  if (error || !overview) {
    return (
      <div className="page-loader">
        <p>{copy.loadFailed}</p>
        {error ? <p className="text-subtle">{error}</p> : null}
      </div>
    )
  }

  return (
    <div className="admin-dashboard">
      <section className="admin-page-header">
        <div>
          <p className="eyebrow">Overview</p>
          <h2>Platform operations</h2>
          <p>Updated {formatDateTime(overview.generatedAt)}</p>
        </div>
        <div className="admin-page-header__actions">
          <Link className="button button--primary" to={`/admin/data/${firstReadableCollection}`}>
            <Database size={16} aria-hidden />
            Find records
          </Link>
          {canReviewOrganizers ? (
            <Link className="button button--secondary" to="/admin/approvals">
              <BadgeCheck size={16} aria-hidden />
              Review organizers
            </Link>
          ) : null}
        </div>
      </section>

      <section className="admin-command-grid" aria-label="Priority admin queues">
        {canReviewOrganizers ? (
          <Link className="admin-command-card" to="/admin/approvals">
            <BadgeCheck size={18} aria-hidden />
            <span>Organizer approvals</span>
            <strong>{overview.counts.organizer_applications ?? 0}</strong>
          </Link>
        ) : null}
        {canReadSafetyReports ? (
          <Link className="admin-command-card" to="/admin/data/event_reports">
            <AlertTriangle size={18} aria-hidden />
            <span>Safety reports</span>
            <strong>{overview.counts.event_reports ?? 0}</strong>
          </Link>
        ) : null}
        {canManageSupport ? (
          <Link className="admin-command-card" to="/admin/support">
            <LifeBuoy size={18} aria-hidden />
            <span>Support tickets</span>
            <strong>{overview.counts.support_tickets ?? 0}</strong>
          </Link>
        ) : null}
        {canReadMessages ? (
          <Link className="admin-command-card" to="/admin/data/notification_jobs">
            <Megaphone size={18} aria-hidden />
            <span>Messages to send</span>
            <strong>{overview.counts.notification_jobs ?? 0}</strong>
          </Link>
        ) : null}
      </section>

      <section className="admin-metric-grid">
        {visibleMetrics.map((metric) => {
          const Icon = metric.icon
          return (
            <Link className="admin-metric-card" key={metric.key} to={`/admin/data/${metric.collectionId}`}>
              <span className="admin-metric-card__icon" aria-hidden>
                <Icon size={18} />
              </span>
              <span>{metric.label}</span>
              <strong>{overview.counts[metric.key] ?? 0}</strong>
            </Link>
          )
        })}
      </section>

      <section className="admin-grid-two">
        <article className="panel">
          <div className="panel__header">
            <div>
              <p className="eyebrow">Manage</p>
              <h3>Work areas</h3>
            </div>
          </div>
          <div className="admin-feature-groups">
            {collectionsByGroup.map(({ group, collections }) => {
              const Icon = groupIcons[group] ?? Database
              return (
                <div className="admin-feature-group" key={group}>
                  <div className="admin-feature-group__header">
                    <span aria-hidden>
                      <Icon size={16} />
                    </span>
                    <strong>{getAdminGroupLabel(group)}</strong>
                    <small>{collections.length} areas</small>
                  </div>
                  <div className="admin-feature-list">
                    {collections.map((collection) => (
                      <Link
                        className="admin-feature-row"
                        key={collection.id}
                        to={`/admin/data/${collection.id}`}
                      >
                        <div>
                          <strong>{collection.label}</strong>
                          <span>{collection.feature}</span>
                        </div>
                        <ArrowRight size={15} aria-hidden />
                      </Link>
                    ))}
                  </div>
                </div>
              )
            })}
          </div>
        </article>

        <article className="panel">
          <div className="panel__header">
            <div>
              <p className="eyebrow">Recent</p>
              <h3>Latest activity</h3>
            </div>
          </div>
          <div className="admin-recent-list">
            {Object.entries(overview.recent).flatMap(([collectionId, docs]) =>
              (docs ?? []).slice(0, 3).map((doc) => {
                const collection = adminCollections.find((item) => item.id === collectionId)
                if (!collection || !canReadAdminCollection(session.adminRole, collection.id)) return null
                return (
                  <Link
                    className="admin-recent-row"
                    key={`${collectionId}-${doc.docPath}`}
                    to={`/admin/data/${collectionId}?doc=${encodeURIComponent(doc.docPath)}`}
                    >
                      <div>
                        <span>{collection?.label ?? collectionId}</span>
                      <strong>{collection ? getAdminRecordTitle(doc, collection.summaryFields) : doc.id}</strong>
                      <small>
                        {collection
                          ? getAdminRecordSubtitle(doc, collection.summaryFields)
                          : doc.docPath}
                      </small>
                    </div>
                    <ArrowRight size={15} aria-hidden />
                  </Link>
                )
              }),
            )}
          </div>
        </article>
      </section>
    </div>
  )
}
