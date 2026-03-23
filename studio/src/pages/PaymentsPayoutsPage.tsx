import { useEffect, useState } from 'react'
import { Link, useSearchParams } from 'react-router-dom'
import { httpsCallable } from 'firebase/functions'

import { functions } from '../firebaseFunctions'
import { copy } from '../lib/copy'
import { formatMoney, formatDateTime } from '../lib/formatters'
import { getErrorMessage } from '../lib/errorMessages'
import { getPayoutReadiness } from '../lib/merchantWorkspace'
import { listWalletTransactions, loadOverviewMetrics } from '../lib/portalData'
import { usePortalSession } from '../lib/portalSession'
import type { WalletTransaction } from '../lib/types'

function transactionTypeLabel(type: WalletTransaction['type']): string {
  switch (type) {
    case 'top_up':
      return 'Top-up'
    case 'campaign_reservation':
      return 'Campaign reserve'
    case 'campaign_charge':
      return 'SMS charge'
    case 'campaign_release':
      return 'Campaign release'
    default:
      return type
  }
}

const getWalletBalance = httpsCallable<
  { organizationId?: string },
  { availableBalance: number; heldBalance: number; currency: string }
>(functions, 'getWalletBalance')

const initiateWalletTopUp = httpsCallable<
  {
    organizationId?: string
    amount: number
    payeeName: string
    payeeMobileNumber: string
    payeeEmail?: string
  },
  { success: boolean; checkoutUrl: string; checkoutId: string; clientReference: string }
>(functions, 'initiateWalletTopUp')

export function PaymentsPayoutsPage() {
  const [searchParams, setSearchParams] = useSearchParams()
  const session = usePortalSession()
  const { organizationId, application } = session
  const [metrics, setMetrics] = useState<{ grossRevenue: number } | null>(null)
  const [wallet, setWallet] = useState<{
    availableBalance: number
    heldBalance: number
    currency: string
  } | null>(null)
  const [transactions, setTransactions] = useState<WalletTransaction[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [topupStatus, setTopupStatus] = useState<string | null>(null)

  useEffect(() => {
    const topup = searchParams.get('topup')
    if (topup === 'success' || topup === 'cancelled') {
      setTopupStatus(topup)
      setSearchParams({}, { replace: true })
    }
  }, [searchParams, setSearchParams])

  useEffect(() => {
    let cancelled = false
    if (!organizationId) return
    async function run() {
      setLoading(true)
      setError(null)
      try {
        const [m, balanceResult, txList] = await Promise.all([
          loadOverviewMetrics(organizationId ?? ''),
          getWalletBalance({ organizationId: organizationId ?? undefined }).then((r) => r.data),
          listWalletTransactions(organizationId ?? '', 25),
        ])
        if (!cancelled) {
          setMetrics(m)
          setWallet({
            availableBalance: balanceResult.availableBalance,
            heldBalance: balanceResult.heldBalance,
            currency: balanceResult.currency,
          })
          setTransactions(txList)
        }
      } catch (e) {
        if (!cancelled) {
          setError(getErrorMessage(e, copy.paymentsLoadFailed))
        }
      } finally {
        if (!cancelled) setLoading(false)
      }
    }
    void run()
    return () => {
      cancelled = true
    }
  }, [organizationId])

  const payoutReadiness = getPayoutReadiness(application)
  const totalEarned = metrics?.grossRevenue ?? 0

  return (
    <PaymentsPayoutsContent
      organizationId={organizationId ?? ''}
      wallet={wallet}
      transactions={transactions}
      loading={loading}
      error={error}
      topupStatus={topupStatus}
      payoutReadiness={payoutReadiness}
      totalEarned={totalEarned}
    />
  )
}

function PaymentsPayoutsContent({
  organizationId,
  wallet,
  transactions,
  loading,
  error,
  topupStatus,
  payoutReadiness,
  totalEarned,
}: {
  organizationId: string
  wallet: { availableBalance: number; heldBalance: number; currency: string } | null
  transactions: WalletTransaction[]
  loading: boolean
  error: string | null
  topupStatus: string | null
  payoutReadiness: { ready: boolean; detail: string }
  totalEarned: number
}) {
  const [topUpAmount, setTopUpAmount] = useState('')
  const [topUpName, setTopUpName] = useState('')
  const [topUpPhone, setTopUpPhone] = useState('')
  const [topUpEmail, setTopUpEmail] = useState('')
  const [topUpSubmitting, setTopUpSubmitting] = useState(false)
  const [topUpError, setTopUpError] = useState<string | null>(null)

  async function handleLoadWallet() {
    const amount = Number(topUpAmount)
    if (!Number.isFinite(amount) || amount < 1) {
      setTopUpError('Enter an amount of at least 1 GHS.')
      return
    }
    const name = topUpName.trim()
    const phone = topUpPhone.trim()
    if (!name || !phone) {
      setTopUpError('Name and mobile number are required.')
      return
    }
    setTopUpError(null)
    setTopUpSubmitting(true)
    try {
      const result = await initiateWalletTopUp({
        organizationId: organizationId || undefined,
        amount,
        payeeName: name,
        payeeMobileNumber: phone,
        payeeEmail: topUpEmail.trim() || undefined,
      })
      const data = result.data
      if (data?.success && data.checkoutUrl) {
        window.location.href = data.checkoutUrl
        return
      }
      setTopUpError('We couldn’t start checkout. Please try again.')
    } catch (e) {
      setTopUpError(getErrorMessage(e, 'We couldn’t start the top-up. Please try again.'))
    } finally {
      setTopUpSubmitting(false)
    }
  }

  if (loading) {
    return <div className="page-loader">{copy.loading}</div>
  }
  if (error) {
    return (
      <div className="page-loader">
        <p>{copy.paymentsLoadFailed}</p>
        <p className="text-subtle">{error}</p>
        <p className="text-subtle" style={{ marginTop: '0.5rem', fontSize: '0.9rem' }}>{copy.pleaseTryAgain}</p>
      </div>
    )
  }

  return (
    <div className="dashboard-stack">
      {topupStatus === 'success' && (
        <div className="panel panel--success" style={{ marginBottom: '1rem' }}>
          <p className="text-subtle">Wallet top-up completed. Your balance will update shortly.</p>
        </div>
      )}
      {topupStatus === 'cancelled' && (
        <div className="panel" style={{ marginBottom: '1rem' }}>
          <p className="text-subtle">Top-up was cancelled. You can load your wallet anytime.</p>
        </div>
      )}

      <section className="page-hero page-hero--events">
        <div className="page-hero__content">
          <p className="eyebrow">Payments &amp; Payouts</p>
          <h2>Revenue and payouts</h2>
          <div className="hero-chip-row">
            <span>{formatMoney(totalEarned)} total earned</span>
            <span>{payoutReadiness.ready ? 'Payout ready' : 'Setup payout'}</span>
          </div>
        </div>
        <div className="page-hero__panel">
          <Link className="button button--secondary" to="/studio/overview">
            Back to overview
          </Link>
          <Link className="button button--secondary" to="/studio/setup/account">
            Edit payout details
          </Link>
        </div>
      </section>

      <section className="stats-grid stats-grid--compact">
        <article className="metric-card metric-card--plain">
          <span>Total earned</span>
          <strong>{formatMoney(totalEarned)}</strong>
        </article>
        <article className="metric-card metric-card--plain">
          <span>Campaign wallet</span>
          <strong>{formatMoney(wallet?.availableBalance ?? 0)}</strong>
        </article>
        <article className="metric-card metric-card--plain">
          <span>Payout status</span>
          <strong>{payoutReadiness.ready ? 'Ready' : 'Incomplete'}</strong>
        </article>
      </section>

      <section className="content-grid">
        <article className="panel">
          <div className="panel__header">
            <div>
              <p className="eyebrow">Campaign wallet</p>
              <h3>Fund promotions (SMS, etc.)</h3>
            </div>
          </div>
          <div style={{ padding: '1rem 0' }}>
            <p className="text-subtle" style={{ marginBottom: '0.75rem' }}>
              Balance: <strong>{formatMoney(wallet?.availableBalance ?? 0)}</strong>
              {(wallet?.heldBalance ?? 0) > 0 && (
                <span> (held: {formatMoney(wallet?.heldBalance ?? 0)})</span>
              )}
            </p>
            <div className="form-row" style={{ display: 'flex', flexWrap: 'wrap', gap: '0.75rem', alignItems: 'flex-end' }}>
              <label className="input-group">
                <span className="input-group__label">Amount (GHS)</span>
                <input
                  type="number"
                  min={1}
                  step={1}
                  className="input"
                  value={topUpAmount}
                  onChange={(e) => setTopUpAmount(e.target.value)}
                  placeholder="e.g. 50"
                />
              </label>
              <label className="input-group">
                <span className="input-group__label">Your name</span>
                <input
                  type="text"
                  className="input"
                  value={topUpName}
                  onChange={(e) => setTopUpName(e.target.value)}
                  placeholder="Payee name"
                />
              </label>
              <label className="input-group">
                <span className="input-group__label">Mobile number</span>
                <input
                  type="tel"
                  className="input"
                  value={topUpPhone}
                  onChange={(e) => setTopUpPhone(e.target.value)}
                  placeholder="0XX XXX XXXX"
                />
              </label>
              <label className="input-group">
                <span className="input-group__label">Email (optional)</span>
                <input
                  type="email"
                  className="input"
                  value={topUpEmail}
                  onChange={(e) => setTopUpEmail(e.target.value)}
                  placeholder="you@example.com"
                />
              </label>
              <button
                type="button"
                className="button button--primary"
                disabled={topUpSubmitting}
                onClick={handleLoadWallet}
              >
                {topUpSubmitting ? 'Redirecting…' : 'Load wallet'}
              </button>
            </div>
            {topUpError && <p className="text-subtle" style={{ color: 'var(--color-error)', marginTop: '0.5rem' }}>{topUpError}</p>}
          </div>
        </article>
        <article className="panel">
          <div className="panel__header">
            <div>
              <p className="eyebrow">Wallet activity</p>
              <h3>Recent transactions</h3>
            </div>
          </div>
          <div style={{ padding: '1rem 0' }}>
            {transactions.length === 0 ? (
              <p className="text-subtle">No wallet transactions yet. Top up to fund SMS campaigns.</p>
            ) : (
              <ul className="list-unstyled" style={{ margin: 0, padding: 0 }}>
                {transactions.map((tx) => (
                  <li
                    key={tx.id}
                    style={{
                      display: 'flex',
                      justifyContent: 'space-between',
                      alignItems: 'center',
                      padding: '0.5rem 0',
                      borderBottom: '1px solid var(--color-border, #eee)',
                      gap: '0.75rem',
                    }}
                  >
                    <span>
                      <strong>{transactionTypeLabel(tx.type)}</strong>
                      {tx.campaignId && <span className="text-subtle"> · Campaign</span>}
                      <br />
                      <span className="text-subtle">{formatDateTime(tx.createdAt)}</span>
                    </span>
                    <span>
                      {tx.type === 'top_up' || tx.type === 'campaign_release' ? '+' : ''}
                      {formatMoney(tx.amount)}
                    </span>
                  </li>
                ))}
              </ul>
            )}
          </div>
        </article>
        <article className="panel">
          <div className="panel__header">
            <div>
              <p className="eyebrow">Payout destination</p>
              <h3>Where you receive funds</h3>
            </div>
          </div>
          <div style={{ padding: '1rem 0' }}>
            <p>{payoutReadiness.detail}</p>
            {!payoutReadiness.ready && (
              <Link className="button button--primary" to="/studio/setup/payout">
                Set up payout
              </Link>
            )}
          </div>
        </article>
        <article className="panel">
          <div className="panel__header">
            <div>
              <p className="eyebrow">Payout history</p>
              <h3>Past payouts</h3>
            </div>
          </div>
          <div className="empty-card">
            <h4>No payouts yet</h4>
            <p>Completed payouts will appear here once processed according to your preferred schedule.</p>
          </div>
        </article>
      </section>
    </div>
  )
}
