import { useEffect, useMemo, useState } from 'react'
import { Link, Navigate, useNavigate, useParams } from 'react-router-dom'

import { collection, doc } from 'firebase/firestore'
import { db } from '../firebaseDb'
import { copy } from '../lib/copy'
import { formatMoney } from '../lib/formatters'
import { getErrorMessage } from '../lib/errorMessages'
import {
  createEmptyEvent,
  getOrganizerEvent,
  saveOrganizerEvent,
  uploadEventCoverImage,
} from '../lib/portalData'
import { usePortalSession } from '../lib/portalSession'
import type { PortalEvent, PortalTicketTier } from '../lib/types'

export function EventEditorPage() {
  const { eventId } = useParams()
  const navigate = useNavigate()
  const session = usePortalSession()
  const [eventDraft, setEventDraft] = useState<PortalEvent | null>(null)
  const [tagsInput, setTagsInput] = useState('')
  const [loading, setLoading] = useState(Boolean(eventId))
  const [isSaving, setIsSaving] = useState(false)
  const [error, setError] = useState('')
  const [isUploadingCover, setIsUploadingCover] = useState(false)
  const [coverUploadError, setCoverUploadError] = useState('')

  useEffect(() => {
    let cancelled = false

    async function load() {
      if (!session.user || !session.organizationId) {
        return
      }
      if (!eventId) {
        const draft = createEmptyEvent({
          organizationId: session.organizationId,
          createdBy: session.user.uid,
        })
        if (!cancelled) {
          setEventDraft(draft)
          setTagsInput(draft.tags.join(', '))
        }
        return
      }
      setLoading(true)
      const existing = await getOrganizerEvent(eventId)
      if (!cancelled) {
        const draft =
          existing ??
          createEmptyEvent({
            id: eventId,
            organizationId: session.organizationId,
            createdBy: session.user.uid,
          })
        setEventDraft(
          draft,
        )
        setTagsInput(draft.tags.join(', '))
        setLoading(false)
      }
    }

    void load()
    return () => {
      cancelled = true
    }
  }, [eventId, session.organizationId, session.user])

  const readinessChecks = useMemo(() => {
    if (!eventDraft) {
      return []
    }

    return [
      {
        label: 'Event title is set',
        complete: eventDraft.title.trim().length >= 3,
      },
      {
        label: 'Description is filled in',
        complete: eventDraft.description.trim().length >= 24,
      },
      {
        label: 'Venue and city are set',
        complete: Boolean(eventDraft.venue.trim() && eventDraft.city.trim()),
      },
      {
        label: 'Start time is scheduled',
        complete: Boolean(eventDraft.startAt),
      },
      {
        label: eventDraft.ticketingEnabled
          ? 'At least one ticket tier is configured'
          : 'Ticketing is intentionally turned off',
        complete: eventDraft.ticketingEnabled ? eventDraft.tiers.length > 0 : true,
      },
    ]
  }, [eventDraft])

  const completedChecks = readinessChecks.filter((item) => item.complete).length
  const totalCapacity = (eventDraft?.tiers ?? []).reduce(
    (sum, tier) => sum + tier.maxQuantity,
    0,
  )
  const potentialGross = (eventDraft?.tiers ?? []).reduce(
    (sum, tier) => sum + tier.price * tier.maxQuantity,
    0,
  )

  if (!session.user) {
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
      navigate(`/studio/events/${savedId}/edit`)
    } catch (caughtError) {
      setError(getErrorMessage(caughtError, copy.eventSaveFailed))
    } finally {
      setIsSaving(false)
    }
  }

  return (
    <div className="dashboard-stack">
      <section className="page-hero page-hero--editor">
        <div className="page-hero__content">
          <p className="eyebrow">{eventId ? 'Edit event' : 'Create event'}</p>
          <h2>Shape the public event page before guests ever see it.</h2>
          <p>
            Use the main canvas for copy and ticket setup, then rely on the
            summary rail to check what is still missing before you publish.
          </p>
          <div className="hero-chip-row">
            <span>{eventDraft.visibility} visibility</span>
            <span>{eventDraft.status} status</span>
            <span>
              {eventDraft.ticketingEnabled ? `${eventDraft.tiers.length} ticket tiers` : 'No ticketing'}
            </span>
          </div>
        </div>
        <div className="page-hero__panel">
          <p className="eyebrow">Readiness</p>
          <h3>
            {completedChecks}/{readinessChecks.length} checks complete
          </h3>
          <p>
            Save once the essentials are in place, then come back to refine
            details as your campaign or lineup evolves.
          </p>
          <div className="hero-actions">
            <button className="button button--secondary" onClick={() => navigate('/studio/events')} type="button">
              Back to events
            </button>
            {eventId ? (
              <Link className="button button--secondary" to={`/studio/promote?eventId=${eventId}`}>
                Promote event
              </Link>
            ) : null}
            {eventId && eventDraft.status === 'published' ? (
              <Link className="button button--secondary" to={`/events/${eventId}`} target="_blank" rel="noopener noreferrer">
                View public page ↗
              </Link>
            ) : null}
            <button
              className="button button--primary"
              disabled={isSaving || !eventDraft.title.trim() || !eventDraft.venue.trim()}
              onClick={handleSave}
              type="button"
            >
              {isSaving ? 'Saving...' : 'Save event'}
            </button>
          </div>
        </div>
      </section>

      <div className="editor-layout">
        <div className="editor-column">
          <section className="editor-card editor-card--section">
            <div className="editor-section__header">
              <div>
                <p className="eyebrow">Cover image</p>
                <h3>The banner guests see first</h3>
              </div>
            </div>
            <div className="cover-upload-area">
              {eventDraft.coverImageUrl ? (
                <div className="cover-upload-preview">
                  <img src={eventDraft.coverImageUrl} alt="Event cover" />
                  <div className="cover-upload-preview__actions">
                    <label className="button button--secondary cover-upload-btn">
                      {isUploadingCover ? 'Uploading...' : 'Replace image'}
                      <input
                        accept="image/*"
                        disabled={isUploadingCover}
                        hidden
                        onChange={handleCoverImageChange}
                        type="file"
                      />
                    </label>
                    <button
                      className="button button--ghost"
                      onClick={() => setEventDraft((d) => d ? { ...d, coverImageUrl: '' } : d)}
                      type="button"
                    >
                      Remove
                    </button>
                  </div>
                </div>
              ) : (
                <label className={`cover-upload-drop${isUploadingCover ? ' cover-upload-drop--uploading' : ''}`}>
                  <div className="cover-upload-drop__inner">
                    <span className="cover-upload-drop__icon">+</span>
                    <strong>{isUploadingCover ? 'Uploading…' : 'Upload cover image'}</strong>
                    <span>JPG, PNG or WebP · recommended 1400×700px</span>
                  </div>
                  <input
                    accept="image/*"
                    disabled={isUploadingCover}
                    hidden
                    onChange={handleCoverImageChange}
                    type="file"
                  />
                </label>
              )}
              {coverUploadError && <p className="form-error">{coverUploadError}</p>}
            </div>
          </section>

          <section className="editor-card editor-card--section">
            <div className="editor-section__header">
              <div>
                <p className="eyebrow">Event identity</p>
                <h3>Core details guests will read first</h3>
              </div>
            </div>

            <div className="form-grid">
              <Field
                label="Event title"
                note="Keep it short, recognizable, and easy to scan."
                onChange={(value) =>
                  setEventDraft((current) => current && { ...current, title: value })
                }
                value={eventDraft.title}
                wide
              />
              <Field
                label="Description"
                multiline
                note="Cover the format, energy, and what guests should expect."
                onChange={(value) =>
                  setEventDraft((current) => current && { ...current, description: value })
                }
                rows={5}
                value={eventDraft.description}
                wide
              />
              <SelectField
                label="Visual mood"
                onChange={(value) =>
                  setEventDraft((current) =>
                    current ? { ...current, mood: value } : current,
                  )
                }
                options={[
                  ['night', 'Night'],
                  ['sunrise', 'Sunrise'],
                  ['electric', 'Electric'],
                  ['garden', 'Garden'],
                ]}
                value={eventDraft.mood}
              />
              <Field
                label="Tags"
                note="Separate tags with commas. Example: Afrobeats, Rooftop, Day party"
                onChange={(value) => {
                  setTagsInput(value)
                  setEventDraft((current) =>
                    current
                      ? {
                          ...current,
                          tags: parseTags(value),
                        }
                      : current,
                  )
                }}
                placeholder="Afrobeats, Rooftop, Day party"
                value={tagsInput}
                wide
              />
            </div>
          </section>

          <section className="editor-card editor-card--section">
            <div className="editor-section__header">
              <div>
                <p className="eyebrow">Schedule and venue</p>
                <h3>Set timing, location, and launch state</h3>
              </div>
            </div>

            <div className="form-grid">
              <Field
                label="Venue"
                onChange={(value) =>
                  setEventDraft((current) => current && { ...current, venue: value })
                }
                value={eventDraft.venue}
              />
              <Field
                label="City"
                onChange={(value) =>
                  setEventDraft((current) => current && { ...current, city: value })
                }
                value={eventDraft.city}
              />
              <Field
                label="Start date and time"
                onChange={(value) =>
                  setEventDraft((current) => current && { ...current, startAt: value })
                }
                type="datetime-local"
                value={eventDraft.startAt}
              />
              <Field
                label="End date and time"
                onChange={(value) =>
                  setEventDraft((current) => current && { ...current, endAt: value })
                }
                type="datetime-local"
                value={eventDraft.endAt}
              />
              <SelectField
                label="Visibility"
                onChange={(value) =>
                  setEventDraft((current) =>
                    current
                      ? { ...current, visibility: value as PortalEvent['visibility'] }
                      : current,
                  )
                }
                options={[
                  ['public', 'Public'],
                  ['private', 'Private'],
                ]}
                value={eventDraft.visibility}
              />
              <SelectField
                label="Publish state"
                onChange={(value) =>
                  setEventDraft((current) =>
                    current
                      ? { ...current, status: value as PortalEvent['status'] }
                      : current,
                  )
                }
                options={[
                  ['draft', 'Draft'],
                  ['published', 'Published'],
                  ['cancelled', 'Cancelled'],
                ]}
                value={eventDraft.status}
              />
            </div>
          </section>

          <section className="editor-card editor-card--section">
            <div className="editor-section__header">
              <div>
                <p className="eyebrow">Lineup</p>
                <h3>Highlight the talent and hosts</h3>
              </div>
            </div>

            <div className="form-grid">
              <Field
                label="Performers"
                onChange={(value) =>
                  setEventDraft((current) => current && { ...current, performers: value })
                }
                placeholder="Featured artists, speakers, or guest talent"
                value={eventDraft.performers}
              />
              <Field
                label="DJs"
                onChange={(value) =>
                  setEventDraft((current) => current && { ...current, djs: value })
                }
                placeholder="Headline DJ names"
                value={eventDraft.djs}
              />
              <Field
                label="MCs"
                onChange={(value) =>
                  setEventDraft((current) => current && { ...current, mcs: value })
                }
                placeholder="Hosts and on-stage personalities"
                value={eventDraft.mcs}
                wide
              />
            </div>
          </section>

          <section className="editor-card editor-card--section">
            <div className="editor-section__header">
              <div>
                <p className="eyebrow">Ticketing</p>
                <h3>Build tiers that match your door strategy</h3>
              </div>
            </div>

            <div className="toggle-stack">
              <ToggleField
                checked={eventDraft.ticketingEnabled}
                description="Turn this off only if guests should RSVP without ticket inventory."
                label="Ticketing enabled"
                onChange={(checked) =>
                  setEventDraft((current) =>
                    current ? { ...current, ticketingEnabled: checked } : current,
                  )
                }
              />
              <ToggleField
                checked={eventDraft.requireTicket}
                description="Require a ticket when door access should stay tightly controlled."
                label="Require a ticket for entry"
                onChange={(checked) =>
                  setEventDraft((current) =>
                    current ? { ...current, requireTicket: checked } : current,
                  )
                }
              />
            </div>

            {eventDraft.ticketingEnabled ? (
              <>
                <div className="tiers-list">
                  {eventDraft.tiers.map((tier, index) => (
                    <div className="tier-card" key={tier.tierId}>
                      <div className="tier-card__header">
                        <div>
                          <strong>{tier.name || `Tier ${index + 1}`}</strong>
                          <span>
                            {formatMoney(tier.price)} • capacity {tier.maxQuantity}
                          </span>
                        </div>
                        <button
                          className="button button--ghost"
                          onClick={() =>
                            setEventDraft((current) =>
                              current
                                ? {
                                    ...current,
                                    tiers: current.tiers.filter(
                                      (item) => item.tierId !== tier.tierId,
                                    ),
                                  }
                                : current,
                            )
                          }
                          type="button"
                        >
                          Remove tier
                        </button>
                      </div>
                      <div className="form-grid">
                        <Field
                          label="Tier name"
                          onChange={(value) => updateTier(index, { ...tier, name: value })}
                          value={tier.name}
                        />
                        <Field
                          label="Price"
                          onChange={(value) =>
                            updateTier(index, { ...tier, price: Number(value || 0) })
                          }
                          type="number"
                          value={String(tier.price)}
                        />
                        <Field
                          label="Capacity"
                          onChange={(value) =>
                            updateTier(index, {
                              ...tier,
                              maxQuantity: Number(value || 0),
                            })
                          }
                          type="number"
                          value={String(tier.maxQuantity)}
                        />
                        <Field
                          label="Description"
                          multiline
                          onChange={(value) =>
                            updateTier(index, { ...tier, description: value })
                          }
                          rows={3}
                          value={tier.description}
                          wide
                        />
                      </div>
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
              </>
            ) : (
              <div className="empty-card">
                <h4>Ticketing is off for this event</h4>
                <p>
                  Guests can still view the page, but no ticket inventory will be
                  sold from Studio until you turn ticketing back on.
                </p>
              </div>
            )}
          </section>

          <section className="editor-card editor-card--section">
            <div className="editor-section__header">
              <div>
                <p className="eyebrow">Distribution</p>
                <h3>Choose how Vennuzo promotes and shares this page</h3>
              </div>
            </div>

            <div className="toggle-stack">
              <ToggleField
                checked={eventDraft.allowSharing}
                description="Let guests copy links and share the event across channels."
                label="Allow share links"
                onChange={(checked) =>
                  setEventDraft((current) =>
                    current ? { ...current, allowSharing: checked } : current,
                  )
                }
              />
              <ToggleField
                checked={eventDraft.sendPushNotification}
                description="Send push notifications when you publish or update the event."
                label="Send push on publish"
                onChange={(checked) =>
                  setEventDraft((current) =>
                    current ? { ...current, sendPushNotification: checked } : current,
                  )
                }
              />
              <ToggleField
                checked={eventDraft.sendSmsNotification}
                description="Enable SMS outreach for important guest updates."
                label="Send SMS on publish"
                onChange={(checked) =>
                  setEventDraft((current) =>
                    current ? { ...current, sendSmsNotification: checked } : current,
                  )
                }
              />
            </div>
          </section>
        </div>

        <aside className="editor-sidebar">
          <section className="editor-card editor-card--summary">
            <p className="eyebrow">Summary rail</p>
            <h3>{eventDraft.title.trim() || 'Untitled event draft'}</h3>
            <p>
              {eventDraft.venue.trim() && eventDraft.city.trim()
                ? `${eventDraft.venue}, ${eventDraft.city}`
                : 'Venue details will appear here once you add them.'}
            </p>

            <div className="summary-stat-grid">
              <article className="summary-stat">
                <span>Ticket tiers</span>
                <strong>{eventDraft.tiers.length}</strong>
              </article>
              <article className="summary-stat">
                <span>Capacity</span>
                <strong>{totalCapacity}</strong>
              </article>
              <article className="summary-stat">
                <span>Potential gross</span>
                <strong>{formatMoney(potentialGross)}</strong>
              </article>
              <article className="summary-stat">
                <span>Event ID</span>
                <strong>{eventDraft.id || 'Not saved yet'}</strong>
              </article>
            </div>

            <div className="readiness-card">
              <div className="panel__header">
                <div>
                  <p className="eyebrow">Checklist</p>
                  <h4>Before you publish</h4>
                </div>
              </div>
              <ul className="readiness-list">
                {readinessChecks.map((item) => (
                  <li
                    className={item.complete ? 'is-complete' : 'is-pending'}
                    key={item.label}
                  >
                    <span>{item.complete ? 'Ready' : 'Pending'}</span>
                    <strong>{item.label}</strong>
                  </li>
                ))}
              </ul>
            </div>

            {error ? <p className="form-error">{error}</p> : null}

            <div className="editor-actions editor-actions--stacked">
              <button
                className="button button--ghost button--full"
                onClick={() => navigate('/studio/events')}
                type="button"
              >
                Back to events
              </button>
              {eventId && eventDraft.status === 'published' ? (
                <Link
                  className="button button--secondary button--full"
                  to={`/events/${eventId}`}
                  target="_blank"
                  rel="noopener noreferrer"
                >
                  View public page ↗
                </Link>
              ) : null}
              <button
                className="button button--primary button--full"
                disabled={isSaving || !eventDraft.title.trim() || !eventDraft.venue.trim()}
                onClick={handleSave}
                type="button"
              >
                {isSaving ? 'Saving...' : 'Save event'}
              </button>
            </div>
          </section>
        </aside>
      </div>
    </div>
  )

  async function handleCoverImageChange(event: React.ChangeEvent<HTMLInputElement>) {
    const file = event.target.files?.[0]
    if (!file || !eventDraft) return
    setCoverUploadError('')
    setIsUploadingCover(true)
    try {
      const id = eventDraft.id || doc(collection(db, 'events')).id
      if (!eventDraft.id) {
        setEventDraft((d) => d ? { ...d, id } : d)
      }
      const url = await uploadEventCoverImage(id, file)
      setEventDraft((d) => d ? { ...d, id, coverImageUrl: url } : d)
    } catch {
      setCoverUploadError('Image upload failed. Please try again.')
    } finally {
      setIsUploadingCover(false)
    }
  }

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

  function parseTags(value: string) {
    return value
      .split(',')
      .map((tag) => tag.trim())
      .filter(Boolean)
  }
}

function Field({
  label,
  value,
  onChange,
  type = 'text',
  wide = false,
  placeholder,
  note,
  multiline = false,
  rows = 4,
}: {
  label: string
  value: string
  onChange: (value: string) => void
  type?: string
  wide?: boolean
  placeholder?: string
  note?: string
  multiline?: boolean
  rows?: number
}) {
  return (
    <label className={wide ? 'field field--wide' : 'field'}>
      <span>{label}</span>
      {multiline ? (
        <textarea
          onChange={(event) => onChange(event.target.value)}
          placeholder={placeholder}
          rows={rows}
          value={value}
        />
      ) : (
        <input
          onChange={(event) => onChange(event.target.value)}
          placeholder={placeholder}
          type={type}
          value={value}
        />
      )}
      {note ? <small>{note}</small> : null}
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
  description,
  onChange,
}: {
  checked: boolean
  label: string
  description: string
  onChange: (value: boolean) => void
}) {
  return (
    <label className="toggle-card">
      <div>
        <strong>{label}</strong>
        <p>{description}</p>
      </div>
      <input checked={checked} onChange={(event) => onChange(event.target.checked)} type="checkbox" />
    </label>
  )
}
