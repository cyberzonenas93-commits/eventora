import { useCallback, useEffect, useState } from 'react'
import { Link, useSearchParams } from 'react-router-dom'
import { httpsCallable } from 'firebase/functions'

import { functions } from '../firebaseFunctions'
import { trackEvent } from '../lib/analytics'
import { copy } from '../lib/copy'
import { formatMoney, formatDateTime } from '../lib/formatters'
import { getErrorMessage } from '../lib/errorMessages'
import { getPayoutReadiness } from '../lib/merchantWorkspace'
import { listWalletTransactions, loadOverviewMetrics } from '../lib/portalData'
import { usePortalSession } from '../lib/portalSession'
import type { WalletTransaction } from '../lib/types'

type PayoutRequestSnapshot = {
  id: string
  amountGhs: number
  status: string
  recipientName?: string
  recipientMsisdn?: string
  channel?: string
  clientReference?: string
  errorDescription?: string
  createdAt?: string
  completedAt?: string
}

type PayoutSummary = {
  grossTicketSalesGhs: number
  reservedPayoutsGhs: number
  availableGhs: number
  currency: string
  recentRequests: PayoutRequestSnapshot[]
}

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
    case 'creative_service_charge':
      return 'Creative service'
    case 'creative_service_refund':
      return 'Creative refund'
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

const getOrganizerPayoutSummary = httpsCallable<
  { organizationId: string },
  PayoutSummary
>(functions, 'getOrganizerPayoutSummary')

const submitOrganizerPayoutRequest = httpsCallable<
  {
    organizationId: string
    amountGhs: number
    recipientName: string
    recipientMsisdn: string
    channel: string
    notes?: string
  },
  { success: boolean; requestId: string; clientReference: string; status: string }
>(functions, 'submitOrganizerPayoutRequest')

const checkOrganizerPayoutStatus = httpsCallable<
  { clientReference: string },
  { status: string; requestId: string; alreadyFinalized?: boolean; fromStatusCheck?: boolean }
>(functions, 'checkOrganizerPayoutStatus')

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
  const [payoutSummary, setPayoutSummary] = useState<PayoutSummary | null>(null)
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

  const loadPayments = useCallback(async () => {
    if (!organizationId) return
      setLoading(true)
      setError(null)
      try {
        const [m, balanceResult, txList, payoutResult] = await Promise.all([
          loadOverviewMetrics(organizationId ?? ''),
          getWalletBalance({ organizationId: organizationId ?? undefined }).then((r) => r.data),
          listWalletTransactions(organizationId ?? '', 25),
          getOrganizerPayoutSummary({ organizationId: organizationId ?? '' }).then((r) => r.data),
        ])
        setMetrics(m)
        setWallet({
          availableBalance: balanceResult.availableBalance,
          heldBalance: balanceResult.heldBalance,
          currency: balanceResult.currency,
        })
        setTransactions(txList)
        setPayoutSummary(payoutResult)
      } catch (e) {
        setError(getErrorMessage(e, copy.paymentsLoadFailed))
      } finally {
        setLoading(false)
      }
  }, [organizationId])

  useEffect(() => {
    let cancelled = false
    if (!organizationId) return
    async function run() {
      await loadPayments()
    }
    if (!cancelled) void run()
    return () => {
      cancelled = true
    }
  }, [organizationId, loadPayments])

  const payoutReadiness = getPayoutReadiness(application)
  const totalEarned = metrics?.grossRevenue ?? 0

  return (
    <PaymentsPayoutsContent
      organizationId={organizationId ?? ''}
      wallet={wallet}
      transactions={transactions}
      payoutSummary={payoutSummary}
      loading={loading}
      error={error}
      topupStatus={topupStatus}
      payoutReadiness={payoutReadiness}
      totalEarned={totalEarned}
      defaultPayoutName={application?.accountName ?? ''}
      defaultPayoutPhone={application?.payoutPhone ?? ''}
      defaultPayoutChannel={application?.network ?? ''}
      onPayoutChanged={() => void loadPayments()}
    />
  )
}

function PaymentsPayoutsContent({
  organizationId,
  wallet,
  transactions,
  payoutSummary,
  loading,
  error,
  topupStatus,
  payoutReadiness,
  totalEarned,
  defaultPayoutName,
  defaultPayoutPhone,
  defaultPayoutChannel,
  onPayoutChanged,
}: {
  organizationId: string
  wallet: { availableBalance: number; heldBalance: number; currency: string } | null
  transactions: WalletTransaction[]
  payoutSummary: PayoutSummary | null
  loading: boolean
  error: string | null
  topupStatus: string | null
  payoutReadiness: { ready: boolean; detail: string }
  totalEarned: number
  defaultPayoutName: string
  defaultPayoutPhone: string
  defaultPayoutChannel: string
  onPayoutChanged: () => void
}) {
  const [topUpAmount, setTopUpAmount] = useState('')
  const [topUpName, setTopUpName] = useState('')
  const [topUpPhone, setTopUpPhone] = useState('')
  const [topUpEmail, setTopUpEmail] = useState('')
  const [topUpSubmitting, setTopUpSubmitting] = useState(false)
  const [topUpError, setTopUpError] = useState<string | null>(null)
  const [withdrawAmount, setWithdrawAmount] = useState('')
  const [withdrawName, setWithdrawName] = useState(defaultPayoutName)
  const [withdrawPhone, setWithdrawPhone] = useState(defaultPayoutPhone)
  const [withdrawChannel, setWithdrawChannel] = useState(defaultPayoutChannel || 'MTN Mobile Money')
  const [withdrawSubmitting, setWithdrawSubmitting] = useState(false)
  const [withdrawError, setWithdrawError] = useState<string | null>(null)
  const [withdrawNotice, setWithdrawNotice] = useState<string | null>(null)

  useEffect(() => {
    setWithdrawName((current) => current || defaultPayoutName)
    setWithdrawPhone((current) => current || defaultPayoutPhone)
    setWithdrawChannel((current) => current || defaultPayoutChannel || 'MTN Mobile Money')
  }, [defaultPayoutName, defaultPayoutPhone, defaultPayoutChannel])

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
	        void trackEvent('wallet_topup_started', {
	          value: amount,
	        }, {
	          area: 'studio',
	          organizationId,
	        })
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

  async function handleWithdraw() {
    const amount = Number(withdrawAmount)
    if (!Number.isFinite(amount) || amount <= 0) {
      setWithdrawError('Enter a withdrawal amount.')
      return
    }
    if (amount > (payoutSummary?.availableGhs ?? 0)) {
      setWithdrawError('Amount is above your available ticket-sales balance.')
      return
    }
    if (!withdrawName.trim() || !withdrawPhone.trim()) {
      setWithdrawError('Payout name and mobile money phone are required.')
      return
    }
    setWithdrawSubmitting(true)
    setWithdrawError(null)
    setWithdrawNotice(null)
    try {
      const result = await submitOrganizerPayoutRequest({
        organizationId,
        amountGhs: amount,
        recipientName: withdrawName.trim(),
        recipientMsisdn: withdrawPhone.trim(),
        channel: withdrawChannel,
      })
      setWithdrawAmount('')
      setWithdrawNotice(
        result.data.status === 'success'
          ? 'Withdrawal completed.'
          : 'Withdrawal started. Hubtel will send the funds shortly.',
      )
      void trackEvent('payout_withdrawal_started', {
        value: amount,
      }, {
        area: 'studio',
        organizationId,
      })
      onPayoutChanged()
    } catch (e) {
      setWithdrawError(getErrorMessage(e, 'We couldn’t start the withdrawal. Please try again.'))
    } finally {
      setWithdrawSubmitting(false)
    }
  }

  async function handleCheckPayout(clientReference?: string) {
    if (!clientReference) return
    setWithdrawError(null)
    try {
      const result = await checkOrganizerPayoutStatus({ clientReference })
      setWithdrawNotice(`Payout status: ${result.data.status}.`)
      onPayoutChanged()
    } catch (e) {
      setWithdrawError(getErrorMessage(e, 'We couldn’t check that payout yet.'))
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
        <div className="panel panel--success">
          <div style={{ padding: '0.9rem 1.5rem' }}>
            <p className="text-subtle" style={{ margin: 0 }}>✓ Wallet top-up completed. Your balance will update shortly.</p>
          </div>
        </div>
      )}
      {topupStatus === 'cancelled' && (
        <div className="panel">
          <div style={{ padding: '0.9rem 1.5rem' }}>
            <p className="text-subtle" style={{ margin: 0 }}>Top-up was cancelled. You can load your wallet anytime.</p>
          </div>
        </div>
      )}

      {/* Prominent balance hero */}
      <div className="balance-hero-card">
        <div className="balance-hero-card__header">
          <div>
            <p className="eyebrow">Payments &amp; Payouts</p>
            <p className="balance-hero-card__label">Total revenue earned</p>
          </div>
          <div style={{ display: 'flex', gap: '0.6rem' }}>
            <Link className="button button--secondary" to="/studio/setup/payout" style={{ fontSize: '0.8rem', padding: '0.5rem 0.9rem' }}>
              Edit payout
            </Link>
          </div>
        </div>
        <div>
          <div className="balance-hero-card__amount">{formatMoney(totalEarned)}</div>
          <p className="balance-hero-card__meta">Lifetime gross revenue from all events</p>
        </div>
        <div className="balance-hero-card__stats">
          <div className="balance-hero-stat">
            <span>Services wallet</span>
            <strong>{formatMoney(wallet?.availableBalance ?? 0)}</strong>
          </div>
          {(wallet?.heldBalance ?? 0) > 0 && (
            <div className="balance-hero-stat">
              <span>Held balance</span>
              <strong>{formatMoney(wallet?.heldBalance ?? 0)}</strong>
            </div>
          )}
          <div className="balance-hero-stat">
            <span>Payout status</span>
            <strong style={{ color: payoutReadiness.ready ? '#34d399' : '#fbbf24' }}>
              {payoutReadiness.ready ? 'Ready ✓' : 'Incomplete'}
            </strong>
          </div>
          <div className="balance-hero-stat">
            <span>Available to withdraw</span>
            <strong>{formatMoney(payoutSummary?.availableGhs ?? 0)}</strong>
          </div>
        </div>
      </div>

      <div className="content-grid">
        {/* Ticket payout withdrawal */}
        <article className="panel">
          <div className="panel__header">
            <div>
              <p className="eyebrow">Ticket sales withdrawal</p>
              <h3>Send funds to mobile money</h3>
            </div>
          </div>
          <div className="topup-form">
            <div className="balance-hero-card__stats" style={{ padding: 0 }}>
              <div className="balance-hero-stat">
                <span>Hubtel ticket sales</span>
                <strong>{formatMoney(payoutSummary?.grossTicketSalesGhs ?? totalEarned)}</strong>
              </div>
              <div className="balance-hero-stat">
                <span>Pending / paid out</span>
                <strong>{formatMoney(payoutSummary?.reservedPayoutsGhs ?? 0)}</strong>
              </div>
              <div className="balance-hero-stat">
                <span>Available</span>
                <strong>{formatMoney(payoutSummary?.availableGhs ?? 0)}</strong>
              </div>
            </div>
            <div className="topup-form-row">
              <label className="input-group">
                <span className="input-group__label">Amount (GHS)</span>
                <input type="number" min={1} step="0.01" className="input" value={withdrawAmount} onChange={(e) => setWithdrawAmount(e.target.value)} placeholder="e.g. 250" />
              </label>
              <label className="input-group">
                <span className="input-group__label">Mobile money network</span>
                <select className="input" value={withdrawChannel} onChange={(e) => setWithdrawChannel(e.target.value)}>
                  <option value="MTN Mobile Money">MTN Mobile Money</option>
                  <option value="Telecel Cash">Telecel Cash</option>
                  <option value="AirtelTigo Money">AirtelTigo Money</option>
                </select>
              </label>
              <label className="input-group">
                <span className="input-group__label">Payout name</span>
                <input type="text" className="input" value={withdrawName} onChange={(e) => setWithdrawName(e.target.value)} placeholder="Name on wallet" />
              </label>
              <label className="input-group">
                <span className="input-group__label">Mobile money phone</span>
                <input type="tel" className="input" value={withdrawPhone} onChange={(e) => setWithdrawPhone(e.target.value)} placeholder="0XX XXX XXXX" />
              </label>
            </div>
            {withdrawError && <p className="form-error">{withdrawError}</p>}
            {withdrawNotice && <p className="text-subtle" style={{ margin: 0 }}>{withdrawNotice}</p>}
            <button
              type="button"
              className="button button--primary"
              disabled={withdrawSubmitting || !payoutReadiness.ready || (payoutSummary?.availableGhs ?? 0) <= 0}
              onClick={handleWithdraw}
              style={{ justifySelf: 'start' }}
            >
              {withdrawSubmitting ? 'Sending…' : 'Withdraw with Hubtel Send Money'}
            </button>
            {!payoutReadiness.ready && (
              <p className="text-subtle" style={{ margin: 0 }}>Complete payout setup before withdrawing.</p>
            )}
          </div>
        </article>

        {/* Load wallet */}
        <article className="panel">
          <div className="panel__header">
            <div>
              <p className="eyebrow">Services wallet</p>
              <h3>Fund promotions and creative services</h3>
            </div>
          </div>
          <div className="topup-form">
            <div className="topup-form-row">
              <label className="input-group">
                <span className="input-group__label">Amount (GHS)</span>
                <input type="number" min={1} step={1} className="input" value={topUpAmount} onChange={(e) => setTopUpAmount(e.target.value)} placeholder="e.g. 50" />
              </label>
              <label className="input-group">
                <span className="input-group__label">Your name</span>
                <input type="text" className="input" value={topUpName} onChange={(e) => setTopUpName(e.target.value)} placeholder="Payee name" />
              </label>
              <label className="input-group">
                <span className="input-group__label">Mobile number</span>
                <input type="tel" className="input" value={topUpPhone} onChange={(e) => setTopUpPhone(e.target.value)} placeholder="0XX XXX XXXX" />
              </label>
              <label className="input-group">
                <span className="input-group__label">Email (optional)</span>
                <input type="email" className="input" value={topUpEmail} onChange={(e) => setTopUpEmail(e.target.value)} placeholder="you@example.com" />
              </label>
            </div>
            {topUpError && <p className="form-error">{topUpError}</p>}
            <button type="button" className="button button--primary" disabled={topUpSubmitting} onClick={handleLoadWallet} style={{ justifySelf: 'start' }}>
              {topUpSubmitting ? 'Redirecting…' : 'Load wallet →'}
            </button>
          </div>
        </article>

        {/* Transaction history */}
        <article className="panel">
          <div className="panel__header">
            <div>
              <p className="eyebrow">Wallet activity</p>
              <h3>Recent transactions</h3>
            </div>
          </div>
          {transactions.length === 0 ? (
            <div className="empty-card">
              <h4>No transactions yet</h4>
              <p>Top up to fund push, SMS, flyers, and table-package flyers.</p>
            </div>
          ) : (
            <div className="tx-list">
              {transactions.map((tx) => (
                <div className="tx-row" key={tx.id}>
                  <div className="tx-row__info">
                    <strong>{transactionTypeLabel(tx.type)}{tx.campaignId ? ' · Campaign' : ''}</strong>
                    <small>{formatDateTime(tx.createdAt)}</small>
                  </div>
                  <span className={`tx-row__amount${tx.type === 'top_up' || tx.type === 'campaign_release' || tx.type === 'creative_service_refund' ? ' tx-row__amount--credit' : ''}`}>
                    {tx.type === 'top_up' || tx.type === 'campaign_release' || tx.type === 'creative_service_refund' ? '+' : '−'}{formatMoney(tx.amount)}
                  </span>
                </div>
              ))}
            </div>
          )}
        </article>

        {/* Payout destination */}
        <article className="panel">
          <div className="panel__header">
            <div>
              <p className="eyebrow">Payout destination</p>
              <h3>Where you receive funds</h3>
            </div>
          </div>
          <div style={{ padding: '1.25rem 1.5rem', display: 'grid', gap: '0.85rem' }}>
            <p style={{ margin: 0, fontSize: '0.88rem', color: 'var(--muted-strong)' }}>{payoutReadiness.detail}</p>
            {!payoutReadiness.ready && (
              <Link className="button button--primary" to="/studio/setup/payout" style={{ justifySelf: 'start' }}>
                Set up payout
              </Link>
            )}
          </div>
        </article>

        {/* Payout history */}
        <article className="panel">
          <div className="panel__header">
            <div>
              <p className="eyebrow">Payout history</p>
              <h3>Past payouts</h3>
            </div>
          </div>
          {(payoutSummary?.recentRequests ?? []).length === 0 ? (
            <div className="empty-card">
              <h4>No payouts yet</h4>
              <p>Completed payouts will appear here once processed.</p>
            </div>
          ) : (
            <div className="tx-list">
              {(payoutSummary?.recentRequests ?? []).map((item) => (
                <div className="tx-row" key={item.id}>
                  <div className="tx-row__info">
                    <strong>{item.status.replace(/_/g, ' ')} · {item.recipientName || item.recipientMsisdn}</strong>
                    <small>{formatDateTime(item.createdAt ?? '')}{item.errorDescription ? ` · ${item.errorDescription}` : ''}</small>
                  </div>
                  <div style={{ display: 'flex', gap: '0.5rem', alignItems: 'center', flexWrap: 'wrap', justifyContent: 'flex-end' }}>
                    {item.status === 'processing' && item.clientReference && (
                      <button type="button" className="button button--secondary" onClick={() => void handleCheckPayout(item.clientReference)} style={{ fontSize: '0.78rem', padding: '0.45rem 0.7rem' }}>
                        Check
                      </button>
                    )}
                    <span className="tx-row__amount">−{formatMoney(item.amountGhs)}</span>
                  </div>
                </div>
              ))}
            </div>
          )}
        </article>
      </div>
    </div>
  )
}
