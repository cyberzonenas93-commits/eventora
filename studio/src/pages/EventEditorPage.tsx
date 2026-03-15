import { useEffect, useState } from 'react'
import { Navigate, useNavigate, useParams } from 'react-router-dom'

import { createEmptyEvent, getOrganizerEvent, saveOrganizerEvent } from '../lib/portalData'
import { usePortalSession } from '../lib/portalSession'
import type { PortalEvent, PortalTicketTier } from '../lib/types'

export function EventEditorPage() {
  const { eventId } = useParams()
  const navigate = useNavigate()
  const session = usePortalSession()
  const [eventDraft, setEventDraft] = useState<PortalEvent | null>(null)
  const [loading, setLoading] = useState(Boolean(eventId))
  const [isSaving, setIsSaving] = useState(false)
  const [error, setError] = useState('')

  useEffect(() => {
    let cancelled = false

    async function load() {
      if (!session.user || !session.organizationId) {
        return
      }
      if (!eventId) {
        setEventDraft(
          createEmptyEvent({
            organizationId: session.organizationId,
            createdBy: session.user.uid,
          }),
        )
        return
      }
      setLoading(true)
      const existing = await getOrganizerEvent(eventId)
      if (!cancelled) {
        setEventDraft(
          existing ??
            createEmptyEvent({
              id: eventId,
              organizationId: session.organizationId,
              createdBy: session.user.uid,
            }),
        )
        setLoading(false)
      }
    }

    void load()
    return () => {
      cancelled = true
    }
  }, [eventId, session.organizationId, session.user])

  if (!session.user || session.status !== 'approved') {
    return <Navigate replace to="/" />
  }

  if (loading || !eventDraft) {
    return <div className="page-loader">Loading event editor...</div>
  }

  async function handleSave() {
    const currentDraft = eventDraft
    if (!currentDraft) {
      return
    }
    setError('')
    setIsSaving(true)
    try {
      const savedId = await saveOrganizerEvent(currentDraft)
      navigate(`/events/${savedId}/edit`)
    } catch (caughtError) {
      setError(
        caughtError instanceof Error ? caughtError.message : 'Could not save event.',
      )
    } finally {
      setIsSaving(false)
    }
  }

  return (
    <div className="dashboard-stack">
      <section className="hero-card hero-card--compact">
        <div>
          <p className="eyebrow">{eventId ? 'Edit event' : 'Create event'}</p>
          <h2>Set the event identity, ticket tiers, and organizer-facing distribution rules.</h2>
        </div>
      </section>

      <section className="editor-card">
        <div className="form-grid">
          <Field
            label="Event title"
            value={eventDraft.title}
            onChange={(value) => setEventDraft((current) => current && { ...current, title: value })}
            wide
          />
          <Field
            label="Description"
            value={eventDraft.description}
            onChange={(value) =>
              setEventDraft((current) => current && { ...current, description: value })
            }
            wide
          />
          <Field
            label="Venue"
            value={eventDraft.venue}
            onChange={(value) => setEventDraft((current) => current && { ...current, venue: value })}
          />
          <Field
            label="City"
            value={eventDraft.city}
            onChange={(value) => setEventDraft((current) => current && { ...current, city: value })}
          />
          <Field
            label="Start date & time"
            type="datetime-local"
            value={eventDraft.startAt}
            onChange={(value) => setEventDraft((current) => current && { ...current, startAt: value })}
          />
          <Field
            label="End date & time"
            type="datetime-local"
            value={eventDraft.endAt}
            onChange={(value) => setEventDraft((current) => current && { ...current, endAt: value })}
          />
          <SelectField
            label="Visibility"
            value={eventDraft.visibility}
            onChange={(value) =>
              setEventDraft((current) =>
                current ? { ...current, visibility: value as PortalEvent['visibility'] } : current,
              )
            }
            options={[
              ['public', 'Public'],
              ['private', 'Private'],
            ]}
          />
          <SelectField
            label="Publish state"
            value={eventDraft.status}
            onChange={(value) =>
              setEventDraft((current) =>
                current ? { ...current, status: value as PortalEvent['status'] } : current,
              )
            }
            options={[
              ['draft', 'Draft'],
              ['published', 'Published'],
              ['cancelled', 'Cancelled'],
            ]}
          />
          <Field
            label="Performers"
            value={eventDraft.performers}
            onChange={(value) =>
              setEventDraft((current) => current && { ...current, performers: value })
            }
          />
          <Field
            label="DJs"
            value={eventDraft.djs}
            onChange={(value) => setEventDraft((current) => current && { ...current, djs: value })}
          />
          <Field
            label="MCs"
            value={eventDraft.mcs}
            onChange={(value) => setEventDraft((current) => current && { ...current, mcs: value })}
          />
          <Field
            label="Tags"
            value={eventDraft.tags.join(', ')}
            onChange={(value) =>
              setEventDraft((current) =>
                current
                  ? {
                      ...current,
                      tags: value
                        .split(',')
                        .map((tag) => tag.trim())
                        .filter(Boolean),
                    }
                  : current,
              )
            }
            wide
          />
        </div>

        <div className="editor-section">
          <div className="editor-section__header">
            <div>
              <p className="eyebrow">Ticketing</p>
              <h3>Ticket tiers and access rules</h3>
            </div>
            <ToggleField
              checked={eventDraft.ticketingEnabled}
              label="Ticketing enabled"
              onChange={(checked) =>
                setEventDraft((current) =>
                  current ? { ...current, ticketingEnabled: checked } : current,
                )
              }
            />
          </div>

          <ToggleField
            checked={eventDraft.requireTicket}
            label="Require ticket for entry"
            onChange={(checked) =>
              setEventDraft((current) =>
                current ? { ...current, requireTicket: checked } : current,
              )
            }
          />

          <div className="tiers-list">
            {eventDraft.tiers.map((tier, index) => (
              <div className="tier-card" key={tier.tierId}>
                <div className="form-grid">
                  <Field
                    label="Tier name"
                    value={tier.name}
                    onChange={(value) => updateTier(index, { ...tier, name: value })}
                  />
                  <Field
                    label="Price"
                    type="number"
                    value={String(tier.price)}
                    onChange={(value) =>
                      updateTier(index, { ...tier, price: Number(value || 0) })
                    }
                  />
                  <Field
                    label="Capacity"
                    type="number"
                    value={String(tier.maxQuantity)}
                    onChange={(value) =>
                      updateTier(index, { ...tier, maxQuantity: Number(value || 0) })
                    }
                  />
                  <Field
                    label="Description"
                    value={tier.description}
                    onChange={(value) => updateTier(index, { ...tier, description: value })}
                    wide
                  />
                </div>
                <button
                  className="button button--ghost"
                  onClick={() =>
                    setEventDraft((current) =>
                      current
                        ? {
                            ...current,
                            tiers: current.tiers.filter((item) => item.tierId !== tier.tierId),
                          }
                        : current,
                    )
                  }
                  type="button"
                >
                  Remove tier
                </button>
              </div>
            ))}
          </div>

          <button
            className="button button--secondary"
            onClick={() =>
              setEventDraft((current) =>
                current
                  ? {
                      ...current,
                      tiers: [
                        ...current.tiers,
                        {
                          tierId: crypto.randomUUID(),
                          name: 'New tier',
                          price: 0,
                          maxQuantity: 100,
                          sold: 0,
                          description: '',
                        },
                      ],
                    }
                  : current,
              )
            }
            type="button"
          >
            Add ticket tier
          </button>
        </div>

        <div className="editor-section">
          <div className="editor-section__header">
            <div>
              <p className="eyebrow">Distribution</p>
              <h3>Sharing and notification defaults</h3>
            </div>
          </div>
          <div className="toggle-stack">
            <ToggleField
              checked={eventDraft.allowSharing}
              label="Allow share links"
              onChange={(checked) =>
                setEventDraft((current) => current && { ...current, allowSharing: checked })
              }
            />
            <ToggleField
              checked={eventDraft.sendPushNotification}
              label="Send push notification on publish"
              onChange={(checked) =>
                setEventDraft((current) =>
                  current && { ...current, sendPushNotification: checked },
                )
              }
            />
            <ToggleField
              checked={eventDraft.sendSmsNotification}
              label="Send SMS notification on publish"
              onChange={(checked) =>
                setEventDraft((current) =>
                  current && { ...current, sendSmsNotification: checked },
                )
              }
            />
          </div>
        </div>

        {error ? <p className="form-error">{error}</p> : null}

        <div className="editor-actions">
          <button className="button button--ghost" onClick={() => navigate('/events')} type="button">
            Back to events
          </button>
          <button
            className="button button--primary"
            disabled={isSaving || !eventDraft.title.trim() || !eventDraft.venue.trim()}
            onClick={handleSave}
            type="button"
          >
            {isSaving ? 'Saving...' : 'Save event'}
          </button>
        </div>
      </section>
    </div>
  )

  function updateTier(index: number, nextTier: PortalTicketTier) {
    setEventDraft((current) =>
      current
        ? {
            ...current,
            tiers: current.tiers.map((tier, tierIndex) =>
              tierIndex === index ? nextTier : tier,
            ),
          }
        : current,
    )
  }
}

function Field({
  label,
  value,
  onChange,
  type = 'text',
  wide = false,
}: {
  label: string
  value: string
  onChange: (value: string) => void
  type?: string
  wide?: boolean
}) {
  return (
    <label className={wide ? 'field field--wide' : 'field'}>
      <span>{label}</span>
      <input onChange={(event) => onChange(event.target.value)} type={type} value={value} />
    </label>
  )
}

function SelectField({
  label,
  value,
  options,
  onChange,
}: {
  label: string
  value: string
  options: Array<[string, string]>
  onChange: (value: string) => void
}) {
  return (
    <label className="field">
      <span>{label}</span>
      <select onChange={(event) => onChange(event.target.value)} value={value}>
        {options.map(([optionValue, optionLabel]) => (
          <option key={optionValue} value={optionValue}>
            {optionLabel}
          </option>
        ))}
      </select>
    </label>
  )
}

function ToggleField({
  checked,
  label,
  onChange,
}: {
  checked: boolean
  label: string
  onChange: (value: boolean) => void
}) {
  return (
    <label className="toggle">
      <input checked={checked} onChange={(event) => onChange(event.target.checked)} type="checkbox" />
      <span>{label}</span>
    </label>
  )
}
