import { useEffect, useMemo, useRef, useState } from 'react'
import {
  addDoc,
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
import {
  Bell,
  CheckCircle2,
  Clock,
  LifeBuoy,
  MessageCircle,
  Send,
  UserRound,
  XCircle,
} from 'lucide-react'

import { db } from '../firebaseDb'
import { canPerformAdminAction } from '../lib/adminRoles'
import { trackEvent } from '../lib/analytics'
import { getErrorMessage } from '../lib/errorMessages'
import { formatDateTime } from '../lib/formatters'
import { usePortalSession } from '../lib/portalSession'

type SupportTicket = {
  id: string
  userId: string
  name: string
  email: string
  phone: string
  topic: string
  subject: string
  status: string
  priority: string
  source: string
  latestMessage: string
  adminUnreadCount: number
  userUnreadCount: number
  assignedTo: string
  assignedToEmail: string
  createdAt: string
  updatedAt: string
  lastMessageAt: string
}

type SupportMessage = {
  id: string
  senderType: 'admin' | 'user'
  senderId: string
  senderName: string
  body: string
  createdAt: string
}

const filters = [
  { id: 'all', label: 'All' },
  { id: 'unread', label: 'Unread' },
  { id: 'awaiting_support', label: 'Needs reply' },
  { id: 'awaiting_user', label: 'Replied' },
  { id: 'closed', label: 'Closed' },
] as const

const statusActions = [
  { id: 'awaiting_support', label: 'Needs reply', icon: Clock },
  { id: 'awaiting_user', label: 'Replied', icon: CheckCircle2 },
  { id: 'closed', label: 'Close', icon: XCircle },
] as const

export function AdminSupportPage() {
  const session = usePortalSession()
  const canManageSupport = canPerformAdminAction(session.adminRole, 'manage_support')
  const [tickets, setTickets] = useState<SupportTicket[]>([])
  const [messages, setMessages] = useState<SupportMessage[]>([])
  const [selectedTicketId, setSelectedTicketId] = useState('')
  const [filter, setFilter] = useState<(typeof filters)[number]['id']>('all')
  const [reply, setReply] = useState('')
  const [loadingTickets, setLoadingTickets] = useState(true)
  const [loadingMessages, setLoadingMessages] = useState(false)
  const [sending, setSending] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [notificationsEnabled, setNotificationsEnabled] = useState(
    typeof Notification !== 'undefined' && Notification.permission === 'granted',
  )
  const previousUnreadTotal = useRef<number | null>(null)

  useEffect(() => {
    if (!canManageSupport) {
      setTickets([])
      setLoadingTickets(false)
      return undefined
    }

    setLoadingTickets(true)
    const ticketQuery = query(
      collection(db, 'support_tickets'),
      orderBy('lastMessageAt', 'desc'),
      limit(120),
    )
    return onSnapshot(
      ticketQuery,
      (snapshot) => {
        const nextTickets = snapshot.docs.map(normalizeTicket)
        const unreadTotal = nextTickets.reduce((sum, ticket) => sum + ticket.adminUnreadCount, 0)
        const newestUnread = nextTickets.find((ticket) => ticket.adminUnreadCount > 0)
        if (
          previousUnreadTotal.current != null &&
          unreadTotal > previousUnreadTotal.current &&
          typeof Notification !== 'undefined' &&
          Notification.permission === 'granted' &&
          newestUnread
        ) {
          new Notification('New Vennuzo support message', {
            body: `${newestUnread.name || newestUnread.email}: ${newestUnread.latestMessage}`,
          })
        }
        previousUnreadTotal.current = unreadTotal
        setTickets(nextTickets)
        setLoadingTickets(false)
        setError(null)
      },
      (caughtError) => {
        setError(getErrorMessage(caughtError, 'Support tickets could not load.'))
        setLoadingTickets(false)
      },
    )
  }, [canManageSupport])

  const filteredTickets = useMemo(() => {
    return tickets.filter((ticket) => {
      if (filter === 'all') return true
      if (filter === 'unread') return ticket.adminUnreadCount > 0
      return ticket.status === filter
    })
  }, [filter, tickets])

  const selectedTicket = useMemo(
    () => tickets.find((ticket) => ticket.id === selectedTicketId) ?? filteredTickets[0] ?? null,
    [filteredTickets, selectedTicketId, tickets],
  )

  useEffect(() => {
    if (!selectedTicket && filteredTickets[0]) {
      setSelectedTicketId(filteredTickets[0].id)
      return
    }
    if (selectedTicket && selectedTicket.id !== selectedTicketId) {
      setSelectedTicketId(selectedTicket.id)
    }
  }, [filteredTickets, selectedTicket, selectedTicketId])

  useEffect(() => {
    if (!selectedTicket?.id) {
      setMessages([])
      return undefined
    }

    setLoadingMessages(true)
    const messageQuery = query(
      collection(db, 'support_tickets', selectedTicket.id, 'messages'),
      orderBy('createdAt', 'asc'),
    )
    return onSnapshot(
      messageQuery,
      (snapshot) => {
        setMessages(snapshot.docs.map(normalizeMessage))
        setLoadingMessages(false)
      },
      (caughtError) => {
        setError(getErrorMessage(caughtError, 'Support messages could not load.'))
        setLoadingMessages(false)
      },
    )
  }, [selectedTicket?.id])

  useEffect(() => {
    if (!selectedTicket || selectedTicket.adminUnreadCount <= 0) return
    updateDoc(doc(db, 'support_tickets', selectedTicket.id), {
      adminUnreadCount: 0,
      lastAdminReadAt: serverTimestamp(),
      updatedAt: serverTimestamp(),
    }).catch(() => {})
  }, [selectedTicket])

  async function enableDesktopNotifications() {
    if (typeof Notification === 'undefined') {
      setError('This browser does not support desktop notifications.')
      return
    }
    const permission = await Notification.requestPermission()
    setNotificationsEnabled(permission === 'granted')
    if (permission !== 'granted') {
      setError('Desktop notifications were not enabled.')
    }
  }

  async function sendReply() {
    const body = reply.trim()
    if (!selectedTicket || !session.user || !body || sending) return

    setSending(true)
    setError(null)
    try {
      await addDoc(collection(db, 'support_tickets', selectedTicket.id, 'messages'), {
        senderType: 'admin',
        senderId: session.user.uid,
        senderName: session.profile?.displayName || session.user.email || 'Vennuzo support',
        body,
        createdAt: serverTimestamp(),
      })
      await updateDoc(doc(db, 'support_tickets', selectedTicket.id), {
        status: 'awaiting_user',
        assignedTo: session.user.uid,
        assignedToEmail: session.user.email || '',
        adminUnreadCount: 0,
        latestMessage: body.slice(0, 500),
        lastMessageAt: serverTimestamp(),
        lastAdminMessageAt: serverTimestamp(),
        updatedAt: serverTimestamp(),
      })
      setReply('')
      void trackEvent('admin_action', {
        action: 'support_reply_sent',
        response_chars: body.length,
        ticket_priority: selectedTicket.priority,
        ticket_source: selectedTicket.source,
      }, {
        area: 'admin',
        role: session.adminRole,
      })
    } catch (caughtError) {
      setError(getErrorMessage(caughtError, 'Reply could not be sent.'))
    } finally {
      setSending(false)
    }
  }

  async function updateTicketStatus(status: string) {
    if (!selectedTicket) return
    setError(null)
    try {
      await updateDoc(doc(db, 'support_tickets', selectedTicket.id), {
        status,
        closedAt: status === 'closed' ? serverTimestamp() : null,
        updatedAt: serverTimestamp(),
      })
      void trackEvent('admin_action', {
        action: 'support_status_updated',
        ticket_status: status,
        ticket_priority: selectedTicket.priority,
      }, {
        area: 'admin',
        role: session.adminRole,
      })
    } catch (caughtError) {
      setError(getErrorMessage(caughtError, 'Ticket status could not be updated.'))
    }
  }

  async function assignToMe() {
    if (!selectedTicket || !session.user) return
    setError(null)
    try {
      await updateDoc(doc(db, 'support_tickets', selectedTicket.id), {
        assignedTo: session.user.uid,
        assignedToEmail: session.user.email || '',
        updatedAt: serverTimestamp(),
      })
      void trackEvent('admin_action', {
        action: 'support_assigned',
        ticket_status: selectedTicket.status,
        ticket_priority: selectedTicket.priority,
      }, {
        area: 'admin',
        role: session.adminRole,
      })
    } catch (caughtError) {
      setError(getErrorMessage(caughtError, 'Ticket could not be assigned.'))
    }
  }

  if (!canManageSupport) {
    return (
      <div className="page-loader">
        <p>This admin role cannot use support chat.</p>
        <p className="text-subtle">Choose another work area from the admin sidebar.</p>
      </div>
    )
  }

  const unreadTotal = tickets.reduce((sum, ticket) => sum + ticket.adminUnreadCount, 0)

  return (
    <div className="admin-support-page">
      <section className="admin-page-header">
        <div>
          <p className="eyebrow">Support inbox</p>
          <h2>User support chat</h2>
          <p>
            Handle in-app support tickets, reply to users, assign conversations, and track unread
            support requests from one place.
          </p>
          <div className="admin-meta-row">
            <span>{tickets.length} tickets</span>
            <span>{unreadTotal} unread</span>
            <span>{tickets.filter((ticket) => ticket.status !== 'closed').length} active</span>
          </div>
        </div>
        <div className="admin-page-header__actions">
          <button
            className="button button--secondary"
            disabled={notificationsEnabled}
            onClick={() => void enableDesktopNotifications()}
            type="button"
          >
            <Bell size={16} aria-hidden />
            {notificationsEnabled ? 'Notifications on' : 'Enable notifications'}
          </button>
        </div>
      </section>

      {error ? <p className="form-error">{error}</p> : null}

      <section className="support-inbox">
        <aside className="support-ticket-list" aria-label="Support ticket list">
          <div className="support-filter-row">
            {filters.map((item) => (
              <button
                className={filter === item.id ? 'is-active' : ''}
                key={item.id}
                onClick={() => setFilter(item.id)}
                type="button"
              >
                {item.label}
              </button>
            ))}
          </div>
          <div className="support-ticket-list__scroll">
            {loadingTickets ? (
              <p className="admin-empty-inline">Loading support tickets...</p>
            ) : filteredTickets.length === 0 ? (
              <p className="admin-empty-inline">No support tickets match this filter.</p>
            ) : (
              filteredTickets.map((ticket) => (
                <button
                  className={ticket.id === selectedTicket?.id ? 'is-selected' : ''}
                  key={ticket.id}
                  onClick={() => setSelectedTicketId(ticket.id)}
                  type="button"
                >
                  <span className="support-ticket-list__icon" aria-hidden>
                    <LifeBuoy size={16} />
                    {ticket.adminUnreadCount > 0 ? <i>{ticket.adminUnreadCount}</i> : null}
                  </span>
                  <span>
                    <strong>{ticket.subject || ticket.topic}</strong>
                    <small>{ticket.name || ticket.email || ticket.userId}</small>
                    <em>{ticket.latestMessage || 'No message yet'}</em>
                  </span>
                  <small>{formatDateTime(ticket.lastMessageAt || ticket.updatedAt || ticket.createdAt)}</small>
                </button>
              ))
            )}
          </div>
        </aside>

        <article className="support-conversation">
          {selectedTicket ? (
            <>
              <header className="support-conversation__header">
                <div>
                  <p className="eyebrow">{selectedTicket.topic}</p>
                  <h3>{selectedTicket.subject}</h3>
                  <div className="support-user-line">
                    <span><UserRound size={14} aria-hidden /> {selectedTicket.name || 'Vennuzo user'}</span>
                    <span>{selectedTicket.email || 'No email'}</span>
                    <span>{selectedTicket.phone || 'No phone'}</span>
                  </div>
                </div>
                <div className="support-ticket-controls">
                  <span className={`support-status-badge support-status-badge--${selectedTicket.status.replace(/_/g, '-')}`}>
                    {labelForStatus(selectedTicket.status)}
                  </span>
                  <button className="button button--secondary" onClick={() => void assignToMe()} type="button">
                    Assign to me
                  </button>
                </div>
              </header>

              <div className="support-status-actions" aria-label="Ticket status actions">
                {statusActions.map((action) => {
                  const Icon = action.icon
                  return (
                    <button
                      className={selectedTicket.status === action.id ? 'is-active' : ''}
                      key={action.id}
                      onClick={() => void updateTicketStatus(action.id)}
                      type="button"
                    >
                      <Icon size={15} aria-hidden />
                      {action.label}
                    </button>
                  )
                })}
              </div>

              <div className="support-message-thread">
                {loadingMessages ? (
                  <p className="admin-empty-inline">Loading messages...</p>
                ) : messages.length === 0 ? (
                  <p className="admin-empty-inline">No messages in this ticket yet.</p>
                ) : (
                  messages.map((message) => (
                    <div
                      className={`support-message support-message--${message.senderType === 'admin' ? 'admin' : 'user'}`}
                      key={message.id}
                    >
                      <div>
                        <strong>{message.senderType === 'admin' ? 'Vennuzo support' : message.senderName || selectedTicket.name}</strong>
                        <small>{formatDateTime(message.createdAt)}</small>
                      </div>
                      <p>{message.body}</p>
                    </div>
                  ))
                )}
              </div>

              <footer className="support-reply-box">
                <div className="support-assignment">
                  <MessageCircle size={15} aria-hidden />
                  <span>
                    Assigned to {selectedTicket.assignedToEmail || 'nobody yet'}
                  </span>
                </div>
                <textarea
                  disabled={selectedTicket.status === 'closed' || sending}
                  onChange={(event) => setReply(event.target.value)}
                  placeholder={
                    selectedTicket.status === 'closed'
                      ? 'This ticket is closed.'
                      : 'Write a support reply...'
                  }
                  value={reply}
                />
                <div className="support-reply-box__actions">
                  <span>{selectedTicket.id}</span>
                  <button
                    className="button button--primary"
                    disabled={selectedTicket.status === 'closed' || sending || !reply.trim()}
                    onClick={() => void sendReply()}
                    type="button"
                  >
                    <Send size={16} aria-hidden />
                    {sending ? 'Sending...' : 'Send reply'}
                  </button>
                </div>
              </footer>
            </>
          ) : (
            <div className="support-empty-state">
              <LifeBuoy size={36} aria-hidden />
              <h3>No ticket selected</h3>
              <p>Select a support ticket from the inbox to view the conversation.</p>
            </div>
          )}
        </article>
      </section>
    </div>
  )
}

function normalizeTicket(snapshot: QueryDocumentSnapshot<DocumentData>): SupportTicket {
  const data = snapshot.data()
  return {
    id: snapshot.id,
    userId: String(data.userId ?? ''),
    name: String(data.name ?? ''),
    email: String(data.email ?? ''),
    phone: String(data.phone ?? ''),
    topic: String(data.topic ?? 'General support'),
    subject: String(data.subject ?? 'Support ticket'),
    status: String(data.status ?? 'open'),
    priority: String(data.priority ?? 'normal'),
    source: String(data.source ?? ''),
    latestMessage: String(data.latestMessage ?? ''),
    adminUnreadCount: Number(data.adminUnreadCount ?? 0),
    userUnreadCount: Number(data.userUnreadCount ?? 0),
    assignedTo: String(data.assignedTo ?? ''),
    assignedToEmail: String(data.assignedToEmail ?? ''),
    createdAt: timestampToIso(data.createdAt),
    updatedAt: timestampToIso(data.updatedAt),
    lastMessageAt: timestampToIso(data.lastMessageAt),
  }
}

function normalizeMessage(snapshot: QueryDocumentSnapshot<DocumentData>): SupportMessage {
  const data = snapshot.data()
  const senderType = String(data.senderType ?? 'user') === 'admin' ? 'admin' : 'user'
  return {
    id: snapshot.id,
    senderType,
    senderId: String(data.senderId ?? ''),
    senderName: String(data.senderName ?? ''),
    body: String(data.body ?? ''),
    createdAt: timestampToIso(data.createdAt),
  }
}

function timestampToIso(value: unknown) {
  if (value && typeof (value as { toDate?: () => Date }).toDate === 'function') {
    const date = (value as { toDate: () => Date }).toDate()
    return Number.isNaN(date.getTime()) ? '' : date.toISOString()
  }
  if (typeof value === 'string') {
    return value
  }
  return ''
}

function labelForStatus(value: string) {
  if (value === 'awaiting_support') return 'Needs reply'
  if (value === 'awaiting_user') return 'Replied'
  if (value === 'closed') return 'Closed'
  if (value === 'pending') return 'Pending'
  return 'Open'
}
