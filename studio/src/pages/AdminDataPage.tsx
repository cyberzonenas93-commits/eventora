import { useEffect, useMemo, useState, type FormEvent } from 'react'
import { useNavigate, useParams, useSearchParams } from 'react-router-dom'
import { httpsCallable } from 'firebase/functions'
import { CheckCircle2, KeyRound, ListChecks, Plus, RefreshCw, Save, Search, Trash2, XCircle } from 'lucide-react'

import {
  adminCollectionById,
  adminCollectionGroups,
  adminCollections,
  deleteAdminConsoleDocument,
  getAdminGroupLabel,
  getAdminRecordSubtitle,
  getAdminRecordTitle,
  humanizeAdminField,
  isAdminCollectionId,
  isLinkedAdminField,
  listAdminConsoleDocuments,
  saveAdminConsoleDocument,
  summarizeAdminFieldValue,
  summarizeAdminValue,
  updateAdminAuthUser,
  type AdminCollectionId,
  type AdminDocument,
  type AdminJsonValue,
} from '../lib/adminConsole'
import { copy } from '../lib/copy'
import { getErrorMessage } from '../lib/errorMessages'
import { trackEvent } from '../lib/analytics'
import {
  canDeleteAdminCollection,
  canPerformAdminAction,
  canReadAdminCollection,
  canWriteAdminCollection,
} from '../lib/adminRoles'
import { usePortalSession } from '../lib/portalSession'
import { functions } from '../firebaseFunctions'

interface AdminDataPageProps {
  collectionIdOverride?: AdminCollectionId
}

interface AuthFormState {
  email: string
  displayName: string
  password: string
  disabled: boolean
}

type EditableAdminValue = string | number | boolean | null
type FieldDraftValue = string | boolean

const reviewPlaceVerification = httpsCallable<
  { requestId: string; decision: 'approve' | 'reject'; reviewNotes?: string },
  { ok: boolean; requestId: string; placeId: string; status: string }
>(functions, 'reviewPlaceVerification')

function isEditableAdminValue(value: AdminJsonValue): value is EditableAdminValue {
  return value == null || typeof value === 'string' || typeof value === 'number' || typeof value === 'boolean'
}

function buildFieldDrafts(doc: AdminDocument, fields: readonly string[]) {
  return fields.reduce<Record<string, FieldDraftValue>>((drafts, field) => {
    const value = doc.data[field]
    if (!isEditableAdminValue(value)) return drafts
    drafts[field] = typeof value === 'boolean' ? value : value == null ? '' : String(value)
    return drafts
  }, {})
}

function parseFieldDraft(field: string, original: EditableAdminValue, value: FieldDraftValue): AdminJsonValue {
  if (typeof original === 'boolean') return Boolean(value)
  if (typeof original === 'number') {
    const parsed = Number(value)
    if (!Number.isFinite(parsed)) {
      throw new Error(`${humanizeAdminField(field)} must be a number.`)
    }
    return parsed
  }
  if (original == null && value === '') return null
  return String(value)
}

function defaultAuthForm(): AuthFormState {
  return {
    email: '',
    displayName: '',
    password: '',
    disabled: false,
  }
}

function authFormFromDocument(doc: AdminDocument): AuthFormState {
  return {
    email: summarizeAdminValue(doc.data.email ?? ''),
    displayName: summarizeAdminValue(doc.data.displayName ?? ''),
    password: '',
    disabled:
      doc.data.authDisabled === true ||
      summarizeAdminValue(doc.data.status ?? '').toLowerCase() === 'disabled',
  }
}

export function AdminDataPage({ collectionIdOverride }: AdminDataPageProps) {
  const params = useParams()
  const [searchParams] = useSearchParams()
  const navigate = useNavigate()
  const session = usePortalSession()
  const routeCollectionId = isAdminCollectionId(params.collectionId)
    ? params.collectionId
    : undefined
  const collectionId = collectionIdOverride ?? routeCollectionId ?? 'events'
  const collection = adminCollectionById[collectionId]
  const canRead = canReadAdminCollection(session.adminRole, collectionId)
  const canWrite = canWriteAdminCollection(session.adminRole, collectionId)
  const canDelete = canDeleteAdminCollection(session.adminRole, collectionId)
  const canUpdateAuth = canPerformAdminAction(session.adminRole, 'update_auth_users')
  const readableCollections = useMemo(
    () => adminCollections.filter((item) => canReadAdminCollection(session.adminRole, item.id)),
    [session.adminRole],
  )
  const readableGroups = useMemo(
    () =>
      adminCollectionGroups
        .map((group) => ({
          group,
          collections: readableCollections.filter((item) => item.group === group),
        }))
        .filter(({ collections }) => collections.length > 0),
    [readableCollections],
  )
  const [docs, setDocs] = useState<AdminDocument[]>([])
  const [selectedPath, setSelectedPath] = useState('')
  const [editorText, setEditorText] = useState('{}')
  const [query, setQuery] = useState('')
  const [newDocId, setNewDocId] = useState('')
  const [newDocMode, setNewDocMode] = useState(false)
  const [merge, setMerge] = useState(true)
  const [showAdvancedTools, setShowAdvancedTools] = useState(false)
  const [fieldDrafts, setFieldDrafts] = useState<Record<string, FieldDraftValue>>({})
  const [loading, setLoading] = useState(true)
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [notice, setNotice] = useState<string | null>(null)
  const [authForm, setAuthForm] = useState<AuthFormState>(defaultAuthForm)
  const [authBusy, setAuthBusy] = useState(false)

  const selectedDoc = useMemo(
    () => docs.find((doc) => doc.docPath === selectedPath) ?? docs[0] ?? null,
    [docs, selectedPath],
  )

  const filteredDocs = useMemo(() => {
    const trimmed = query.trim().toLowerCase()
    if (!trimmed) return docs
    return docs.filter((doc) =>
      `${doc.id} ${doc.docPath} ${JSON.stringify(doc.data)}`.toLowerCase().includes(trimmed),
    )
  }, [docs, query])

  const isAuthCollection = collectionId === 'users' || collectionId === 'admins'
  const canCreateById = canWrite && !collection.path.startsWith('collectionGroup:')
  const editableFields = useMemo(() => {
    if (!selectedDoc || newDocMode) return []
    return collection.summaryFields.filter(
      (field) => isEditableAdminValue(selectedDoc.data[field]) && !isLinkedAdminField(field),
    )
  }, [collection.summaryFields, newDocMode, selectedDoc])

  useEffect(() => {
    if (!canRead && readableCollections.length > 0) {
      navigate(`/admin/data/${readableCollections[0].id}`, { replace: true })
    }
  }, [canRead, navigate, readableCollections])

  useEffect(() => {
    let cancelled = false
    async function loadDocuments() {
      if (!canRead) {
        setDocs([])
        setSelectedPath('')
        setEditorText('{}')
        setAuthForm(defaultAuthForm())
        setFieldDrafts({})
        setLoading(false)
        return
      }

      setLoading(true)
      setError(null)
      setNotice(null)
      try {
        const result = await listAdminConsoleDocuments(collectionId, 150)
        if (cancelled) return
        setDocs(result.docs)
        const requestedPath = searchParams.get('doc')
        const nextDoc =
          requestedPath && result.docs.some((doc) => doc.docPath === requestedPath)
            ? result.docs.find((doc) => doc.docPath === requestedPath) ?? null
            : result.docs[0] ?? null
        setSelectedPath(nextDoc?.docPath ?? '')
        setEditorText(nextDoc ? JSON.stringify(nextDoc.data, null, 2) : '{}')
        setAuthForm(nextDoc ? authFormFromDocument(nextDoc) : defaultAuthForm())
        setFieldDrafts(nextDoc ? buildFieldDrafts(nextDoc, collection.summaryFields) : {})
        setNewDocMode(false)
        setShowAdvancedTools(false)
      } catch (caughtError) {
        if (!cancelled) setError(getErrorMessage(caughtError, copy.loadFailed))
      } finally {
        if (!cancelled) setLoading(false)
      }
    }
    void loadDocuments()
    return () => {
      cancelled = true
    }
  }, [canRead, collection.summaryFields, collectionId, searchParams])

  function refresh() {
    if (!canRead) return
    setLoading(true)
    setError(null)
    setNotice(null)
    listAdminConsoleDocuments(collectionId, 150)
      .then((result) => {
        setDocs(result.docs)
        const nextDoc =
          selectedPath && result.docs.some((doc) => doc.docPath === selectedPath)
            ? result.docs.find((doc) => doc.docPath === selectedPath) ?? null
            : result.docs[0] ?? null
        setSelectedPath(nextDoc?.docPath ?? '')
        setEditorText(nextDoc ? JSON.stringify(nextDoc.data, null, 2) : '{}')
        setAuthForm(nextDoc ? authFormFromDocument(nextDoc) : defaultAuthForm())
        setFieldDrafts(nextDoc ? buildFieldDrafts(nextDoc, collection.summaryFields) : {})
        setNewDocMode(false)
        setShowAdvancedTools(false)
      })
      .catch((caughtError) => setError(getErrorMessage(caughtError, copy.loadFailed)))
      .finally(() => setLoading(false))
  }

  function startNewDocument() {
    setNewDocMode(true)
    setSelectedPath('')
    setNewDocId('')
    setEditorText('{}')
    setFieldDrafts({})
    setShowAdvancedTools(true)
    setNotice(null)
    setError(null)
  }

  function selectDocument(doc: AdminDocument) {
    setNewDocMode(false)
    setSelectedPath(doc.docPath)
    setEditorText(JSON.stringify(doc.data, null, 2))
    setAuthForm(authFormFromDocument(doc))
    setFieldDrafts(buildFieldDrafts(doc, collection.summaryFields))
    setShowAdvancedTools(false)
    setNotice(null)
    setError(null)
  }

  async function handleGuidedSave(event: FormEvent) {
    event.preventDefault()
    if (!canWrite || !selectedDoc || editableFields.length === 0) return
    setSaving(true)
    setError(null)
    setNotice(null)
    try {
      const updates = editableFields.reduce<Record<string, AdminJsonValue>>((nextUpdates, field) => {
        const original = selectedDoc.data[field] as EditableAdminValue
        const draft = fieldDrafts[field] ?? (typeof original === 'boolean' ? original : original == null ? '' : String(original))
        nextUpdates[field] = parseFieldDraft(field, original, draft)
        return nextUpdates
      }, {})
      const result = await saveAdminConsoleDocument({
        collectionId,
        docPath: selectedDoc.docPath,
        data: updates,
        merge: true,
      })
      setNotice('Record updated.')
      void trackEvent('admin_action', {
        action: 'record_updated',
        collection_id: collectionId,
        field_count: Object.keys(updates).length,
      }, {
        area: 'admin',
        role: session.adminRole,
      })
      setSelectedPath(result.doc.docPath)
      setDocs((current) =>
        current.map((doc) => (doc.docPath === result.doc.docPath ? result.doc : doc)),
      )
      setEditorText(JSON.stringify(result.doc.data, null, 2))
      setFieldDrafts(buildFieldDrafts(result.doc, collection.summaryFields))
    } catch (caughtError) {
      setError(getErrorMessage(caughtError, 'We could not update this record.'))
    } finally {
      setSaving(false)
    }
  }

  async function handleSave(event: FormEvent) {
    event.preventDefault()
    if (!canWrite) return
    setSaving(true)
    setError(null)
    setNotice(null)
    try {
      const parsed = JSON.parse(editorText) as Record<string, AdminJsonValue>
      if (!parsed || typeof parsed !== 'object' || Array.isArray(parsed)) {
        throw new Error('Advanced details are not in a valid format.')
      }
      const wasNewRecord = newDocMode
      const result = await saveAdminConsoleDocument({
        collectionId,
        docPath: wasNewRecord ? undefined : selectedDoc?.docPath,
        docId: wasNewRecord ? newDocId.trim() || undefined : undefined,
        data: parsed,
        merge,
      })
      setNotice(copy.saved)
      void trackEvent('admin_action', {
        action: wasNewRecord ? 'record_created' : 'record_saved',
        collection_id: collectionId,
        field_count: Object.keys(parsed).length,
        merge,
      }, {
        area: 'admin',
        role: session.adminRole,
      })
      setNewDocMode(false)
      setSelectedPath(result.doc.docPath)
      setDocs((current) => {
        const exists = current.some((doc) => doc.docPath === result.doc.docPath)
        if (!exists) return [result.doc, ...current]
        return current.map((doc) => (doc.docPath === result.doc.docPath ? result.doc : doc))
      })
      setEditorText(JSON.stringify(result.doc.data, null, 2))
      setFieldDrafts(buildFieldDrafts(result.doc, collection.summaryFields))
    } catch (caughtError) {
      setError(getErrorMessage(caughtError, copy.saveFailed))
    } finally {
      setSaving(false)
    }
  }

  async function handleDelete() {
    if (!canDelete || !selectedDoc) return
    const confirmed = window.confirm('Delete this record? This cannot be undone.')
    if (!confirmed) return
    setSaving(true)
    setError(null)
    setNotice(null)
    try {
      await deleteAdminConsoleDocument({ collectionId, docPath: selectedDoc.docPath })
      setNotice('Record deleted.')
      void trackEvent('admin_action', {
        action: 'record_deleted',
        collection_id: collectionId,
      }, {
        area: 'admin',
        role: session.adminRole,
      })
      setDocs((current) => current.filter((doc) => doc.docPath !== selectedDoc.docPath))
      setSelectedPath('')
      setEditorText('{}')
      setFieldDrafts({})
    } catch (caughtError) {
      setError(getErrorMessage(caughtError, 'We could not delete this record.'))
    } finally {
      setSaving(false)
    }
  }

  async function handleAuthUpdate(event: FormEvent) {
    event.preventDefault()
    if (!canUpdateAuth || !selectedDoc) return
    setAuthBusy(true)
    setError(null)
    setNotice(null)
    try {
      await updateAdminAuthUser({
        uid: selectedDoc.id,
        email: authForm.email.trim() || undefined,
        displayName: authForm.displayName.trim() || undefined,
        password: authForm.password || undefined,
        disabled: authForm.disabled,
      })
      setNotice('Login access updated.')
      void trackEvent('admin_action', {
        action: 'auth_updated',
        collection_id: collectionId,
        disabled: authForm.disabled,
      }, {
        area: 'admin',
        role: session.adminRole,
      })
      setAuthForm((current) => ({ ...current, password: '' }))
    } catch (caughtError) {
      setError(getErrorMessage(caughtError, 'We could not update this login access.'))
    } finally {
      setAuthBusy(false)
    }
  }

  async function handlePlaceVerificationReview(decision: 'approve' | 'reject') {
    if (!selectedDoc || collectionId !== 'place_verifications') return
    const label = decision === 'approve' ? 'approve' : 'reject'
    const reviewNotes = window.prompt(`Optional notes for this ${label} decision:`) ?? ''
    setSaving(true)
    setError(null)
    setNotice(null)
    try {
      const result = await reviewPlaceVerification({
        requestId: selectedDoc.id,
        decision,
        reviewNotes,
      })
      setNotice(`Place verification ${result.data.status}.`)
      refresh()
    } catch (caughtError) {
      setError(getErrorMessage(caughtError, 'We could not review this verification request.'))
    } finally {
      setSaving(false)
    }
  }

  if (!canRead) {
    return (
      <div className="page-loader">
        <p>This admin role cannot use that work area.</p>
        <p className="text-subtle">Choose another available area from the admin sidebar.</p>
      </div>
    )
  }

  return (
    <div className="admin-data-page">
      <section className="admin-page-header admin-page-header--data">
        <div>
          <p className="eyebrow">Work area</p>
          <h2>{collection.label}</h2>
          <p>{collection.feature}</p>
          <div className="admin-meta-row">
            <span>{getAdminGroupLabel(collection.group)}</span>
            <span>{docs.length} records</span>
          </div>
        </div>
        <div className="admin-page-header__actions">
          <button className="button button--secondary" disabled={loading} onClick={refresh} type="button">
            <RefreshCw size={16} aria-hidden />
            Refresh
          </button>
        </div>
      </section>

      {error ? <p className="form-error">{error}</p> : null}
      {notice ? <p className="form-success">{notice}</p> : null}

      <section className="admin-collection-toolbar">
        <label className="admin-collection-select">
          <span>Choose area</span>
          <select
            onChange={(event) => {
              navigate(`/admin/data/${event.target.value}`)
            }}
            value={collectionId}
          >
            {readableGroups.map(({ group, collections }) => (
              <optgroup key={group} label={getAdminGroupLabel(group)}>
                {collections.map((item) => (
                  <option key={item.id} value={item.id}>
                    {item.label}
                  </option>
                ))}
              </optgroup>
            ))}
          </select>
        </label>
        <div className="admin-collection-toolbar__meta">
          <strong>Current area</strong>
          <span>{getAdminGroupLabel(collection.group)}</span>
        </div>
      </section>

      <section className="admin-data-layout">
        <aside className="admin-data-list panel">
          <div className="admin-data-list__header">
            <div>
              <p className="eyebrow">Records</p>
              <strong>{filteredDocs.length} shown</strong>
            </div>
          </div>
          <div className="admin-data-list__toolbar">
            <label className="admin-search">
              <Search size={15} aria-hidden />
              <input
                aria-label="Search records"
                onChange={(event) => setQuery(event.target.value)}
                placeholder="Search records"
                type="search"
                value={query}
              />
            </label>
          </div>
          {loading ? (
            <div className="admin-empty-inline">{copy.loading}</div>
          ) : filteredDocs.length === 0 ? (
            <div className="admin-empty-inline">No records found.</div>
          ) : (
            <div className="admin-record-list">
              {filteredDocs.map((doc) => (
                <button
                  className={doc.docPath === selectedDoc?.docPath ? 'is-selected' : ''}
                  key={doc.docPath}
                  onClick={() => selectDocument(doc)}
                  type="button"
                >
                  <ListChecks size={15} aria-hidden />
                  <span>
                    <strong>{getAdminRecordTitle(doc, collection.summaryFields)}</strong>
                    <small>{getAdminRecordSubtitle(doc, collection.summaryFields)}</small>
                  </span>
                </button>
              ))}
            </div>
          )}
        </aside>

        <main className="admin-data-editor panel">
          <div className="panel__header">
            <div>
              <p className="eyebrow">{newDocMode ? 'Create record' : 'Record details'}</p>
              <h3>
                {newDocMode
                  ? `Add to ${collection.label}`
                  : selectedDoc
                    ? getAdminRecordTitle(selectedDoc, collection.summaryFields)
                    : 'No record selected'}
              </h3>
            </div>
            <div className="admin-data-editor__actions">
              {canDelete && selectedDoc && !newDocMode ? (
                <button className="button button--ghost" disabled={saving} onClick={handleDelete} type="button">
                  <Trash2 size={15} aria-hidden />
                  Delete
                </button>
              ) : null}
            </div>
          </div>

          {selectedDoc && !newDocMode ? (
            <section className="admin-document-summary">
              <h4>Key details</h4>
              <div className="admin-summary-grid">
                {collection.summaryFields.map((field) => (
                  <div key={field}>
                    <span>{humanizeAdminField(field)}</span>
                    <strong>{summarizeAdminFieldValue(field, selectedDoc.data[field])}</strong>
                  </div>
                ))}
              </div>
            </section>
          ) : null}

          {selectedDoc && !newDocMode && collectionId === 'place_verifications' ? (
            <section className="admin-guided-editor">
              <div className="admin-editor-section-header">
                <div>
                  <p className="eyebrow">Verification review</p>
                  <h4>Approve location ownership</h4>
                </div>
                <div className="admin-data-editor__actions">
                  <button
                    className="button button--primary"
                    disabled={saving}
                    onClick={() => handlePlaceVerificationReview('approve')}
                    type="button"
                  >
                    <CheckCircle2 size={16} aria-hidden />
                    Approve
                  </button>
                  <button
                    className="button button--ghost"
                    disabled={saving}
                    onClick={() => handlePlaceVerificationReview('reject')}
                    type="button"
                  >
                    <XCircle size={16} aria-hidden />
                    Reject
                  </button>
                </div>
              </div>
              <p className="text-subtle">
                Approval marks the place as verified and unlocks paid subscriber push and official venue ownership tools.
              </p>
            </section>
          ) : null}

          {canWrite && selectedDoc && !newDocMode && editableFields.length > 0 ? (
            <form className="admin-guided-editor" onSubmit={handleGuidedSave}>
              <div className="admin-editor-section-header">
                <div>
                  <p className="eyebrow">Update</p>
                  <h4>Key details</h4>
                </div>
                <button className="button button--primary" disabled={saving || !canWrite} type="submit">
                  <Save size={16} aria-hidden />
                  {saving ? 'Saving...' : 'Save changes'}
                </button>
              </div>
              <div className="admin-guided-editor__grid">
                {editableFields.map((field) => {
                  const original = selectedDoc.data[field] as EditableAdminValue
                  const draft = fieldDrafts[field] ?? (typeof original === 'boolean' ? original : '')
                  if (typeof original === 'boolean') {
                    return (
                      <label className="admin-toggle admin-toggle--boxed" key={field}>
                        <input
                          checked={Boolean(draft)}
                          disabled={!canWrite}
                          onChange={(event) =>
                            setFieldDrafts((current) => ({ ...current, [field]: event.target.checked }))
                          }
                          type="checkbox"
                        />
                        {humanizeAdminField(field)}
                      </label>
                    )
                  }
                  return (
                    <label className="input-group" key={field}>
                      <span className="input-group__label">{humanizeAdminField(field)}</span>
                      <input
                        disabled={!canWrite}
                        onChange={(event) =>
                          setFieldDrafts((current) => ({ ...current, [field]: event.target.value }))
                        }
                        type={typeof original === 'number' ? 'number' : 'text'}
                        value={typeof draft === 'boolean' ? String(draft) : draft}
                      />
                    </label>
                  )
                })}
              </div>
            </form>
          ) : null}

          {canWrite ? (
            <section className="admin-advanced-tools">
              <div className="admin-advanced-tools__header">
                <div>
                  <p className="eyebrow">Support tools</p>
                  <h4>Extra actions</h4>
                </div>
                <div className="admin-data-editor__actions">
                  <button
                    className="button button--secondary"
                    onClick={() => setShowAdvancedTools((current) => !current)}
                    type="button"
                  >
                    {showAdvancedTools ? 'Hide options' : 'More options'}
                  </button>
                </div>
              </div>
              {showAdvancedTools || newDocMode ? (
                <form className="admin-json-editor" onSubmit={handleSave}>
                  {canCreateById && !newDocMode ? (
                    <button className="button button--secondary" onClick={startNewDocument} type="button">
                      <Plus size={16} aria-hidden />
                      Create new record
                    </button>
                  ) : null}
                  {newDocMode && canCreateById ? (
                    <label className="input-group">
                      <span className="input-group__label">Reference name</span>
                      <input
                        onChange={(event) => setNewDocId(event.target.value)}
                        placeholder="Leave blank to create one automatically"
                        value={newDocId}
                      />
                    </label>
                  ) : null}
                  <label className="admin-toggle">
                    <input
                      checked={merge}
                      onChange={(event) => setMerge(event.target.checked)}
                      type="checkbox"
                    />
                    Keep other details when saving
                  </label>
                  <textarea
                    aria-label="Full record details"
                    disabled={!canWrite || (!selectedDoc && !newDocMode)}
                    onChange={(event) => setEditorText(event.target.value)}
                    spellCheck={false}
                    value={editorText}
                  />
                  <div className="admin-json-editor__footer">
                    <small>Use this only when support has given you exact details to enter.</small>
                    <button
                      className="button button--primary"
                      disabled={saving || !canWrite || (!selectedDoc && !newDocMode)}
                      type="submit"
                    >
                      <Save size={16} aria-hidden />
                      {saving ? 'Saving...' : 'Save'}
                    </button>
                  </div>
                </form>
              ) : null}
            </section>
          ) : null}

          {isAuthCollection && selectedDoc && !newDocMode && canUpdateAuth ? (
            <form className="admin-auth-tools" onSubmit={handleAuthUpdate}>
              <div>
                <p className="eyebrow">Login access</p>
                <h4>Update this person's sign-in</h4>
              </div>
              <div className="admin-auth-tools__grid">
                <label className="input-group">
                  <span className="input-group__label">Email</span>
                  <input
                    onChange={(event) =>
                      setAuthForm((current) => ({ ...current, email: event.target.value }))
                    }
                    type="email"
                    value={authForm.email}
                  />
                </label>
                <label className="input-group">
                  <span className="input-group__label">Display name</span>
                  <input
                    onChange={(event) =>
                      setAuthForm((current) => ({ ...current, displayName: event.target.value }))
                    }
                    value={authForm.displayName}
                  />
                </label>
                <label className="input-group">
                  <span className="input-group__label">New password</span>
                  <input
                    onChange={(event) =>
                      setAuthForm((current) => ({ ...current, password: event.target.value }))
                    }
                    placeholder="Leave blank to keep current password"
                    type="password"
                    value={authForm.password}
                  />
                </label>
                <label className="admin-toggle admin-toggle--boxed">
                  <input
                    checked={authForm.disabled}
                    onChange={(event) =>
                      setAuthForm((current) => ({ ...current, disabled: event.target.checked }))
                    }
                    type="checkbox"
                  />
                  Block this person from signing in
                </label>
              </div>
              <button className="button button--secondary" disabled={authBusy} type="submit">
                <KeyRound size={16} aria-hidden />
                {authBusy ? 'Updating...' : 'Save login changes'}
              </button>
            </form>
          ) : null}
        </main>
      </section>
    </div>
  )
}
