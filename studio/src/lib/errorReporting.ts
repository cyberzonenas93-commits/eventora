/**
 * Error reporting / Sentry integration for Vennuzo Studio.
 *
 * Only initialises Sentry when VITE_SENTRY_DSN is set in the environment,
 * so local dev and CI runs without a DSN are unaffected.
 *
 * Setup:
 *   1. Add VITE_SENTRY_DSN to your .env.production (or Hosting env vars)
 *   2. Set VITE_APP_VERSION to your build version (e.g. git SHA or semver)
 *
 * Usage:
 *   import { captureError } from '../lib/errorReporting'
 *   captureError(error, { context: 'PaymentsPage', userId })
 */

import * as Sentry from '@sentry/react'

let initialised = false

export function initErrorReporting(): void {
  const dsn = import.meta.env.VITE_SENTRY_DSN as string | undefined
  if (!dsn) return

  Sentry.init({
    dsn,
    release: import.meta.env.VITE_APP_VERSION as string | undefined,
    environment: import.meta.env.MODE, // 'production' | 'development'
    // Only send 20% of performance traces to stay within free tier
    tracesSampleRate: 0.2,
    // Capture replays only on error sessions
    replaysOnErrorSampleRate: 1.0,
    replaysSessionSampleRate: 0,
    integrations: [
      Sentry.browserTracingIntegration(),
    ],
    // Don't report known non-actionable errors
    ignoreErrors: [
      'ResizeObserver loop limit exceeded',
      'ResizeObserver loop completed with undelivered notifications',
      'Non-Error promise rejection captured',
    ],
    beforeSend(event) {
      // Strip any PII from breadcrumb urls in production
      if (event.request?.url) {
        try {
          const url = new URL(event.request.url)
          url.search = '' // strip query params (may contain tokens)
          event.request.url = url.toString()
        } catch {
          // ignore parse errors
        }
      }
      return event
    },
  })

  initialised = true
}

/**
 * Capture an unexpected error and report it to Sentry (if configured).
 * Safe to call even if Sentry is not initialised.
 */
export function captureError(
  error: unknown,
  context?: Record<string, string | number | boolean>,
): void {
  if (!initialised) {
    console.error('[errorReporting]', error, context)
    return
  }
  Sentry.withScope((scope) => {
    if (context) {
      scope.setExtras(context)
    }
    Sentry.captureException(error)
  })
}

/**
 * Identify the current user to Sentry for better error attribution.
 * Call after successful sign-in.
 */
export function identifyUser(uid: string, email?: string): void {
  if (!initialised) return
  Sentry.setUser({ id: uid, email })
}

/**
 * Clear the current user identity (call on sign-out).
 */
export function clearUser(): void {
  if (!initialised) return
  Sentry.setUser(null)
}

/**
 * Wrap a React component tree with Sentry's error boundary.
 * Re-exports Sentry.ErrorBoundary so callers don't import Sentry directly.
 */
export const SentryErrorBoundary = Sentry.ErrorBoundary
