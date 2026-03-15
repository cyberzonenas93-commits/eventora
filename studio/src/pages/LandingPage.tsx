import { useMemo, useState } from 'react'
import { Navigate } from 'react-router-dom'

import { usePortalSession } from '../lib/portalSession'

type AuthMode = 'signup' | 'login'

export function LandingPage() {
  const session = usePortalSession()
  const [mode, setMode] = useState<AuthMode>('signup')
  const [error, setError] = useState('')
  const [isBusy, setIsBusy] = useState(false)
  const [signup, setSignup] = useState({
    displayName: '',
    email: '',
    phone: '',
    password: '',
    confirmPassword: '',
  })
  const [login, setLogin] = useState({
    email: '',
    password: '',
  })

  const signupValid = useMemo(
    () =>
      signup.displayName.trim().length >= 2 &&
      signup.email.includes('@') &&
      signup.password.length >= 6 &&
      signup.password === signup.confirmPassword,
    [signup],
  )
  const loginValid = login.email.includes('@') && login.password.length >= 6

  if (session.user) {
    if (session.status === 'approved') {
      return <Navigate replace to="/overview" />
    }
    if (session.status === 'submitted' || session.status === 'under_review') {
      return <Navigate replace to="/review" />
    }
    return <Navigate replace to="/setup/account" />
  }

  async function handleSubmit() {
    setError('')
    setIsBusy(true)
    try {
      if (mode === 'signup') {
        await session.signUp({
          displayName: signup.displayName,
          email: signup.email,
          password: signup.password,
          phone: signup.phone,
        })
      } else {
        await session.signIn(login.email, login.password)
      }
    } catch (caughtError) {
      setError(
        caughtError instanceof Error
          ? caughtError.message
          : 'Could not complete authentication.',
      )
    } finally {
      setIsBusy(false)
    }
  }

  return (
    <main className="landing-page">
      <section className="landing-hero">
        <span className="eyebrow">Eventora Studio</span>
        <h1>
          The organizer side of Eventora, built for approvals, publishing control,
          and payout-ready operations.
        </h1>
        <p>
          Sign up, submit your organizer profile, and let superadmins approve your
          team before you publish and sell on Eventora.
        </p>
        <div className="landing-points">
          <div>
            <strong>Approval-led onboarding</strong>
            <span>Verification, payout setup, and review before go-live.</span>
          </div>
          <div>
            <strong>Connected to the app</strong>
            <span>Approval unlocks organizer features across Eventora surfaces.</span>
          </div>
          <div>
            <strong>Event operations ready</strong>
            <span>Overview, event creation, ticketing setup, and organizer settings.</span>
          </div>
        </div>
      </section>

      <section className="auth-panel">
        <div className="auth-toggle">
          <button
            className={mode === 'signup' ? 'is-active' : ''}
            onClick={() => setMode('signup')}
            type="button"
          >
            Create organizer account
          </button>
          <button
            className={mode === 'login' ? 'is-active' : ''}
            onClick={() => setMode('login')}
            type="button"
          >
            Sign in
          </button>
        </div>

        {mode === 'signup' ? (
          <div className="auth-form">
            <label>
              Display name
              <input
                onChange={(event) =>
                  setSignup((current) => ({
                    ...current,
                    displayName: event.target.value,
                  }))
                }
                placeholder="Your full name"
                value={signup.displayName}
              />
            </label>
            <label>
              Email
              <input
                onChange={(event) =>
                  setSignup((current) => ({
                    ...current,
                    email: event.target.value,
                  }))
                }
                placeholder="you@eventora.app"
                type="email"
                value={signup.email}
              />
            </label>
            <label>
              Phone (optional at signup)
              <input
                onChange={(event) =>
                  setSignup((current) => ({
                    ...current,
                    phone: event.target.value,
                  }))
                }
                placeholder="+233 24 000 0000"
                value={signup.phone}
              />
            </label>
            <label>
              Password
              <input
                onChange={(event) =>
                  setSignup((current) => ({
                    ...current,
                    password: event.target.value,
                  }))
                }
                type="password"
                value={signup.password}
              />
            </label>
            <label>
              Confirm password
              <input
                onChange={(event) =>
                  setSignup((current) => ({
                    ...current,
                    confirmPassword: event.target.value,
                  }))
                }
                type="password"
                value={signup.confirmPassword}
              />
            </label>
          </div>
        ) : (
          <div className="auth-form">
            <label>
              Email
              <input
                onChange={(event) =>
                  setLogin((current) => ({ ...current, email: event.target.value }))
                }
                placeholder="you@eventora.app"
                type="email"
                value={login.email}
              />
            </label>
            <label>
              Password
              <input
                onChange={(event) =>
                  setLogin((current) => ({ ...current, password: event.target.value }))
                }
                type="password"
                value={login.password}
              />
            </label>
          </div>
        )}

        {error ? <p className="form-error">{error}</p> : null}

        <button
          className="button button--primary button--full"
          disabled={isBusy || !(mode === 'signup' ? signupValid : loginValid)}
          onClick={handleSubmit}
          type="button"
        >
          {isBusy
            ? 'Working...'
            : mode === 'signup'
            ? 'Continue to organizer setup'
            : 'Open Eventora Studio'}
        </button>
      </section>
    </main>
  )
}
