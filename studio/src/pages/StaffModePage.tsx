import { useEffect, useMemo, useState, type FormEvent } from 'react'
import { useParams } from 'react-router-dom'
import { httpsCallable } from 'firebase/functions'
import { Banknote, ClipboardList, LockKeyhole, LogOut, Plus, RefreshCw, Smartphone } from 'lucide-react'

import { functions } from '../firebaseFunctions'
import { getErrorMessage } from '../lib/errorMessages'
import { formatMoney } from '../lib/formatters'

interface StaffInventoryItem {
  id: string
  name: string
  category: string
  sellingGhs: number
  stock: number
  listed: boolean
}

interface StaffTab {
  id: string
  staffId: string
  customer: string
  itemId: string
  itemName: string
  quantity: number
  totalAmount: number
  status: 'open' | 'closed'
  paymentMethod: string
  closedAt?: string | null
}

interface StaffMember {
  id: string
  name: string
  role: string
  station: string
}

interface StaffWorkspaceResult {
  success: boolean
  sessionId?: string
  sessionToken?: string
  expiresAt?: string
  config: {
    eventId: string
    eventTitle: string
    staffAccessCode?: string
    paymentMode: 'merchant_collected' | 'vennuzo_controlled'
  }
  staff: StaffMember
  inventory: StaffInventoryItem[]
  tabs: StaffTab[]
}

interface StaffSession {
  eventId: string
  sessionId: string
  sessionToken: string
  expiresAt: string
}

const startEventOpsStaffSession = httpsCallable<
  { eventId: string; pin: string },
  StaffWorkspaceResult
>(functions, 'startEventOpsStaffSession')

const getEventOpsStaffWorkspace = httpsCallable<
  { eventId: string; sessionId: string; sessionToken: string },
  StaffWorkspaceResult
>(functions, 'getEventOpsStaffWorkspace')

const createEventOpsStaffTab = httpsCallable<
  { eventId: string; sessionId: string; sessionToken: string; customer: string; itemId: string; quantity: number },
  StaffWorkspaceResult
>(functions, 'createEventOpsStaffTab')

const closeEventOpsStaffTab = httpsCallable<
  { eventId: string; sessionId: string; sessionToken: string; tabId: string; paymentMethod: string },
  StaffWorkspaceResult
>(functions, 'closeEventOpsStaffTab')

const demoWorkspace: StaffWorkspaceResult = {
  success: true,
  config: {
    eventId: 'demo_event_ops',
    eventTitle: 'Vennuzo Event Ops Demo',
    paymentMode: 'merchant_collected',
  },
  staff: {
    id: 'staff_demo',
    name: 'Demo Waiter',
    role: 'Waiter',
    station: 'VIP',
  },
  inventory: [
    { id: 'item_moet', name: 'Moet Bottle Service', category: 'Drinks', sellingGhs: 950, stock: 24, listed: true },
    { id: 'item_shisha', name: 'Premium Shisha', category: 'Experience', sellingGhs: 180, stock: 35, listed: true },
    { id: 'item_platter', name: 'Chef Platter', category: 'Food', sellingGhs: 400, stock: 18, listed: true },
  ],
  tabs: [
    {
      id: 'tab_demo_1',
      staffId: 'staff_demo',
      customer: 'Birthday Table',
      itemId: 'item_platter',
      itemName: 'Chef Platter',
      quantity: 2,
      totalAmount: 800,
      status: 'open',
      paymentMethod: 'Pending',
    },
  ],
}

function staffSessionKey(eventId: string) {
  return `vennuzo:event-ops-staff:${eventId}`
}

function readStaffSession(eventId: string): StaffSession | null {
  if (!eventId || typeof window === 'undefined') return null
  try {
    const raw = window.localStorage.getItem(staffSessionKey(eventId))
    if (!raw) return null
    const parsed = JSON.parse(raw) as StaffSession
    if (!parsed.sessionId || !parsed.sessionToken) return null
    if (parsed.expiresAt && new Date(parsed.expiresAt).getTime() < Date.now()) return null
    return parsed
  } catch {
    return null
  }
}

function writeStaffSession(session: StaffSession | null, accessKey?: string) {
  if (typeof window === 'undefined') return
  if (!session) return
  window.localStorage.setItem(staffSessionKey(session.eventId), JSON.stringify(session))
  if (accessKey && accessKey !== session.eventId) {
    window.localStorage.setItem(staffSessionKey(accessKey), JSON.stringify(session))
  }
}

export function StaffModePage() {
  const params = useParams()
  const [eventId, setEventId] = useState(params.eventId || '')
  const [pin, setPin] = useState('')
  const [workspace, setWorkspace] = useState<StaffWorkspaceResult | null>(null)
  const [session, setSession] = useState<StaffSession | null>(null)
  const [customer, setCustomer] = useState('Walk-in')
  const [selectedItemId, setSelectedItemId] = useState('')
  const [quantity, setQuantity] = useState('1')
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [message, setMessage] = useState<string | null>(null)

  useEffect(() => {
    const id = params.eventId || ''
    setEventId((current) => current || id)
  }, [params.eventId])

  useEffect(() => {
    if (!eventId) return
    const saved = readStaffSession(eventId)
    if (!saved) return
    setSession(saved)
    setLoading(true)
    getEventOpsStaffWorkspace(saved)
      .then((result) => {
        setWorkspace(result.data)
        setSelectedItemId(result.data.inventory[0]?.id || '')
      })
      .catch(() => {
        setSession(null)
      })
      .finally(() => setLoading(false))
  }, [eventId])

  const openTabs = useMemo(() => workspace?.tabs.filter((tab) => tab.status === 'open') ?? [], [workspace])
  const closedTabs = useMemo(() => workspace?.tabs.filter((tab) => tab.status === 'closed') ?? [], [workspace])
  const mySales = closedTabs
    .filter((tab) => !workspace?.staff?.id || tab.staffId === workspace.staff.id)
    .reduce((sum, tab) => sum + Number(tab.totalAmount || 0), 0)
  const selectedItem = workspace?.inventory.find((item) => item.id === selectedItemId) ?? workspace?.inventory[0] ?? null
  const recentClosedTabs = useMemo(
    () =>
      closedTabs
        .filter((tab) => !workspace?.staff?.id || tab.staffId === workspace.staff.id)
        .slice(0, 8),
    [closedTabs, workspace?.staff?.id],
  )
  const stockWarning =
    selectedItem && selectedItem.stock <= 0
      ? 'Sold out'
      : selectedItem && selectedItem.stock <= 5
        ? `${selectedItem.stock} left`
        : selectedItem
          ? `${selectedItem.stock} in stock`
          : ''
  const requestedQuantity = Math.max(Number(quantity || 1), 1)
  const cannotOpenTab = !selectedItem || loading || selectedItem.stock <= 0 || requestedQuantity > selectedItem.stock

  function applyWorkspace(result: StaffWorkspaceResult, nextSession?: StaffSession) {
    setWorkspace(result)
    setSelectedItemId((current) => current || result.inventory[0]?.id || '')
    if (nextSession) {
      setSession(nextSession)
      writeStaffSession(nextSession)
    }
  }

  async function handleLogin(e: FormEvent) {
    e.preventDefault()
    const cleanEventId = eventId.trim()
    const cleanPin = pin.trim()
    if (!cleanEventId || !cleanPin) return
    setLoading(true)
    setError(null)
    setMessage(null)
    try {
      const result = await startEventOpsStaffSession({ eventId: cleanEventId, pin: cleanPin })
      const canonicalEventId = result.data.config.eventId || cleanEventId
      const nextSession = {
        eventId: canonicalEventId,
        sessionId: result.data.sessionId || '',
        sessionToken: result.data.sessionToken || '',
        expiresAt: result.data.expiresAt || new Date(Date.now() + 1000 * 60 * 60 * 8).toISOString(),
      }
      setEventId(canonicalEventId)
      applyWorkspace(result.data, nextSession)
      writeStaffSession(nextSession, cleanEventId)
      setMessage(`Signed in as ${result.data.staff.name}.`)
      setPin('')
    } catch (err) {
      setError(getErrorMessage(err, 'Could not sign in with that staff PIN.'))
    } finally {
      setLoading(false)
    }
  }

  function handleDemo() {
    setEventId(demoWorkspace.config.eventId)
    setSession({
      eventId: demoWorkspace.config.eventId,
      sessionId: 'demo',
      sessionToken: 'demo',
      expiresAt: new Date(Date.now() + 1000 * 60 * 60).toISOString(),
    })
    setWorkspace(demoWorkspace)
    setSelectedItemId(demoWorkspace.inventory[0]?.id || '')
    setMessage('Demo staff mode started.')
  }

  async function refreshWorkspace() {
    if (!session || session.sessionId === 'demo') return
    setLoading(true)
    setError(null)
    try {
      const result = await getEventOpsStaffWorkspace(session)
      applyWorkspace(result.data)
    } catch (err) {
      setError(getErrorMessage(err, 'Could not refresh staff workspace.'))
    } finally {
      setLoading(false)
    }
  }

  async function handleOpenTab(e: FormEvent) {
    e.preventDefault()
    if (!workspace || !session || !selectedItem) return
    const nextQuantity = requestedQuantity
    if (selectedItem.stock < nextQuantity) {
      setError(`${selectedItem.name} has only ${selectedItem.stock} unit${selectedItem.stock === 1 ? '' : 's'} left.`)
      return
    }
    setLoading(true)
    setError(null)
    try {
      if (session.sessionId === 'demo') {
        setWorkspace({
          ...workspace,
          tabs: [
            {
              id: `demo_tab_${Date.now()}`,
              staffId: workspace.staff.id,
              customer: customer.trim() || 'Walk-in',
              itemId: selectedItem.id,
              itemName: selectedItem.name,
              quantity: nextQuantity,
              totalAmount: selectedItem.sellingGhs * nextQuantity,
              status: 'open',
              paymentMethod: 'Pending',
            },
            ...workspace.tabs,
          ],
        })
      } else {
        const result = await createEventOpsStaffTab({
          ...session,
          customer: customer.trim() || 'Walk-in',
          itemId: selectedItem.id,
          quantity: nextQuantity,
        })
        applyWorkspace(result.data)
      }
      setCustomer('Walk-in')
      setQuantity('1')
      setMessage('Order opened.')
    } catch (err) {
      setError(getErrorMessage(err, 'Could not open this tab.'))
    } finally {
      setLoading(false)
    }
  }

  async function handleCloseTab(tabId: string, paymentMethod: string) {
    if (!workspace || !session) return
    setLoading(true)
    setError(null)
    try {
      if (session.sessionId === 'demo') {
        setWorkspace({
          ...workspace,
          tabs: workspace.tabs.map((tab) =>
            tab.id === tabId ? { ...tab, status: 'closed', paymentMethod } : tab,
          ),
        })
      } else {
        const result = await closeEventOpsStaffTab({ ...session, tabId, paymentMethod })
        applyWorkspace(result.data)
      }
      setMessage('Tab closed after payment.')
    } catch (err) {
      setError(getErrorMessage(err, 'Could not close this tab.'))
    } finally {
      setLoading(false)
    }
  }

  function handleSignOut() {
    if (session && typeof window !== 'undefined') {
      window.localStorage.removeItem(staffSessionKey(session.eventId))
      window.localStorage.removeItem(staffSessionKey(eventId))
    }
    setSession(null)
    setWorkspace(null)
    setPin('')
    setMessage(null)
  }

  if (!workspace || !session) {
    return (
      <main className="staff-mode staff-mode--login">
        <section className="staff-login-card">
          <div className="staff-login-card__brand">
            <Smartphone size={26} aria-hidden />
            <div>
              <p className="eyebrow">Vennuzo Staff Mode</p>
              <h1>Sign in to take event orders.</h1>
            </div>
          </div>
          {error && <p className="checkout__error">{error}</p>}
          {message && <p className="checkout__info">{message}</p>}
          <form className="staff-login-form" onSubmit={handleLogin}>
            <label>
              Event code
              <input value={eventId} onChange={(e) => setEventId(e.target.value)} placeholder="map-night" required />
            </label>
            <label>
              Staff PIN
              <input inputMode="numeric" maxLength={6} type="password" value={pin} onChange={(e) => setPin(e.target.value)} required />
            </label>
            <button className="button button--primary" disabled={loading} type="submit">
              <LockKeyhole size={16} aria-hidden />
              {loading ? 'Signing in...' : 'Open staff app'}
            </button>
          </form>
          <button className="button button--secondary" onClick={handleDemo} type="button">
            Try demo staff mode
          </button>
        </section>
      </main>
    )
  }

  return (
    <main className="staff-mode">
      <header className="staff-mode-header">
        <div>
          <p className="eyebrow">Vennuzo Staff Mode</p>
          <h1>{workspace.config.eventTitle}</h1>
          <span>{workspace.staff.name} · {workspace.staff.role} · {workspace.staff.station}</span>
        </div>
        <div className="staff-mode-header__actions">
          <button className="button button--secondary" onClick={() => void refreshWorkspace()} type="button">
            <RefreshCw size={16} aria-hidden />
            Refresh
          </button>
          <button className="button button--secondary" onClick={handleSignOut} type="button">
            <LogOut size={16} aria-hidden />
            Sign out
          </button>
        </div>
      </header>

      {error && <p className="checkout__error">{error}</p>}
      {message && <p className="checkout__info">{message}</p>}

      <section className="staff-kpi-grid">
        <div>
          <ClipboardList size={18} aria-hidden />
          <span>Open tabs</span>
          <strong>{openTabs.length}</strong>
        </div>
        <div>
          <Banknote size={18} aria-hidden />
          <span>My closed sales</span>
          <strong>{formatMoney(mySales)}</strong>
        </div>
      </section>

      <section className="staff-order-panel">
        <div className="panel__header">
          <div>
            <p className="eyebrow">New order</p>
            <h2>Open a customer tab</h2>
          </div>
        </div>
        <form className="staff-order-form" onSubmit={handleOpenTab}>
          <label>
            Customer/tab
            <input value={customer} onChange={(e) => setCustomer(e.target.value)} />
          </label>
          <label>
            Item
            <select value={selectedItemId} onChange={(e) => setSelectedItemId(e.target.value)}>
              {workspace.inventory.map((item) => (
                <option key={item.id} value={item.id}>
                  {item.name} · {formatMoney(item.sellingGhs)} · {item.stock <= 0 ? 'sold out' : `${item.stock} left`}
                </option>
              ))}
            </select>
            {selectedItem && (
              <small className={selectedItem.stock <= 5 ? 'staff-stock staff-stock--low' : 'staff-stock'}>
                {stockWarning}
              </small>
            )}
          </label>
          <label>
            Qty
            <input min={1} type="number" value={quantity} onChange={(e) => setQuantity(e.target.value)} />
          </label>
          <button className="button button--primary" disabled={cannotOpenTab} type="submit">
            <Plus size={16} aria-hidden />
            Open tab
          </button>
        </form>
      </section>

      <section className="staff-tab-list">
        <div className="panel__header">
          <div>
            <p className="eyebrow">Open tabs</p>
            <h2>Close when paid</h2>
          </div>
        </div>
        {openTabs.length === 0 ? (
          <div className="empty-card">
            <h4>No open tabs</h4>
            <p>New customer orders will appear here.</p>
          </div>
        ) : (
          openTabs.map((tab) => (
            <article className="staff-tab-card" key={tab.id}>
              <div>
                <strong>{tab.customer}</strong>
                <span>{tab.itemName} x {tab.quantity}</span>
                <small>{formatMoney(tab.totalAmount)}</small>
              </div>
              <div className="staff-tab-card__actions">
                <button className="button button--secondary" onClick={() => void handleCloseTab(tab.id, 'Cash')} type="button">Cash</button>
                <button className="button button--secondary" onClick={() => void handleCloseTab(tab.id, 'Merchant MoMo')} type="button">MoMo</button>
              </div>
            </article>
          ))
        )}
      </section>

      <section className="staff-tab-list">
        <div className="panel__header">
          <div>
            <p className="eyebrow">Recent sales</p>
            <h2>Closed by you</h2>
          </div>
        </div>
        {recentClosedTabs.length === 0 ? (
          <div className="empty-card">
            <h4>No closed tabs yet</h4>
            <p>Paid tabs you close will appear here for quick reconciliation.</p>
          </div>
        ) : (
          recentClosedTabs.map((tab) => (
            <article className="staff-tab-card staff-tab-card--closed" key={tab.id}>
              <div>
                <strong>{tab.customer}</strong>
                <span>{tab.itemName} x {tab.quantity}</span>
                <small>{formatMoney(tab.totalAmount)} · {tab.paymentMethod}</small>
              </div>
            </article>
          ))
        )}
      </section>
    </main>
  )
}
