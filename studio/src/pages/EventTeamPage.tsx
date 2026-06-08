import { useCallback, useEffect, useMemo, useState, type FormEvent } from 'react'
import { httpsCallable } from 'firebase/functions'
import {
  Activity,
  Copy,
  KeyRound,
  ShieldCheck,
  TicketCheck,
  UserPlus,
  Users,
} from 'lucide-react'

import { functions } from '../firebaseFunctions'
import { getErrorMessage } from '../lib/errorMessages'
import { formatDateTime, titleCaseStatus } from '../lib/formatters'
import { listOrganizerEvents } from '../lib/portalData'
import { usePortalSession } from '../lib/portalSession'
import type { PortalEvent } from '../lib/types'

interface RoleTemplate {
  id: string
  label: string
  description: string
  permissions: Record<string, boolean>
}

interface TeamMember {
  id: string
  userId: string
  email: string
  displayName: string
  role: string
  roleLabel: string
  permissions: Record<string, boolean>
  status: string
}

interface TeamInvite {
  id: string
  email: string
  role: string
  roleLabel: string
  permissions: Record<string, boolean>
  status: string
  acceptUrl: string
  createdAt?: string | null
  acceptedAt?: string | null
}

interface ScanLog {
  id: string
  type: string
  attendeeName: string
  tierName: string
  status: string
  outcome: string
  performedByEmail: string
  role: string
  createdAt?: string | null
}

interface TeamWorkspaceResult {
  success: boolean
  eventId: string
  eventTitle: string
  roleTemplates: RoleTemplate[]
  members: TeamMember[]
  invites: TeamInvite[]
  scanLogs: ScanLog[]
}

const getEventTeamWorkspace = httpsCallable<{ eventId: string }, TeamWorkspaceResult>(
  functions,
  'getEventTeamWorkspace',
)

const createEventTeamInvite = httpsCallable<
  { eventId: string; email: string; role: string; permissions?: Record<string, boolean> },
  TeamWorkspaceResult & { acceptUrl: string }
>(functions, 'createEventTeamInvite')

const updateEventTeamMember = httpsCallable<
  { eventId: string; userId: string; role: string; permissions?: Record<string, boolean>; status: string },
  TeamWorkspaceResult
>(functions, 'updateEventTeamMember')

export function EventTeamPage() {
  const { organizationId } = usePortalSession()
  const [events, setEvents] = useState<PortalEvent[]>([])
  const [selectedEventId, setSelectedEventId] = useState('')
  const [workspace, setWorkspace] = useState<TeamWorkspaceResult | null>(null)
  const [email, setEmail] = useState('')
  const [role, setRole] = useState('scanner')
  const [customPermissions, setCustomPermissions] = useState<Record<string, boolean>>({})
  const [message, setMessage] = useState<string | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [loading, setLoading] = useState(true)
  const [submitting, setSubmitting] = useState(false)

  useEffect(() => {
    let cancelled = false
    if (!organizationId) return
    setLoading(true)
    listOrganizerEvents(organizationId)
      .then((items) => {
        if (cancelled) return
        setEvents(items)
        setSelectedEventId((current) => current || items[0]?.id || '')
      })
      .catch((err) => {
        if (!cancelled) setError(getErrorMessage(err, 'Could not load events.'))
      })
      .finally(() => {
        if (!cancelled) setLoading(false)
      })
    return () => {
      cancelled = true
    }
  }, [organizationId])

  const selectedRole = useMemo(
    () => workspace?.roleTemplates.find((item) => item.id === role) ?? workspace?.roleTemplates[0],
    [role, workspace],
  )
  const activePermissions = {
    ...(selectedRole?.permissions ?? {}),
    ...customPermissions,
  }

  const refreshTeam = useCallback(async (eventId = selectedEventId) => {
    if (!eventId) return
    setLoading(true)
    setError(null)
    try {
      const result = await getEventTeamWorkspace({ eventId })
      setWorkspace(result.data)
      setRole((current) => result.data.roleTemplates.some((item) => item.id === current) ? current : result.data.roleTemplates[0]?.id || 'scanner')
    } catch (err) {
      setError(getErrorMessage(err, 'Could not load team workspace.'))
    } finally {
      setLoading(false)
    }
  }, [selectedEventId])

  useEffect(() => {
    if (!selectedEventId) return
    void refreshTeam(selectedEventId)
  }, [refreshTeam, selectedEventId])

  async function handleInvite(e: FormEvent) {
    e.preventDefault()
    if (!selectedEventId || !email.trim()) return
    setSubmitting(true)
    setError(null)
    setMessage(null)
    try {
      const result = await createEventTeamInvite({
        eventId: selectedEventId,
        email: email.trim(),
        role,
        permissions: activePermissions,
      })
      setWorkspace(result.data)
      setEmail('')
      setCustomPermissions({})
      setMessage(`Invite created. Link copied-ready: ${result.data.acceptUrl}`)
    } catch (err) {
      setError(getErrorMessage(err, 'Could not create invite.'))
    } finally {
      setSubmitting(false)
    }
  }

  async function copyInvite(url: string) {
    await navigator.clipboard.writeText(url)
    setMessage('Invite link copied.')
  }

  async function toggleMember(member: TeamMember) {
    if (!selectedEventId) return
    setSubmitting(true)
    try {
      const result = await updateEventTeamMember({
        eventId: selectedEventId,
        userId: member.userId,
        role: member.role,
        permissions: member.permissions,
        status: member.status === 'active' ? 'disabled' : 'active',
      })
      setWorkspace(result.data)
    } catch (err) {
      setError(getErrorMessage(err, 'Could not update team member.'))
    } finally {
      setSubmitting(false)
    }
  }

  return (
    <div className="team-page">
      <section className="team-hero">
        <div>
          <p className="eyebrow">Event team</p>
          <h2>Invite staff, assign roles, and protect ticket admission.</h2>
          <p>
            Build the actual operations team for each event: scanners, gate leads, box office staff,
            inventory staff, and owners. Every validation and admission action is permission-checked.
          </p>
        </div>
        <div className="team-hero__stats">
          <span><Users size={18} aria-hidden /> {workspace?.members.length ?? 0} members</span>
          <span><UserPlus size={18} aria-hidden /> {workspace?.invites.filter((item) => item.status === 'pending').length ?? 0} invites</span>
          <span><Activity size={18} aria-hidden /> {workspace?.scanLogs.length ?? 0} scans</span>
        </div>
      </section>

      {message && <div className="notice notice--success">{message}</div>}
      {error && <div className="notice notice--error">{error}</div>}

      <section className="panel">
        <div className="panel__header">
          <div>
            <p className="eyebrow">Event</p>
            <h3>Choose the event team to manage</h3>
          </div>
        </div>
        <select className="checkout__input" value={selectedEventId} onChange={(e) => setSelectedEventId(e.target.value)}>
          {events.map((event) => (
            <option key={event.id} value={event.id}>{event.title}</option>
          ))}
        </select>
      </section>

      <section className="content-grid">
        <article className="panel">
          <div className="panel__header">
            <div>
              <p className="eyebrow">Invite</p>
              <h3>Add staff by email</h3>
            </div>
            <UserPlus size={20} aria-hidden />
          </div>
          <form className="checkout__form" onSubmit={handleInvite}>
            <label className="checkout__label">
              Email address
              <input className="checkout__input" type="email" value={email} onChange={(e) => setEmail(e.target.value)} required />
            </label>
            <label className="checkout__label">
              Role template
              <select className="checkout__input" value={role} onChange={(e) => {
                setRole(e.target.value)
                setCustomPermissions({})
              }}>
                {workspace?.roleTemplates.map((template) => (
                  <option key={template.id} value={template.id}>{template.label}</option>
                ))}
              </select>
            </label>
            {selectedRole && <p className="text-subtle">{selectedRole.description}</p>}
            <div className="permission-grid">
              {Object.entries(activePermissions).map(([permission, enabled]) => (
                <label className="permission-toggle" key={permission}>
                  <input
                    checked={enabled}
                    type="checkbox"
                    onChange={(e) => setCustomPermissions((current) => ({ ...current, [permission]: e.target.checked }))}
                  />
                  <span>{permissionLabel(permission)}</span>
                </label>
              ))}
            </div>
            <button className="button button--primary" disabled={submitting || !selectedEventId || !email.trim()} type="submit">
              <ShieldCheck size={16} aria-hidden />
              Create invite
            </button>
          </form>
        </article>

        <article className="panel">
          <div className="panel__header">
            <div>
              <p className="eyebrow">Pending</p>
              <h3>Invite links</h3>
            </div>
            <KeyRound size={20} aria-hidden />
          </div>
          <div className="team-list">
            {workspace?.invites.length ? workspace.invites.map((invite) => (
              <div className="team-row" key={invite.id}>
                <div>
                  <strong>{invite.email}</strong>
                  <span>{invite.roleLabel} · {titleCaseStatus(invite.status)}</span>
                </div>
                {invite.acceptUrl && (
                  <button className="button button--secondary" onClick={() => void copyInvite(invite.acceptUrl)} type="button">
                    <Copy size={15} aria-hidden />
                    Copy
                  </button>
                )}
              </div>
            )) : <p className="text-subtle">No invites yet.</p>}
          </div>
        </article>
      </section>

      <section className="content-grid">
        <article className="panel">
          <div className="panel__header">
            <div>
              <p className="eyebrow">Members</p>
              <h3>Accepted team</h3>
            </div>
            <Users size={20} aria-hidden />
          </div>
          <div className="team-list">
            {workspace?.members.length ? workspace.members.map((member) => (
              <div className="team-row" key={member.id}>
                <div>
                  <strong>{member.displayName || member.email}</strong>
                  <span>{member.roleLabel} · {titleCaseStatus(member.status)}</span>
                </div>
                <button className="button button--ghost" disabled={submitting} onClick={() => void toggleMember(member)} type="button">
                  {member.status === 'active' ? 'Disable' : 'Reactivate'}
                </button>
              </div>
            )) : <p className="text-subtle">Accepted staff will appear here.</p>}
          </div>
        </article>

        <article className="panel">
          <div className="panel__header">
            <div>
              <p className="eyebrow">Live log</p>
              <h3>Ticket scan activity</h3>
            </div>
            <TicketCheck size={20} aria-hidden />
          </div>
          <div className="team-list team-list--log">
            {workspace?.scanLogs.length ? workspace.scanLogs.map((log) => (
              <div className="team-row" key={log.id}>
                <div>
                  <strong>{log.attendeeName || titleCaseStatus(log.type)}</strong>
                  <span>{log.tierName || log.outcome} · {log.role || 'staff'}</span>
                </div>
                <small>{log.createdAt ? formatDateTime(log.createdAt) : 'Just now'}</small>
              </div>
            )) : <p className="text-subtle">Ticket validation and admission actions will stream in here.</p>}
          </div>
        </article>
      </section>

      {loading && <div className="page-loader"><p>Loading event team…</p></div>}
    </div>
  )
}

function permissionLabel(permission: string) {
  return permission
    .replace(/([A-Z])/g, ' $1')
    .replace(/^./, (letter) => letter.toUpperCase())
}
