import { useState } from 'react'
import { Link } from 'react-router-dom'

import { copy } from '../lib/copy'

export function UnsubscribePage() {
  const [phone, setPhone] = useState('')
  const [status, setStatus] = useState<'idle' | 'loading' | 'success' | 'error'>('idle')
  const [message, setMessage] = useState('')

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    if (!phone.trim()) return
    setStatus('loading')
    setMessage('')
    try {
      const res = await fetch('/api/sms-opt-out', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ phone: phone.trim() }),
      })
      const data = await res.json().catch(() => ({}))
      if (res.ok && data.success) {
        setStatus('success')
        setMessage(data.message || 'You have been unsubscribed from Vennuzo SMS.')
      } else {
        setStatus('error')
        setMessage(data.error || copy.unsubscribeError)
      }
    } catch {
      setStatus('error')
      setMessage(copy.unsubscribeNetworkError)
    }
  }

  return (
    <div className="dashboard-stack" style={{ maxWidth: '28rem', margin: '2rem auto', padding: '0 1rem' }}>
      <section className="page-hero page-hero--events">
        <div className="page-hero__content">
          <p className="eyebrow">SMS opt-out</p>
          <h2>Unsubscribe from Vennuzo SMS</h2>
          <p className="text-subtle">
            Enter your Ghana mobile number to stop receiving promotional SMS from Vennuzo event organizers.
          </p>
        </div>
      </section>

      <article className="panel">
        <div className="panel__header">
          <h3>Your number</h3>
        </div>
        <form onSubmit={handleSubmit} style={{ padding: '1rem 0' }}>
          <label className="input-group" style={{ display: 'block', marginBottom: '1rem' }}>
            <span className="input-group__label">Mobile number</span>
            <input
              type="tel"
              className="input"
              value={phone}
              onChange={(e) => setPhone(e.target.value)}
              placeholder="0XX XXX XXXX or +233..."
              disabled={status === 'loading'}
            />
          </label>
          {message && (
            <p
              className={status === 'success' ? 'form-success' : 'form-error'}
              style={{ marginBottom: '1rem' }}
            >
              {message}
            </p>
          )}
          <button
            type="submit"
            className="button button--primary"
            disabled={status === 'loading' || !phone.trim()}
          >
            {status === 'loading' ? 'Submitting…' : 'Unsubscribe'}
          </button>
        </form>
      </article>

      <p className="text-subtle" style={{ marginTop: '1rem' }}>
        <Link to="/">Back to Vennuzo</Link>
      </p>
    </div>
  )
}
