import { useCallback, useEffect, useState, type FormEvent } from 'react'
import { useNavigate, useParams, useSearchParams } from 'react-router-dom'
import { httpsCallable } from 'firebase/functions'
import { ShieldCheck } from 'lucide-react'

import { functions } from '../firebaseFunctions'
import { getErrorMessage } from '../lib/errorMessages'
import { usePortalSession } from '../lib/portalSession'

const acceptEventTeamInvite = httpsCallable<
  { inviteId: string; token: string },
  { success: boolean; eventId: string; redirectPath: string }
>(functions, 'acceptEventTeamInvite')

export function TeamInviteAcceptPage() {
  const params = useParams()
  const [searchParams] = useSearchParams()
  const navigate = useNavigate()
  const session = usePortalSession()
  const inviteId = params.inviteId || ''
  const token = searchParams.get('token') || ''
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [displayName, setDisplayName] = useState('')
  const [mode, setMode] = useState<'signin' | 'signup'>('signin')
  const [submitting, setSubmitting] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [message, setMessage] = useState<string | null>(null)

  const acceptInvite = useCallback(async () => {
    setSubmitting(true)
    setError(null)
    try {
      const result = await acceptEventTeamInvite({ inviteId, token })
      setMessage('Invite accepted. Opening your staff workspace…')
      navigate(result.data.redirectPath || `/staff/${result.data.eventId}`, { replace: true })
    } catch (err) {
      setError(getErrorMessage(err, 'Could not accept this invite.'))
    } finally {
      setSubmitting(false)
    }
  }, [inviteId, navigate, token])

  useEffect(() => {
    if (!session.user || !inviteId || !token) return
    void acceptInvite()
  }, [acceptInvite, session.user, inviteId, token])

  async function handleAuth(e: FormEvent) {
    e.preventDefault()
    setSubmitting(true)
    setError(null)
    try {
      if (mode === 'signin') {
        await session.signIn(email, password)
      } else {
        await session.signUp({
          displayName: displayName.trim() || email.split('@')[0] || 'Event staff',
          email,
          password,
        })
      }
    } catch (err) {
      setError(getErrorMessage(err, mode === 'signin' ? 'Could not sign in.' : 'Could not create account.'))
      setSubmitting(false)
    }
  }

  return (
    <main className="landing-page invite-page">
      <section className="auth-panel auth-panel--centered invite-card">
        <div className="studio-brand">
          <div className="studio-brand__mark" aria-hidden>
            <img src="/logo-mark.png" alt="" />
          </div>
          <div>
            <strong>Vennuzo Team</strong>
            <span>Event operations invite</span>
          </div>
        </div>
        <div className="auth-panel__header">
          <p className="eyebrow">Invitation</p>
          <h2>Join the event team.</h2>
          <p>Sign in or create your account with the invited email address, then Vennuzo will open your staff workspace.</p>
        </div>
        {!inviteId || !token ? (
          <div className="notice notice--error">This invite link is incomplete.</div>
        ) : session.user ? (
          <div className="invite-card__accepting">
            <ShieldCheck size={28} aria-hidden />
            <p>{message || 'Accepting your invite…'}</p>
            {error && <div className="notice notice--error">{error}</div>}
            <button className="button button--primary" disabled={submitting} onClick={() => void acceptInvite()} type="button">
              Try again
            </button>
          </div>
        ) : (
          <form className="checkout__form" onSubmit={handleAuth}>
            {mode === 'signup' && (
              <label className="checkout__label">
                Name
                <input className="checkout__input" value={displayName} onChange={(e) => setDisplayName(e.target.value)} />
              </label>
            )}
            <label className="checkout__label">
              Email
              <input className="checkout__input" type="email" value={email} onChange={(e) => setEmail(e.target.value)} required />
            </label>
            <label className="checkout__label">
              Password
              <input className="checkout__input" type="password" value={password} onChange={(e) => setPassword(e.target.value)} required />
            </label>
            {error && <div className="notice notice--error">{error}</div>}
            <button className="button button--primary" disabled={submitting || !email.trim() || !password.trim()} type="submit">
              {mode === 'signin' ? 'Sign in and accept' : 'Create account and accept'}
            </button>
            <button
              className="button button--ghost"
              onClick={() => setMode((current) => current === 'signin' ? 'signup' : 'signin')}
              type="button"
            >
              {mode === 'signin' ? 'Create an account instead' : 'I already have an account'}
            </button>
          </form>
        )}
      </section>
    </main>
  )
}
