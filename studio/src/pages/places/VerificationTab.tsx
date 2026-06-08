import { FileText, Phone, ShieldCheck, UploadCloud } from 'lucide-react'
import type { FormEvent } from 'react'

import type { PortalPlace } from '../../lib/types'
import { maskPhone, verificationLabel } from './helpers'
import { VerificationBadge } from './VerificationBadge'

type VerificationTabProps = {
  selectedPlace: PortalPlace | null
  selectedPlaceVerified: boolean
  canVerifyByPhone: boolean
  otpTarget: string
  otpCode: string
  setOtpCode: (value: string) => void
  otpConfirming: boolean
  otpSending: boolean
  confirmPhoneOtp: (e: FormEvent) => void
  sendPhoneOtp: () => void
  verificationMethod: string
  setVerificationMethod: (value: string) => void
  verificationEmail: string
  setVerificationEmail: (value: string) => void
  verificationPhone: string
  setVerificationPhone: (value: string) => void
  verificationMapsUrl: string
  setVerificationMapsUrl: (value: string) => void
  verificationWebsiteUrl: string
  setVerificationWebsiteUrl: (value: string) => void
  verificationSocialUrl: string
  setVerificationSocialUrl: (value: string) => void
  verificationNotes: string
  setVerificationNotes: (value: string) => void
  verificationFile: File | null
  setVerificationFile: (value: File | null) => void
  saving: boolean
  requestVerification: (e: FormEvent) => void
}

export function VerificationTab({
  selectedPlace,
  selectedPlaceVerified,
  canVerifyByPhone,
  otpTarget,
  otpCode,
  setOtpCode,
  otpConfirming,
  otpSending,
  confirmPhoneOtp,
  sendPhoneOtp,
  verificationMethod,
  setVerificationMethod,
  verificationEmail,
  setVerificationEmail,
  verificationPhone,
  setVerificationPhone,
  verificationMapsUrl,
  setVerificationMapsUrl,
  verificationWebsiteUrl,
  setVerificationWebsiteUrl,
  verificationSocialUrl,
  setVerificationSocialUrl,
  verificationNotes,
  setVerificationNotes,
  verificationFile,
  setVerificationFile,
  saving,
  requestVerification,
}: VerificationTabProps) {
  return (
    <article className="panel">
      <div className="panel__header">
        <div>
          <p className="eyebrow">Verification</p>
          <h3>{selectedPlace?.verified ? 'Verified owner' : 'Verify this location'}</h3>
        </div>
        <ShieldCheck size={22} aria-hidden />
      </div>
      <div className="order-row">
        <div>
          <strong>{selectedPlace ? verificationLabel(selectedPlace) : 'Create a place first'}</strong>
          <span>
            Anyone can create a profile. Verification unlocks paid subscriber push, official ownership signals, and featured placement requests.
          </span>
        </div>
        {selectedPlace ? <VerificationBadge place={selectedPlace} /> : null}
      </div>

      {selectedPlace && !selectedPlaceVerified ? (
        canVerifyByPhone ? (
          <div className="places-verify-phone">
            <div className="order-row">
              <div>
                <strong>Verify by phone</strong>
                <span>
                  We can send a 6-digit code to the business phone on file
                  {selectedPlace.verifiablePhone ? ` (${maskPhone(selectedPlace.verifiablePhone)})` : ''}.
                </span>
              </div>
              <Phone size={18} aria-hidden />
            </div>
            {otpTarget ? (
              <form className="form-grid form-grid--single" onSubmit={confirmPhoneOtp}>
                <p className="text-subtle">Enter the 6-digit code sent to {otpTarget}.</p>
                <label>
                  <span>Verification code</span>
                  <input
                    autoComplete="one-time-code"
                    inputMode="numeric"
                    maxLength={6}
                    onChange={(e) => setOtpCode(e.target.value.replace(/\D/g, '').slice(0, 6))}
                    placeholder="123456"
                    value={otpCode}
                  />
                </label>
                <div className="cover-upload-preview__actions">
                  <button
                    className="button button--primary"
                    disabled={otpConfirming || otpCode.trim().length !== 6}
                    type="submit"
                  >
                    <ShieldCheck size={16} aria-hidden />
                    {otpConfirming ? 'Verifying…' : 'Confirm code'}
                  </button>
                  <button
                    className="button button--ghost"
                    disabled={otpSending}
                    onClick={() => void sendPhoneOtp()}
                    type="button"
                  >
                    {otpSending ? 'Sending…' : 'Resend code'}
                  </button>
                </div>
              </form>
            ) : (
              <button
                className="button button--primary"
                disabled={otpSending}
                onClick={() => void sendPhoneOtp()}
                type="button"
              >
                <Phone size={16} aria-hidden />
                {otpSending ? 'Sending code…' : 'Send code by phone'}
              </button>
            )}
          </div>
        ) : (
          <div className="empty-card">
            <h4><FileText size={16} aria-hidden /> Document verification required</h4>
            <p>
              This place has no verifiable phone on file, so instant phone verification isn't
              available. Submit ownership documents below and our team will review them.
            </p>
          </div>
        )
      ) : null}

      {selectedPlace && !selectedPlaceVerified ? (
      <form className="form-grid" onSubmit={requestVerification}>
        <label>
          <span>Verification method</span>
          <select value={verificationMethod} onChange={(e) => setVerificationMethod(e.target.value)}>
            <option value="email">Regular email</option>
            <option value="phone">Business phone</option>
            <option value="document">Document upload</option>
            <option value="google_maps">Google Maps match</option>
            <option value="website_social">Website / social proof</option>
          </select>
        </label>
        {verificationMethod === 'email' ? (
        <label>
          <span>Contact email</span>
          <input
            inputMode="email"
            type="email"
            value={verificationEmail}
            onChange={(e) => setVerificationEmail(e.target.value)}
            placeholder="Any email you can access"
          />
        </label>
        ) : null}
        {verificationMethod === 'phone' ? (
        <label>
          <span>Phone</span>
          <input value={verificationPhone} onChange={(e) => setVerificationPhone(e.target.value)} />
        </label>
        ) : null}
        {verificationMethod === 'google_maps' ? (
        <label>
          <span>Google Maps link</span>
          <input value={verificationMapsUrl} onChange={(e) => setVerificationMapsUrl(e.target.value)} />
        </label>
        ) : null}
        {verificationMethod === 'website_social' ? (
        <>
        <label>
          <span>Website</span>
          <input value={verificationWebsiteUrl} onChange={(e) => setVerificationWebsiteUrl(e.target.value)} />
        </label>
        <label>
          <span>Social link</span>
          <input value={verificationSocialUrl} onChange={(e) => setVerificationSocialUrl(e.target.value)} />
        </label>
        </>
        ) : null}
        {verificationMethod === 'document' ? (
        <label className="form-grid__wide">
          <span>Proof document</span>
          <input
            accept="image/*,.pdf"
            onChange={(e) => setVerificationFile(e.target.files?.[0] ?? null)}
            type="file"
          />
        </label>
        ) : null}
        <label className="form-grid__wide">
          <span>Notes for reviewer</span>
          <textarea
            value={verificationNotes}
            onChange={(e) => setVerificationNotes(e.target.value)}
            rows={3}
            placeholder="Tell us how you are connected to this location."
          />
        </label>
        <button className="button button--primary" disabled={saving} type="submit">
          {verificationFile ? <UploadCloud size={16} aria-hidden /> : <FileText size={16} aria-hidden />}
          Submit verification
        </button>
      </form>
      ) : null}

      {selectedPlaceVerified ? (
        <div className="empty-card">
          <h4><ShieldCheck size={16} aria-hidden /> This place is verified</h4>
          <p>Paid subscriber push and featured placement are unlocked for this location.</p>
        </div>
      ) : null}
    </article>
  )
}
