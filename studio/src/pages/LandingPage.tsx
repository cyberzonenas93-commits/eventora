import { useMemo, useRef, useState } from 'react'
import { Navigate } from 'react-router-dom'

import { usePortalSession } from '../lib/portalSession'

type AuthMode = 'signup' | 'login'

export function LandingPage() {
  const session = usePortalSession()
  const isAdminHost =
    typeof window !== 'undefined' &&
    (window.location.hostname.includes('eventora-admin') ||
      window.location.hostname.startsWith('admin.'))
  const [mode, setMode] = useState<AuthMode>('signup')
  const [error, setError] = useState('')
  const [isBusy, setIsBusy] = useState(false)
  const [showSignupPassword, setShowSignupPassword] = useState(false)
  const [showSignupConfirmPassword, setShowSignupConfirmPassword] = useState(false)
  const [showLoginPassword, setShowLoginPassword] = useState(false)
  const loginEmailRef = useRef<HTMLInputElement | null>(null)
  const loginPasswordRef = useRef<HTMLInputElement | null>(null)
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
  const hasPasswordLength = signup.password.length >= 8
  const hasPasswordCase =
    signup.password.toLowerCase() !== signup.password &&
    signup.password.toUpperCase() !== signup.password
  const hasPasswordNumber = /\d/.test(signup.password)

  const signupValid = useMemo(
    () =>
      signup.displayName.trim().length >= 2 &&
      signup.email.includes('@') &&
      hasPasswordLength &&
      hasPasswordCase &&
      hasPasswordNumber &&
      signup.password === signup.confirmPassword,
    [hasPasswordCase, hasPasswordLength, hasPasswordNumber, signup],
  )
  const loginValid = login.email.includes('@') && login.password.length >= 6

  if (session.user) {
    if (isAdminHost && session.isAdmin) {
      return <Navigate replace to="/superadmin/approvals" />
    }
    if (session.isSuperAdmin) {
      return <Navigate replace to="/superadmin/approvals" />
    }
    return <Navigate replace to="/overview" />
  }

  async function handleSubmit() {
    setError('')

    if (!isAdminHost && mode === 'signup' && !signupValid) {
      setError('Please complete all required fields and use a stronger password.')
      return
    }

    if (!isAdminHost && mode === 'login' && !loginValid) {
      setError('Enter a valid email address and password to continue.')
      return
    }

    setIsBusy(true)
    try {
      if (!isAdminHost && mode === 'signup') {
        await session.signUp({
          displayName: signup.displayName,
          email: signup.email,
          password: signup.password,
          phone: signup.phone,
        })
      } else {
        const email = login.email.trim() || loginEmailRef.current?.value.trim() || ''
        const password = login.password || loginPasswordRef.current?.value || ''

        if (!email || !password) {
          throw new Error('Enter your admin email address and password to continue.')
        }

        await session.signIn(email, password)
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
    <main className="landing-page landing-page--reference">
      <section className="landing-hero landing-hero--reference">
        <div className="landing-hero__copy landing-hero__copy--reference">
          <div className="landing-brand-lockup">
            <div className="studio-brand studio-brand--hero">
              <div className="studio-brand__mark">E</div>
              <div>
                <strong>Eventora Studio</strong>
                <span>{isAdminHost ? 'Operations Console' : 'Creator Workspace'}</span>
              </div>
            </div>
            <span className="eyebrow">{isAdminHost ? 'Platform operations' : 'Premium event platform'}</span>
          </div>
          <h1>{isAdminHost ? 'Run approvals from one control room.' : 'Built to sell out.'}</h1>
          <p>
            {isAdminHost
              ? 'Sign in as a superadmin to review organizer activity, approve teams, and keep Eventora operations moving from one secure dashboard.'
              : 'Create your Eventora Studio account, open your workspace instantly, and launch your first event with premium tools for ticketing, payouts, promotion, and guest experience.'}
          </p>
          <div className="hero-chip-row">
            {isAdminHost ? (
              <>
                <span>Organizer approvals</span>
                <span>Review notes</span>
                <span>Provisioning control</span>
              </>
            ) : (
                <>
                  <span>Instant workspace</span>
                  <span>Event publishing</span>
                  <span>Guest-ready ticketing</span>
                </>
              )}
            </div>

          <div className="reference-story-card">
            <strong>{isAdminHost ? 'What superadmins control' : 'What happens after signup'}</strong>
            <ol className="merchant-timeline merchant-timeline--stacked">
              {isAdminHost ? (
                <>
                  <li>View every organizer application in one queue</li>
                  <li>Mark applications under review with notes</li>
                  <li>Approve or reject submissions from the web dashboard</li>
                  <li>Provision organizer access through the existing backend flow</li>
                </>
              ) : (
                <>
                  <li>Create your organizer account</li>
                  <li>Open your workspace right away</li>
                  <li>Set your brand, payouts, and launch preferences</li>
                  <li>Create and publish your first event from the same dashboard</li>
                </>
              )}
            </ol>
          </div>

          <div className="merchant-proof-grid merchant-proof-grid--reference">
            <article className="merchant-proof-card merchant-proof-card--warm">
              <strong>{isAdminHost ? 'One queue' : 'Single path'}</strong>
              <p>
                {isAdminHost
                  ? 'Superadmins can review submitted applications without leaving the web dashboard.'
                  : 'Account creation, workspace setup, event publishing, and payouts stay inside one clean creator flow.'}
              </p>
            </article>
            <article className="merchant-proof-card merchant-proof-card--mint">
              <strong>{isAdminHost ? 'Live status control' : 'Launch with confidence'}</strong>
              <p>
                {isAdminHost
                  ? 'Approval decisions, review notes, and organization provisioning stay tied to the same backend workflow.'
                  : 'Brand setup, payouts, promotion, and event creation are available immediately without approval bottlenecks.'}
              </p>
            </article>
          </div>
        </div>
      </section>

      <section className="auth-panel auth-panel--reference">
        <div className="auth-panel__header">
          <p className="eyebrow">{isAdminHost ? 'Superadmin access' : 'Get Started'}</p>
          <h2>
            {isAdminHost
              ? 'Sign in to the approvals dashboard'
              : mode === 'signup'
                ? 'Create your Eventora Studio account'
                : 'Welcome back'}
          </h2>
          <p>
            {isAdminHost
              ? 'Only superadmins can review organizer applications and provision approved teams from this site.'
              : mode === 'signup'
                ? 'Create your account to open Eventora Studio instantly and start building your first live event.'
                : 'Sign in to return to your workspace, update your brand, or launch your next event.'}
          </p>
        </div>

        {isAdminHost ? null : (
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
        )}

        {!isAdminHost && mode === 'signup' ? (
          <div className="auth-form auth-form--reference">
            <label className="field">
              <span>Organizer / Brand Name *</span>
              <input
                onChange={(event) =>
                  setSignup((current) => ({
                    ...current,
                    displayName: event.target.value,
                  }))
                }
                placeholder="e.g., Strictly Soul Ghana"
                value={signup.displayName}
              />
            </label>
            <label className="field">
              <span>Phone Number *</span>
              <input
                onChange={(event) =>
                  setSignup((current) => ({
                    ...current,
                    phone: event.target.value,
                  }))
                }
                placeholder="024 123 4567"
                value={signup.phone}
              />
              <small>Used for account security and payout notifications</small>
            </label>
            <label className="field">
              <span>Email Address *</span>
              <input
                onChange={(event) =>
                  setSignup((current) => ({
                    ...current,
                    email: event.target.value,
                  }))
                }
                placeholder="your@email.com"
                type="email"
                value={signup.email}
              />
              <small>We&apos;ll send event updates and important notifications here</small>
            </label>
            <label className="field">
              <span>Password *</span>
              <div className="password-field">
                <input
                  onChange={(event) =>
                    setSignup((current) => ({
                      ...current,
                      password: event.target.value,
                    }))
                  }
                  placeholder="Create a strong password"
                  type={showSignupPassword ? 'text' : 'password'}
                  value={signup.password}
                />
                <button
                  className="password-toggle"
                  onClick={() => setShowSignupPassword((current) => !current)}
                  type="button"
                >
                  {showSignupPassword ? 'Hide' : 'Show'}
                </button>
              </div>
              <div className="password-rules">
                <p>Password must include:</p>
                <ul>
                  <li className={hasPasswordLength ? 'is-valid' : ''}>At least 8 characters</li>
                  <li className={hasPasswordCase ? 'is-valid' : ''}>Uppercase and lowercase letters</li>
                  <li className={hasPasswordNumber ? 'is-valid' : ''}>At least one number</li>
                </ul>
              </div>
            </label>
            <label className="field">
              <span>Confirm Password *</span>
              <div className="password-field">
                <input
                  onChange={(event) =>
                    setSignup((current) => ({
                      ...current,
                      confirmPassword: event.target.value,
                    }))
                  }
                  type={showSignupConfirmPassword ? 'text' : 'password'}
                  value={signup.confirmPassword}
                />
                <button
                  className="password-toggle"
                  onClick={() => setShowSignupConfirmPassword((current) => !current)}
                  type="button"
                >
                  {showSignupConfirmPassword ? 'Hide' : 'Show'}
                </button>
              </div>
            </label>
          </div>
        ) : (
          <div className="auth-form auth-form--reference">
            <label className="field">
              <span>Email Address *</span>
              <input
                ref={loginEmailRef}
                onChange={(event) =>
                  setLogin((current) => ({ ...current, email: event.target.value }))
                }
                placeholder="your@email.com"
                type="email"
                value={login.email}
              />
            </label>
            <label className="field">
              <span>Password *</span>
              <div className="password-field">
                <input
                  ref={loginPasswordRef}
                  onChange={(event) =>
                    setLogin((current) => ({ ...current, password: event.target.value }))
                  }
                  placeholder="Enter your password"
                  type={showLoginPassword ? 'text' : 'password'}
                  value={login.password}
                />
                <button
                  className="password-toggle"
                  onClick={() => setShowLoginPassword((current) => !current)}
                  type="button"
                >
                  {showLoginPassword ? 'Hide' : 'Show'}
                </button>
              </div>
            </label>
          </div>
        )}

        {error ? <p className="form-error">{error}</p> : null}

        <button
          className="button button--primary button--full"
          disabled={isBusy}
          onClick={handleSubmit}
          type="button"
        >
          {isBusy
            ? 'Working...'
            : !isAdminHost && mode === 'signup'
              ? 'Create organizer account'
              : isAdminHost
                ? 'Sign in to approvals'
                : 'Sign in to Studio'}
        </button>

        <div className="auth-panel__footer">
          <p>
            By continuing, you agree to our{' '}
            <button className="inline-link-button" type="button">
              Terms of Service
            </button>{' '}
            and{' '}
            <button className="inline-link-button" type="button">
              Privacy Policy
            </button>
          </p>
        </div>
      </section>
    </main>
  )
}
