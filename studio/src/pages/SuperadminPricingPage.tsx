import { useEffect, useState } from 'react'
import { httpsCallable } from 'firebase/functions'

import { functions } from '../firebaseFunctions'
import { copy } from '../lib/copy'
import { getErrorMessage } from '../lib/errorMessages'

const getAdminPricingConfig = httpsCallable<
  void,
  { defaultSmsRateGhs: number; smsMarginMultiplier: number }
>(functions, 'getAdminPricingConfig')

const setAdminPricingConfig = httpsCallable<
  { defaultSmsRateGhs: number; smsMarginMultiplier: number },
  { success: boolean }
>(functions, 'setAdminPricingConfig')

const listAdminPromoPackages = httpsCallable<
  void,
  {
    packages: {
      id: string
      name: string
      description: string
      active: boolean
      order: number
      defaultSmsRateGhs: number
      smsMarginMultiplier: number
      minSpend?: number
    }[]
  }
>(functions, 'listAdminPromoPackages')

const setAdminPromoPackage = httpsCallable<
  {
    id?: string
    name: string
    description?: string
    active: boolean
    order: number
    defaultSmsRateGhs: number
    smsMarginMultiplier: number
    minSpend?: number
  },
  { success: boolean; id: string }
>(functions, 'setAdminPromoPackage')

export function SuperadminPricingPage() {
  const [packages, setPackages] = useState<Array<{
    id: string
    name: string
    description: string
    active: boolean
    order: number
    defaultSmsRateGhs: number
    smsMarginMultiplier: number
    minSpend?: number
  }>>([])
  const [loading, setLoading] = useState(true)
  const [savingPricing, setSavingPricing] = useState(false)
  const [savingPackage, setSavingPackage] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [notice, setNotice] = useState<string | null>(null)
  const [pricingForm, setPricingForm] = useState({ defaultSmsRateGhs: '0.05', smsMarginMultiplier: '1.5' })
  const [editingId, setEditingId] = useState<string | null>(null)
  const [packageForm, setPackageForm] = useState({
    name: '',
    description: '',
    active: true,
    order: 0,
    defaultSmsRateGhs: '0.05',
    smsMarginMultiplier: '1.5',
    minSpend: '',
  })

  useEffect(() => {
    let cancelled = false
    setLoading(true)
    Promise.all([
      getAdminPricingConfig().then((r) => r.data),
      listAdminPromoPackages().then((r) => r.data.packages),
    ])
      .then(([config, list]) => {
        if (!cancelled) {
          setPricingForm({
            defaultSmsRateGhs: String(config.defaultSmsRateGhs),
            smsMarginMultiplier: String(config.smsMarginMultiplier),
          })
          setPackages(list)
        }
      })
      .catch((e) => {
        if (!cancelled) setError(getErrorMessage(e, copy.pricingLoadFailed))
      })
      .finally(() => {
        if (!cancelled) setLoading(false)
      })
    return () => { cancelled = true }
  }, [])

  async function handleSavePricing(e: React.FormEvent) {
    e.preventDefault()
    setError(null)
    setNotice(null)
    const defaultSmsRateGhs = Number(pricingForm.defaultSmsRateGhs)
    const smsMarginMultiplier = Number(pricingForm.smsMarginMultiplier)
    if (!Number.isFinite(defaultSmsRateGhs) || defaultSmsRateGhs < 0) {
      setError(copy.defaultSmsRateInvalid)
      return
    }
    if (!Number.isFinite(smsMarginMultiplier) || smsMarginMultiplier < 1) {
      setError(copy.smsMarginInvalid)
      return
    }
    setSavingPricing(true)
    try {
      await setAdminPricingConfig({ defaultSmsRateGhs, smsMarginMultiplier })
      setNotice(copy.saved)
    } catch (e) {
      setError(getErrorMessage(e, copy.pricingSaveFailed))
    } finally {
      setSavingPricing(false)
    }
  }

  function openEdit(pkg: typeof packages[0]) {
    setEditingId(pkg.id)
    setPackageForm({
      name: pkg.name,
      description: pkg.description || '',
      active: pkg.active,
      order: pkg.order,
      defaultSmsRateGhs: String(pkg.defaultSmsRateGhs),
      smsMarginMultiplier: String(pkg.smsMarginMultiplier),
      minSpend: pkg.minSpend != null ? String(pkg.minSpend) : '',
    })
  }

  function openNew() {
    setEditingId('')
    setPackageForm({
      name: '',
      description: '',
      active: true,
      order: packages.length,
      defaultSmsRateGhs: '0.05',
      smsMarginMultiplier: '1.5',
      minSpend: '',
    })
  }

  async function handleSavePackage(e: React.FormEvent) {
    e.preventDefault()
    setError(null)
    setNotice(null)
    if (!packageForm.name.trim()) {
      setError(copy.packageNameRequired)
      return
    }
    setSavingPackage(true)
    try {
      const result = await setAdminPromoPackage({
        id: editingId || undefined,
        name: packageForm.name.trim(),
        description: packageForm.description.trim() || undefined,
        active: packageForm.active,
        order: packageForm.order,
        defaultSmsRateGhs: Number(packageForm.defaultSmsRateGhs) || 0.05,
        smsMarginMultiplier: Number(packageForm.smsMarginMultiplier) || 1.5,
        minSpend: packageForm.minSpend ? Number(packageForm.minSpend) : undefined,
      })
      setNotice(copy.saved)
      if (!editingId) {
        setPackages((prev) => [
          ...prev,
          {
            id: result.data.id,
            name: packageForm.name.trim(),
            description: packageForm.description.trim(),
            active: packageForm.active,
            order: packageForm.order,
            defaultSmsRateGhs: Number(packageForm.defaultSmsRateGhs) || 0.05,
            smsMarginMultiplier: Number(packageForm.smsMarginMultiplier) || 1.5,
            minSpend: packageForm.minSpend ? Number(packageForm.minSpend) : undefined,
          },
        ])
      } else {
        setPackages((prev) =>
          prev.map((p) =>
            p.id === editingId
              ? {
                  ...p,
                  name: packageForm.name.trim(),
                  description: packageForm.description.trim(),
                  active: packageForm.active,
                  order: packageForm.order,
                  defaultSmsRateGhs: Number(packageForm.defaultSmsRateGhs) || 0.05,
                  smsMarginMultiplier: Number(packageForm.smsMarginMultiplier) || 1.5,
                  minSpend: packageForm.minSpend ? Number(packageForm.minSpend) : undefined,
                }
              : p
          )
        )
      }
      setEditingId(null)
    } catch (e) {
      setError(getErrorMessage(e, copy.packageSaveFailed))
    } finally {
      setSavingPackage(false)
    }
  }

  if (loading) {
    return <div className="page-loader">{copy.loading}</div>
  }

  return (
    <>
      <section className="status-card superadmin-card">
        <div className="status-card__header">
          <p className="eyebrow">Superadmin</p>
          <h1>Pricing & packages</h1>
        </div>
        <p>Default SMS pricing applies when no package is selected. Promo packages override rate and margin for organizers who choose them.</p>
        {error && <p className="form-error">{error}</p>}
        {notice && <p className="form-success">{notice}</p>}

        <article className="superadmin-admin-card" style={{ marginTop: '1rem' }}>
          <strong>Default pricing (app_config/pricing)</strong>
          <form onSubmit={handleSavePricing} className="superadmin-admin-form">
            <label className="input-group">
              <span className="input-group__label">Default SMS rate (GHS per message)</span>
              <input
                type="number"
                step="0.01"
                min="0"
                value={pricingForm.defaultSmsRateGhs}
                onChange={(e) => setPricingForm((f) => ({ ...f, defaultSmsRateGhs: e.target.value }))}
              />
            </label>
            <label className="input-group">
              <span className="input-group__label">SMS margin multiplier (e.g. 1.5 = 50% margin)</span>
              <input
                type="number"
                step="0.1"
                min="1"
                value={pricingForm.smsMarginMultiplier}
                onChange={(e) => setPricingForm((f) => ({ ...f, smsMarginMultiplier: e.target.value }))}
              />
            </label>
            <button type="submit" className="button button--primary" disabled={savingPricing}>
              {savingPricing ? 'Saving…' : 'Save pricing'}
            </button>
          </form>
        </article>

        <article className="superadmin-admin-card" style={{ marginTop: '1.5rem' }}>
          <strong>Promo packages</strong>
          <p className="superadmin-admin-card__intro">Organizers can select a package on the Promote page. Only active packages are shown.</p>
          {editingId !== null ? (
            <form onSubmit={handleSavePackage} className="superadmin-admin-form" style={{ marginBottom: '1rem' }}>
              <input type="hidden" value={editingId} readOnly />
              <label className="input-group">
                <span className="input-group__label">Name *</span>
                <input
                  type="text"
                  value={packageForm.name}
                  onChange={(e) => setPackageForm((f) => ({ ...f, name: e.target.value }))}
                  placeholder="e.g. Standard"
                />
              </label>
              <label className="input-group">
                <span className="input-group__label">Description</span>
                <input
                  type="text"
                  value={packageForm.description}
                  onChange={(e) => setPackageForm((f) => ({ ...f, description: e.target.value }))}
                />
              </label>
              <label className="input-group">
                <span className="input-group__label">Order (display order)</span>
                <input
                  type="number"
                  value={packageForm.order}
                  onChange={(e) => setPackageForm((f) => ({ ...f, order: Number(e.target.value) || 0 }))}
                />
              </label>
              <label className="input-group">
                <span className="input-group__label">Default SMS rate (GHS)</span>
                <input
                  type="number"
                  step="0.01"
                  value={packageForm.defaultSmsRateGhs}
                  onChange={(e) => setPackageForm((f) => ({ ...f, defaultSmsRateGhs: e.target.value }))}
                />
              </label>
              <label className="input-group">
                <span className="input-group__label">SMS margin multiplier</span>
                <input
                  type="number"
                  step="0.1"
                  min="1"
                  value={packageForm.smsMarginMultiplier}
                  onChange={(e) => setPackageForm((f) => ({ ...f, smsMarginMultiplier: e.target.value }))}
                />
              </label>
              <label className="input-group">
                <span className="input-group__label">Min spend (GHS, optional)</span>
                <input
                  type="number"
                  step="1"
                  value={packageForm.minSpend}
                  onChange={(e) => setPackageForm((f) => ({ ...f, minSpend: e.target.value }))}
                />
              </label>
              <label className="checkbox">
                <input
                  type="checkbox"
                  checked={packageForm.active}
                  onChange={(e) => setPackageForm((f) => ({ ...f, active: e.target.checked }))}
                />
                <span>Active (visible to organizers)</span>
              </label>
              <div style={{ display: 'flex', gap: '0.5rem', marginTop: '0.5rem' }}>
                <button type="submit" className="button button--primary" disabled={savingPackage}>
                  {savingPackage ? 'Saving…' : 'Save package'}
                </button>
                <button type="button" className="button button--ghost" onClick={() => setEditingId(null)}>
                  Cancel
                </button>
              </div>
            </form>
          ) : (
            <button type="button" className="button button--secondary" onClick={openNew} style={{ marginBottom: '1rem' }}>
              Add package
            </button>
          )}
          <div className="superadmin-admin-list">
            {packages.map((pkg) => (
              <article className="superadmin-admin-list__item" key={pkg.id}>
                <div>
                  <strong>{pkg.name}</strong>
                  {!pkg.active && <span className="text-subtle"> (inactive)</span>}
                  <p className="superadmin-admin-list__meta">
                    Order {pkg.order} · Rate {pkg.defaultSmsRateGhs} GHS · Margin ×{pkg.smsMarginMultiplier}
                    {pkg.minSpend != null && ` · Min spend ${pkg.minSpend} GHS`}
                  </p>
                </div>
                <button type="button" className="button button--ghost" onClick={() => openEdit(pkg)}>
                  Edit
                </button>
              </article>
            ))}
            {packages.length === 0 && editingId === null && <p className="text-subtle">No packages yet. Add one to offer tiered pricing.</p>}
          </div>
        </article>
      </section>
    </>
  )
}
