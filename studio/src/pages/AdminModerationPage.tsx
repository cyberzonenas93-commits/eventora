import { useEffect, useMemo, useState } from 'react'
import { Link } from 'react-router-dom'
import {
  collection,
  doc,
  limit,
  onSnapshot,
  orderBy,
  query,
  serverTimestamp,
  updateDoc,
  type DocumentData,
  type QueryDocumentSnapshot,
} from 'firebase/firestore'
import { AlertTriangle, CheckCircle2, ExternalLink, RotateCcw, XCircle } from 'lucide-react'

import { db } from '../firebaseDb'
import { trackEvent } from '../lib/analytics'
import { getErrorMessage } from '../lib/errorMessages'
import { formatDateTime } from '../lib/formatters'
import { usePortalSession } from '../lib/portalSession'

type EventReport = {
  id: string
  eventId: string
  eventTitle: string
  reason: string
  details: string
  status: string
  reviewedByEmail: string
  createdAt: string
}

const STATUS_FILTERS = ['open', 'resolved', 'dismissed', 'all'] as const
type StatusFilter = (typeof STATUS_FILTERS)[number]

function toIso(value: unknown): string {
  if (value && typeof (value as { toDate?: () => Date }).toDate === 'function') {
    return (value as { toDate: () => Date }).toDate().toISOString()
  }
  return typeof value === 'string' ? value : ''
}

function toReport(snap: QueryDocumentSnapshot<DocumentData>): EventReport {
  const data = snap.data() ?? {}
  return {
    id: snap.id,
    eventId: String(data.eventId ?? ''),
    eventTitle: String(data.eventTitle ?? 'Event'),
    reason: String(data.reason ?? ''),
    details: String(data.details ?? ''),
    status: String(data.status ?? 'open'),
    reviewedByEmail: String(data.reviewedByEmail ?? ''),
    createdAt: toIso(data.createdAt),
  }
}

export function AdminModerationPage() {
  const session = usePortalSession()
  const [reports, setReports] = useState<EventReport[]>([])
  const [loading, setLoading] = useState(true)
  const [filter, setFilter] = useState<StatusFilter>('open')
  const [error, setError] = useState('')
  const [busyId, setBusyId] = useState('')

  useEffect(() => {
    const reportsQuery = query(
      collection(db, 'event_reports'),
      orderBy('createdAt', 'desc'),
      limit(200),
    )
    const unsubscribe = onSnapshot(
      reportsQuery,
      (snapshot) => {
        setReports(snapshot.docs.map(toReport))
        setLoading(false)
      },
      (err) => {
        setError(getErrorMessage(err, 'Could not load reports.'))
        setLoading(false)
      },
    )
    return () => unsubscribe()
  }, [])

  const visibleReports = useMemo(
    () => reports.filter((report) => (filter === 'all' ? true : (report.status || 'open') === filter)),
    [reports, filter],
  )
  const openCount = useMemo(
    () => reports.filter((report) => (report.status || 'open') === 'open').length,
    [reports],
  )

  async function updateStatus(report: EventReport, status: string) {
    setBusyId(report.id)
    setError('')
    try {
      await updateDoc(doc(db, 'event_reports', report.id), {
        status,
        reviewedBy: session.user?.uid ?? '',
        reviewedByEmail: session.user?.email ?? '',
        reviewedAt: serverTimestamp(),
        updatedAt: serverTimestamp(),
      })
      void trackEvent('admin_action', { action: 'moderation_report_review', status }, { area: 'admin' })
    } catch (err) {
      setError(getErrorMessage(err, 'Could not update the report.'))
    } finally {
      setBusyId('')
    }
  }

  return (
    <section className="admin-page" style={{ padding: '1.5rem', maxWidth: 920, margin: '0 auto' }}>
      <header style={{ marginBottom: '1rem' }}>
        <h1 style={{ display: 'flex', alignItems: 'center', gap: '0.5rem' }}>
          <AlertTriangle size={22} aria-hidden /> Trust &amp; Safety — event reports
        </h1>
        <p style={{ opacity: 0.75 }}>
          {openCount} open report{openCount === 1 ? '' : 's'}. Review attendee-submitted reports and
          mark each resolved or dismissed.
        </p>
      </header>

      <div
        role="tablist"
        aria-label="Filter reports by status"
        style={{ display: 'flex', gap: '0.5rem', marginBottom: '1rem', flexWrap: 'wrap' }}
      >
        {STATUS_FILTERS.map((value) => (
          <button
            key={value}
            type="button"
            role="tab"
            aria-selected={filter === value}
            className="button button--secondary"
            onClick={() => setFilter(value)}
            style={{ fontWeight: filter === value ? 800 : 500, textTransform: 'capitalize' }}
          >
            {value}
          </button>
        ))}
      </div>

      {error ? (
        <p role="alert" style={{ color: '#dc2626' }}>
          {error}
        </p>
      ) : null}
      {loading ? <p>Loading reports…</p> : null}
      {!loading && visibleReports.length === 0 ? (
        <p>No {filter === 'all' ? '' : filter} reports.</p>
      ) : null}

      <ul style={{ listStyle: 'none', padding: 0, display: 'grid', gap: '0.75rem' }}>
        {visibleReports.map((report) => {
          const status = report.status || 'open'
          return (
            <li
              key={report.id}
              style={{
                border: '1px solid rgba(127,127,127,.25)',
                borderRadius: 12,
                padding: '1rem',
              }}
            >
              <div
                style={{ display: 'flex', justifyContent: 'space-between', gap: '1rem', flexWrap: 'wrap' }}
              >
                <div>
                  <strong>{report.reason || 'Report'}</strong>{' '}
                  <span style={{ fontSize: 12, textTransform: 'uppercase', opacity: 0.7 }}>· {status}</span>
                  <div style={{ fontSize: 13, opacity: 0.8 }}>{report.eventTitle}</div>
                </div>
                <div style={{ fontSize: 12, opacity: 0.7, textAlign: 'right' }}>
                  <div>{formatDateTime(report.createdAt)}</div>
                  {report.reviewedByEmail ? <div>reviewed by {report.reviewedByEmail}</div> : null}
                </div>
              </div>
              <p style={{ margin: '0.5rem 0', whiteSpace: 'pre-wrap' }}>{report.details}</p>
              <div style={{ display: 'flex', gap: '0.5rem', flexWrap: 'wrap', alignItems: 'center' }}>
                {report.eventId ? (
                  <Link className="button button--secondary" to={`/events/${report.eventId}`}>
                    <ExternalLink size={14} aria-hidden /> View event
                  </Link>
                ) : null}
                {status !== 'resolved' ? (
                  <button
                    type="button"
                    className="button button--primary"
                    disabled={busyId === report.id}
                    onClick={() => updateStatus(report, 'resolved')}
                  >
                    <CheckCircle2 size={14} aria-hidden /> Resolve
                  </button>
                ) : null}
                {status !== 'dismissed' ? (
                  <button
                    type="button"
                    className="button button--secondary"
                    disabled={busyId === report.id}
                    onClick={() => updateStatus(report, 'dismissed')}
                  >
                    <XCircle size={14} aria-hidden /> Dismiss
                  </button>
                ) : null}
                {status !== 'open' ? (
                  <button
                    type="button"
                    className="button button--secondary"
                    disabled={busyId === report.id}
                    onClick={() => updateStatus(report, 'open')}
                  >
                    <RotateCcw size={14} aria-hidden /> Reopen
                  </button>
                ) : null}
              </div>
            </li>
          )
        })}
      </ul>
    </section>
  )
}
