import { useMemo, useRef, useState } from 'react'
import { Navigate } from 'react-router-dom'

import { copy } from '../lib/copy'
import { getErrorMessage } from '../lib/errorMessages'
import { usePortalSession } from '../lib/portalSession'

type AuthMode = 'signup' | 'login'

export function LandingPage() {
  const session = usePortalSession()
  const isAdminHost =
    typeof window !== 'undefined' &&
    (window.location.hostname.includes('vennuzo-admin') ||
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
    if (isAdminHost && session.isAdmin) {
      return <Navigate replace to="/superadmin" />
    }
    if (session.isSuperAdmin) {
      return <Navigate replace to="/superadmin" />
    }
    return <Navigate replace to="/studio/overview" />
  }

  async function handleSubmit() {
    setError('')

    if (!isAdminHost && mode === 'signup' && !signupValid) {
      setError(copy.completeRequiredFields)
      return
    }

    if (!isAdminHost && mode === 'login' && !loginValid) {
      setError(copy.validEmailAndPassword)
      return
    }

    setIsBusy(true)
    try {
      if (!isAdminHost && mode === 'signup') {
        await session.signUp({
          displayName: signup.displayName,
          contactPerson: signup.contactPerson,
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
      setError(getErrorMessage(caughtError, copy.authFailed))
    } finally {
      setIsBusy(false)
    }
  }

  async function handleGoogle() {
    setError('')
    setIsBusy(true)
    try {
      await session.signInWithGoogle({ seedOrganizerProfile: !isAdminHost })
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
      await session.signInWithApple({ seedOrganizerProfile: !isAdminHost })
    } catch (caughtError) {
      setError(getErrorMessage(caughtError, copy.appleSignInFailed))
    } finally {
      setIsBusy(false)
    }
  }

  return (
    <main className="landing-page">
      <section className="landing-hero">
        <div className="landing-hero__copy">
          <div className="landing-brand-lockup">
            <div className="studio-brand">
              <div className="studio-brand__mark">V</div>
              <div>
                <strong>Vennuzo Studio</strong>
                <span>{isAdminHost ? 'Operations Console' : 'Creator Workspace'}</span>
              </div>
            </div>
            <span className="eyebrow">{isAdminHost ? 'Platform operations' : 'Premium event platform'}</span>
          </div>
          <h1>{isAdminHost ? 'Run approvals from one control room.' : 'The fastest way to sell out your event.'}</h1>
          {!isAdminHost && (
            <div className="landing-hero__features">
              <div className="landing-hero__feature">
                <span className="landing-hero__feature-icon">🎟️</span>
                <span>Instant ticket sales, zero setup friction</span>
              </div>
              <div className="landing-hero__feature">
                <span className="landing-hero__feature-icon">📊</span>
                <span>Real-time revenue and attendance analytics</span>
              </div>
              <div className="landing-hero__feature">
                <span className="landing-hero__feature-icon">💸</span>
                <span>Fast payouts via mobile money or bank transfer</span>
              </div>
              <div className="landing-hero__feature">
                <span className="landing-hero__feature-icon">📣</span>
                <span>Built-in SMS campaigns to reach your audience</span>
              </div>
            </div>
          )}
          <div className="hero-chip-row">
            <span>{isAdminHost ? 'Organizer approvals' : 'Free to start'}</span>
            {!isAdminHost && <span>Ghana's #1 events platform</span>}
          </div>
        </div>
      </section>

      <section className="auth-panel">
        <div className="auth-panel__header">
          <p className="eyebrow">{isAdminHost ? 'Superadmin access' : 'Get Started'}</p>
          <h2>
            {isAdminHost
              ? 'Sign in to the approvals dashboard'
              : mode === 'signup'
                ? 'Create your organizer account'
                : 'Welcome back'}
          </h2>
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
            <span>{isAdminHost ? 'Continue with Google' : 'Start with Google'}</span>
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
            <span>{isAdminHost ? 'Continue with Apple' : 'Start with Apple'}</span>
          </button>
        </div>

        <div className="auth-panel__footer">
          <p>
            By continuing, you agree to our{' '}
            <button className="inline-link-button" type="button">
              Terms
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
