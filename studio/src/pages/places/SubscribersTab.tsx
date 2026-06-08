import { Bell, Lock, Send, Star, Users, type LucideIcon } from 'lucide-react'
import type { FormEvent } from 'react'

import { formatMoney } from '../../lib/formatters'
import type { PortalPlace } from '../../lib/types'

type SubscribersTabProps = {
  selectedPlace: PortalPlace | null
  selectedPlaceVerified: boolean
  pushTitle: string
  setPushTitle: (value: string) => void
  pushMessage: string
  setPushMessage: (value: string) => void
  saving: boolean
  sendPlacePush: (e: FormEvent) => void
}

export function SubscribersTab({
  selectedPlace,
  selectedPlaceVerified,
  pushTitle,
  setPushTitle,
  pushMessage,
  setPushMessage,
  saving,
  sendPlacePush,
}: SubscribersTabProps) {
  return (
    <article className="panel">
      <div className="panel__header">
        <div>
          <p className="eyebrow">Subscriber push</p>
          <h3>Paid location alerts</h3>
        </div>
        <Bell size={22} aria-hidden />
      </div>
      <div className="metric-grid">
        <Metric icon={Users} label="Subscribers" value={`${selectedPlace?.subscriberCount ?? 0}`} />
        <Metric icon={Star} label="Rating" value={(selectedPlace?.rating ?? 0).toFixed(1)} />
        <Metric icon={Send} label="Fee estimate" value={formatMoney((selectedPlace?.subscriberCount ?? 0) * 0.02)} />
      </div>
      {!selectedPlaceVerified ? (
        <div className="empty-card">
          <h4><Lock size={16} aria-hidden /> Verify this place to unlock</h4>
          <p>Paid subscriber push and featured placement unlock once this location is verified.</p>
        </div>
      ) : null}
      <form className="form-grid form-grid--single" onSubmit={sendPlacePush}>
        <label>
          <span>Push title</span>
          <input
            value={pushTitle}
            onChange={(e) => setPushTitle(e.target.value)}
            disabled={!selectedPlaceVerified}
          />
        </label>
        <label>
          <span>Message</span>
          <textarea
            value={pushMessage}
            onChange={(e) => setPushMessage(e.target.value)}
            rows={4}
            required
            disabled={!selectedPlaceVerified}
          />
        </label>
        <button className="button button--primary" disabled={!selectedPlaceVerified || saving} type="submit">
          <Send size={16} aria-hidden />
          Send paid push
        </button>
      </form>
    </article>
  )
}

function Metric({ icon: Icon, label, value }: { icon: LucideIcon; label: string; value: string }) {
  return (
    <div className="metric-card">
      <Icon size={18} aria-hidden />
      <strong>{value}</strong>
      <span>{label}</span>
    </div>
  )
}
