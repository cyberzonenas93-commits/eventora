import { useMemo, useRef, useState } from 'react'
import { Navigate } from 'react-router-dom'
import { BarChart3, Banknote, LockKeyhole, Megaphone, ShieldCheck, TicketCheck } from 'lucide-react'

import { trackEvent } from '../lib/analytics'
import { copy } from '../lib/copy'
import { getErrorMessage } from '../lib/errorMessages'
import { usePortalSession } from '../lib/portalSession'

type AuthMode = 'signup' | 'login'

export function LandingPage() {
  const session = usePortalSession()
  const isAdminMode =
    typeof window !== 'undefined' &&
    (window.location.hostname.includes('vennuzo-admin') ||
      window.location.hostname.startsWith('admin.') ||
      window.location.pathname.startsWith('/admin') ||
      window.location.pathname.startsWith('/superadmin'))
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
    contactPerson: '',
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
      signup.contactPerson.trim().length >= 2 &&
      signup.email.includes('@') &&
      hasPasswordLength &&
      hasPasswordCase &&
      hasPasswordNumber &&
      signup.password === signup.confirmPassword,
    [hasPasswordCase, hasPasswordLength, hasPasswordNumber, signup],
  )
  const loginValid = login.email.includes('@') && login.password.length >= 6

  if (session.user) {
    if (isAdminMode && session.isAdmin) {
      return <Navigate replace to="/admin/overview" />
    }
    if (session.isAdmin) {
      return <Navigate replace to="/admin/overview" />
    }
    return <Navigate replace to="/studio/overview" />
  }

  async function handleSubmit() {
    setError('')

    if (!isAdminMode && mode === 'signup' && !signupValid) {
      setError(copy.completeRequiredFields)
      return
    }

    if (!isAdminMode && mode === 'login' && !loginValid) {
      setError(copy.validEmailAndPassword)
      return
    }

    setIsBusy(true)
    try {
      if (!isAdminMode && mode === 'signup') {
        await session.signUp({
          displayName: signup.displayName,
          contactPerson: signup.contactPerson,
          email: signup.email,
          password: signup.password,
          phone: signup.phone,
        })
        void trackEvent('sign_up', { method: 'password' }, { area: 'studio' })
      } else {
        const email = login.email.trim() || loginEmailRef.current?.value.trim() || ''
        const password = login.password || loginPasswordRef.current?.value || ''

        if (!email || !password) {
          throw new Error('Enter your admin email address and password to continue.')
        }

        await session.signIn(email, password)
        void trackEvent('login', { method: 'password', admin: isAdminMode }, { area: isAdminMode ? 'admin' : 'studio' })
      }
    } catch (caughtError) {
      setError(getErrorMessage(caughtError, copy.authFailed))
    } finally {
      setIsBusy(false)
    }
  }

  async function handleGoogle() {
    setError('')
    setIsBusy(true)
    try {
      await session.signInWithGoogle({ seedOrganizerProfile: !isAdminMode })
      void trackEvent('login', { method: 'google', admin: isAdminMode }, { area: isAdminMode ? 'admin' : 'studio' })
    } catch (caughtError) {
      setError(getErrorMessage(caughtError, copy.googleSignInFailed))
    } finally {
      setIsBusy(false)
    }
  }

  async function handleApple() {
    setError('')
    setIsBusy(true)
    try {
      await session.signInWithApple({ seedOrganizerProfile: !isAdminMode })
      void trackEvent('login', { method: 'apple', admin: isAdminMode }, { area: isAdminMode ? 'admin' : 'studio' })
    } catch (caughtError) {
      const message = getErrorMessage(caughtError, copy.appleSignInFailed)
      setError(
        /auth\/operation-not-allowed|operation-not-allowed/i.test(message)
          ? copy.appleSignInNotConfigured
          : message,
      )
    } finally {
      setIsBusy(false)
    }
  }

  if (isAdminMode) {
    return (
      <main className="admin-login-page">
        <section className="admin-login-shell" aria-label="Vennuzo admin sign in">
          <div className="admin-login-brand">
            <div className="studio-brand">
              <div className="studio-brand__mark">
                <img src="/logo-mark.png" alt="" />
              </div>
              <div>
                <strong>Vennuzo Admin</strong>
                <span>Operations console</span>
              </div>
            </div>
            <div>
              <p className="eyebrow">Restricted access</p>
              <h1>Platform control room</h1>
            </div>
            <div className="admin-login-status">
              <span>
                <LockKeyhole size={15} aria-hidden />
                Admin-only workspace
              </span>
              <span>admin.vennuzo.com</span>
            </div>
          </div>

          <form
            className="admin-login-form"
            onSubmit={(event) => {
              event.preventDefault()
              void handleSubmit()
            }}
          >
            <div className="auth-panel__header">
              <p className="eyebrow">Sign in</p>
              <h2>Access Vennuzo Admin</h2>
            </div>

            <div className="auth-form auth-form--reference">
              <label className="field">
                <span>Email address</span>
                <input
                  ref={loginEmailRef}
                  aria-label="Email address"
                  autoComplete="email"
                  onChange={(event) =>
                    setLogin((current) => ({ ...current, email: event.target.value }))
                  }
                  placeholder="admin@vennuzo.com"
                  type="email"
                  value={login.email}
                />
              </label>
              <label className="field">
                <span>Password</span>
                <div className="password-field">
                  <input
                    ref={loginPasswordRef}
                    aria-label="Password"
                    autoComplete="current-password"
                    onChange={(event) =>
                      setLogin((current) => ({ ...current, password: event.target.value }))
                    }
                    placeholder="Enter password"
                    type={showLoginPassword ? 'text' : 'password'}
                    value={login.password}
                  />
                  <button
                    aria-label={showLoginPassword ? 'Hide password' : 'Show password'}
                    className="password-toggle"
                    onClick={() => setShowLoginPassword((current) => !current)}
                    type="button"
                  >
                    {showLoginPassword ? 'Hide' : 'Show'}
                  </button>
                </div>
              </label>
            </div>

            {error ? <p className="form-error">{error}</p> : null}

            <button className="button button--primary button--full" disabled={isBusy} type="submit">
              {isBusy ? 'Signing in...' : 'Sign in'}
            </button>

            <div className="auth-social">
              <div className="auth-social__divider">
                <span>or</span>
              </div>
              <button
                className="button button--secondary button--full auth-social__button"
                disabled={isBusy}
                onClick={handleGoogle}
                type="button"
              >
                <span className="auth-social__icon" aria-hidden="true">
                  G
                </span>
                <span>Continue with Google</span>
              </button>
              <button
                className="button button--secondary button--full auth-social__button"
                disabled={isBusy}
                onClick={handleApple}
                type="button"
              >
                <span className="auth-social__icon" aria-hidden="true">
                  
                </span>
                <span>Continue with Apple</span>
              </button>
            </div>
          </form>
        </section>
      </main>
    )
  }

  return (
    <main className="landing-page">
      <section className="landing-hero">
        <div className="landing-hero__copy">
          <div className="landing-brand-lockup">
            <div className="studio-brand">
              <div className="studio-brand__mark">
                <img src="/logo-mark.png" alt="" />
              </div>
              <div>
                <strong>Vennuzo Studio</strong>
                <span>{isAdminMode ? 'Operations Console' : 'Creator Workspace'}</span>
              </div>
            </div>
            <span className="eyebrow">{isAdminMode ? 'Platform operations' : 'Premium event platform'}</span>
          </div>
          <h1>{isAdminMode ? 'Run Vennuzo from one control room.' : 'The fastest way to sell out your event.'}</h1>
          {!isAdminMode && (
            <div className="landing-hero__features">
              <div className="landing-hero__feature">
                <span className="landing-hero__feature-icon" aria-hidden><TicketCheck size={16} /></span>
                <span>Instant ticket sales, zero setup friction</span>
              </div>
              <div className="landing-hero__feature">
                <span className="landing-hero__feature-icon" aria-hidden><BarChart3 size={16} /></span>
                <span>Real-time revenue and attendance analytics</span>
              </div>
              <div className="landing-hero__feature">
                <span className="landing-hero__feature-icon" aria-hidden><Banknote size={16} /></span>
                <span>Fast payouts via mobile money or bank transfer</span>
              </div>
              <div className="landing-hero__feature">
                <span className="landing-hero__feature-icon" aria-hidden><Megaphone size={16} /></span>
                <span>Built-in SMS campaigns to reach your audience</span>
              </div>
            </div>
          )}
          <div className="hero-chip-row">
            <span>{isAdminMode ? 'Full platform management' : 'Free to start'}</span>
            {!isAdminMode && <span><ShieldCheck size={14} aria-hidden /> Hubtel-ready payments</span>}
          </div>
        </div>
        {!isAdminMode ? (
          <div className="landing-hero__product" aria-hidden>
            <div className="landing-product-card landing-product-card--main">
              <span>Tonight's door</span>
              <strong>GHS 18,420</strong>
              <div className="landing-product-card__bar"><i style={{ width: '74%' }} /></div>
              <small>624 tickets issued · 74% sold through</small>
            </div>
            <div className="landing-product-grid">
              <div className="landing-product-card">
                <span>Campaign</span>
                <strong>1,280</strong>
                <small>SMS + push audience</small>
              </div>
              <div className="landing-product-card">
                <span>Next payout</span>
                <strong>Ready</strong>
                <small>Mobile money verified</small>
              </div>
            </div>
          </div>
        ) : null}
      </section>

      <section className="auth-panel">
        <div className="auth-panel__header">
          <p className="eyebrow">{isAdminMode ? 'Admin access' : 'Get Started'}</p>
          <h2>
            {isAdminMode
              ? 'Sign in to the admin console'
              : mode === 'signup'
                ? 'Create your organizer account'
                : 'Welcome back'}
          </h2>
        </div>

        {isAdminMode ? null : (
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

        {!isAdminMode && mode === 'signup' ? (
          <div className="auth-form auth-form--reference">
            <label className="field">
              <span>Organizer / Brand Name *</span>
              <input
                aria-label="Signup email address"
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
              <span>Contact Person *</span>
              <input
                onChange={(event) =>
                  setSignup((current) => ({
                    ...current,
                    contactPerson: event.target.value,
                  }))
                }
                placeholder="e.g., Jane Doe"
                value={signup.contactPerson}
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
              <small className="field-helper">Used for account security and payout notifications</small>
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
              <small className="field-helper">We&apos;ll send event updates and important notifications here</small>
            </label>
            <label className="field">
              <span>Password *</span>
              <div className="password-field">
                <input
                  aria-label="Signup password"
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
                  aria-label={showSignupPassword ? 'Hide signup password' : 'Show signup password'}
                  className="password-toggle"
                  onClick={() => setShowSignupPassword((current) => !current)}
                  type="button"
                >
                  {showSignupPassword ? 'Hide' : 'Show'}
                </button>
              </div>
              <div className="password-rules">
                <ul>
                  <li className={hasPasswordLength ? 'is-valid' : ''}>8+ characters</li>
                  <li className={hasPasswordCase ? 'is-valid' : ''}>Upper and lower case</li>
                  <li className={hasPasswordNumber ? 'is-valid' : ''}>1 number</li>
                </ul>
              </div>
            </label>
            <label className="field">
              <span>Confirm Password *</span>
              <div className="password-field">
                <input
                  aria-label="Confirm signup password"
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
                  aria-label={
                    showSignupConfirmPassword
                      ? 'Hide confirm signup password'
                      : 'Show confirm signup password'
                  }
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
                aria-label="Email address"
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
                  aria-label="Password"
                  onChange={(event) =>
                    setLogin((current) => ({ ...current, password: event.target.value }))
                  }
                  placeholder="Enter your password"
                  type={showLoginPassword ? 'text' : 'password'}
                  value={login.password}
                />
                <button
                  aria-label={showLoginPassword ? 'Hide password' : 'Show password'}
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
            : !isAdminMode && mode === 'signup'
              ? 'Create organizer account'
              : isAdminMode
                ? 'Sign in to Admin'
                : 'Sign in to Studio'}
        </button>

        <div className="auth-social">
          <div className="auth-social__divider">
            <span>or</span>
          </div>
          <button
            className="button button--secondary button--full auth-social__button"
            disabled={isBusy}
            onClick={handleGoogle}
            type="button"
          >
            <span className="auth-social__icon" aria-hidden="true">
              G
            </span>
            <span>{isAdminMode ? 'Continue with Google' : 'Start with Google'}</span>
          </button>
          <button
            className="button button--secondary button--full auth-social__button"
            disabled={isBusy}
            onClick={handleApple}
            type="button"
          >
            <span className="auth-social__icon" aria-hidden="true">
              <svg viewBox="0 0 24 24" role="img">
                <path
                  d="M15.4 12.6c0-2 1.7-3 1.8-3.1-1-1.5-2.5-1.7-3-1.7-1.3-.1-2.6.8-3.3.8s-1.8-.8-2.9-.8c-1.5 0-2.9.9-3.7 2.2-1.6 2.8-.4 6.9 1.1 9 .7 1 1.5 2.1 2.6 2.1s1.5-.7 2.9-.7 1.7.7 2.9.7 1.9-1 2.6-2c.8-1.2 1.1-2.3 1.1-2.3-.1 0-2.1-.8-2.1-4.2Zm-2.1-6.2c.6-.8 1.1-1.9 1-3-.9 0-2 .6-2.6 1.4-.6.7-1.1 1.8-.9 2.9 1 .1 2-.5 2.5-1.3Z"
                  fill="currentColor"
                />
              </svg>
            </span>
            <span>{isAdminMode ? 'Continue with Apple' : 'Start with Apple'}</span>
          </button>
        </div>

        <div className="auth-panel__footer">
          <p>
            By continuing, you agree to our{' '}
            <a
              className="inline-link-button"
              href="https://vennuzo.com/support.html"
              target="_blank"
              rel="noopener noreferrer"
            >
              Terms
            </a>{' '}
            and{' '}
            <a
              className="inline-link-button"
              href="https://vennuzo.com/privacy-policy.html"
              target="_blank"
              rel="noopener noreferrer"
            >
              Privacy Policy
            </a>
          </p>
        </div>
      </section>
    </main>
  )
}
