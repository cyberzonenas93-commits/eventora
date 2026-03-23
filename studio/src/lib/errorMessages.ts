/**
 * Normalize unknown errors into a single user-facing message.
 * Handles Error instances, Firebase-style { message }, and strings.
 */
export function getErrorMessage(error: unknown, fallback: string): string {
  if (error == null) return fallback
  if (typeof error === 'string') return error.trim() || fallback
  if (error instanceof Error) return error.message.trim() || fallback
  const obj = error as { message?: string; code?: string }
  if (typeof obj?.message === 'string') return obj.message.trim() || fallback
  return fallback
}

/**
 * Check for common error codes (e.g. Firebase) and return a friendlier message when possible.
 */
export function getFriendlyErrorMessage(
  error: unknown,
  fallback: string,
  options?: { networkMessage?: string; authMessage?: string },
): string {
  const raw = getErrorMessage(error, fallback)
  const obj = error as { code?: string } | undefined
  const code = typeof obj?.code === 'string' ? obj.code.toLowerCase() : ''

  if (options?.networkMessage && /unavailable|network|failed to fetch|timeout/i.test(raw)) {
    return options.networkMessage
  }
  if (options?.authMessage && /auth|permission|unauthenticated/i.test(code + raw)) {
    return options.authMessage
  }

  return raw
}
