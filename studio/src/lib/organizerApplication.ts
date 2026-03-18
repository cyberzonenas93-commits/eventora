import type { OrganizerApplication } from './types'

export const setupSteps = ['account', 'payout', 'launch'] as const

export function createEmptyApplication(
  seed?: Partial<OrganizerApplication>,
): OrganizerApplication {
  return {
    userId: seed?.userId ?? '',
    organizerName: seed?.organizerName ?? '',
    contactPerson: seed?.contactPerson ?? '',
    email: seed?.email ?? '',
    phone: seed?.phone ?? '',
    businessType: seed?.businessType ?? '',
    businessAddress: seed?.businessAddress ?? '',
    audienceCity: seed?.audienceCity ?? 'Accra',
    instagram: seed?.instagram ?? '',
    brandTagline: seed?.brandTagline ?? '',
    brandAccentColor: seed?.brandAccentColor ?? '#f26b3d',
    logoFileName: seed?.logoFileName ?? '',
    logoImageUrl: seed?.logoImageUrl ?? '',
    governmentIdFileName: seed?.governmentIdFileName ?? '',
    governmentIdUrl: seed?.governmentIdUrl ?? '',
    selfieFileName: seed?.selfieFileName ?? '',
    selfieUrl: seed?.selfieUrl ?? '',
    isRegisteredBusiness: seed?.isRegisteredBusiness ?? 'no',
    businessRegistrationNumber: seed?.businessRegistrationNumber ?? '',
    tinNumber: seed?.tinNumber ?? '',
    payoutMethod: seed?.payoutMethod ?? 'mobile-money',
    bankName: seed?.bankName ?? '',
    accountName: seed?.accountName ?? '',
    accountNumber: seed?.accountNumber ?? '',
    network: seed?.network ?? 'MTN Mobile Money',
    payoutPhone: seed?.payoutPhone ?? '',
    settlementPreference: seed?.settlementPreference ?? 'After event ends',
    agreedToPayoutTerms: seed?.agreedToPayoutTerms ?? false,
    agreesToCompliance: seed?.agreesToCompliance ?? false,
    status: seed?.status ?? 'active',
    reviewNotes: seed?.reviewNotes ?? '',
    organizationId: seed?.organizationId ?? `org_${seed?.userId ?? ''}`,
  }
}
