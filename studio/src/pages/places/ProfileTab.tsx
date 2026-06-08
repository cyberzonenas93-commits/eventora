import { CheckCircle2, Store } from 'lucide-react'
import type { FormEvent } from 'react'

import type { PortalPlace } from '../../lib/types'
import { verificationLabel } from './helpers'

type ProfileTabProps = {
  selectedPlace: PortalPlace | null
  profileName: string
  setProfileName: (value: string) => void
  profileCity: string
  setProfileCity: (value: string) => void
  profileAddress: string
  setProfileAddress: (value: string) => void
  profilePhone: string
  setProfilePhone: (value: string) => void
  profileWebsite: string
  setProfileWebsite: (value: string) => void
  profileDescription: string
  setProfileDescription: (value: string) => void
  saving: boolean
  saveProfile: (e: FormEvent) => void
}

export function ProfileTab({
  selectedPlace,
  profileName,
  setProfileName,
  profileCity,
  setProfileCity,
  profileAddress,
  setProfileAddress,
  profilePhone,
  setProfilePhone,
  profileWebsite,
  setProfileWebsite,
  profileDescription,
  setProfileDescription,
  saving,
  saveProfile,
}: ProfileTabProps) {
  return (
    <article className="panel">
      <div className="panel__header">
        <div>
          <p className="eyebrow">Profile</p>
          <h3>{selectedPlace ? selectedPlace.name : 'Create a place'}</h3>
        </div>
        <Store size={22} aria-hidden />
      </div>
      <div className="hero-chip-row">
        <span>{selectedPlace ? verificationLabel(selectedPlace) : 'Self-serve onboarding'}</span>
        {!selectedPlace || selectedPlace.verified ? null : (
          <span>Verification unlocks paid push and featured placement</span>
        )}
      </div>
      <form className="form-grid" onSubmit={saveProfile}>
        <label>
          <span>Name</span>
          <input value={profileName} onChange={(e) => setProfileName(e.target.value)} required />
        </label>
        <label>
          <span>City</span>
          <input value={profileCity} onChange={(e) => setProfileCity(e.target.value)} />
        </label>
        <label className="form-grid__wide">
          <span>Address</span>
          <input value={profileAddress} onChange={(e) => setProfileAddress(e.target.value)} />
        </label>
        <label>
          <span>Phone</span>
          <input value={profilePhone} onChange={(e) => setProfilePhone(e.target.value)} />
        </label>
        <label>
          <span>Website / social</span>
          <input value={profileWebsite} onChange={(e) => setProfileWebsite(e.target.value)} />
        </label>
        <label className="form-grid__wide">
          <span>Description</span>
          <textarea value={profileDescription} onChange={(e) => setProfileDescription(e.target.value)} rows={4} />
        </label>
        <button className="button button--primary" disabled={saving} type="submit">
          <CheckCircle2 size={16} aria-hidden />
          {selectedPlace ? 'Save place' : 'Create unverified place'}
        </button>
      </form>
    </article>
  )
}
