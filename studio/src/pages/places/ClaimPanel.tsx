import { Search } from 'lucide-react'
import type { FormEvent } from 'react'

type ClaimSuggestion = { placeId: string; title: string; subtitle: string; fullText: string }

type ClaimPanelProps = {
  claimQuery: string
  setClaimQuery: (value: string) => void
  searchPlacesToClaim: (e: FormEvent) => void
  claimSearching: boolean
  claimSuggestions: ClaimSuggestion[]
  claimingId: string
  claimPlace: (googlePlaceId: string) => void
}

export function ClaimPanel({
  claimQuery,
  setClaimQuery,
  searchPlacesToClaim,
  claimSearching,
  claimSuggestions,
  claimingId,
  claimPlace,
}: ClaimPanelProps) {
  return (
    <article className="panel">
      <div className="panel__header">
        <div>
          <p className="eyebrow">Claim a place</p>
          <h3>Find your business on Google</h3>
        </div>
        <Search size={22} aria-hidden />
      </div>
      <p className="text-subtle">
        Search Google for your venue and claim it. We import the name, address, and phone so you
        can verify ownership.
      </p>
      <form className="form-grid form-grid--single" onSubmit={searchPlacesToClaim}>
        <label>
          <span>Business name or address</span>
          <input
            value={claimQuery}
            onChange={(e) => setClaimQuery(e.target.value)}
            placeholder="e.g. Skybar 25, Accra"
          />
        </label>
        <button className="button button--secondary" disabled={claimSearching || !claimQuery.trim()} type="submit">
          <Search size={16} aria-hidden />
          {claimSearching ? 'Searching…' : 'Search Google'}
        </button>
      </form>
      <div className="order-list">
        {claimSuggestions.length === 0 ? (
          <div className="empty-card">
            <h4>No results yet</h4>
            <p>Search for your business to claim it from Google, or create a profile manually below.</p>
          </div>
        ) : (
          claimSuggestions.map((suggestion) => (
            <div className="order-row" key={suggestion.placeId}>
              <div>
                <strong>{suggestion.title}</strong>
                <span>{suggestion.subtitle}</span>
              </div>
              <button
                className="button button--primary"
                disabled={Boolean(claimingId)}
                onClick={() => claimPlace(suggestion.placeId)}
                type="button"
              >
                {claimingId === suggestion.placeId ? 'Claiming…' : 'Claim'}
              </button>
            </div>
          ))
        )}
      </div>
    </article>
  )
}
