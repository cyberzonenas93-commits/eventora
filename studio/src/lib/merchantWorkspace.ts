import type { OrganizerApplication, OrganizerApplicationStatus, UserProfile } from './types'

export function getWorkspaceName(
  application: OrganizerApplication | null,
  profile: UserProfile | null,
) {
  return application?.organizerName?.trim() || profile?.displayName?.trim() || 'Eventora Studio'
}

export function getWorkspaceTagline(application: OrganizerApplication | null) {
  return (
    application?.brandTagline?.trim() ||
    'Run every launch, drop, and ticket release from one focused workspace.'
  )
}

export function getWorkspaceAccent(application: OrganizerApplication | null) {
  return application?.brandAccentColor?.trim() || '#f26b3d'
}

export function getPayoutReadiness(application: OrganizerApplication | null) {
  if (!application) {
    return {
      ready: false,
      label: 'Payout profile not started',
      detail: 'Add a settlement destination so payouts are ready when sales begin.',
    }
  }

  if (!application.agreedToPayoutTerms) {
    return {
      ready: false,
      label: 'Payout terms still pending',
      detail: 'Confirm your payout preferences to finish this section.',
    }
  }

  if (application.payoutMethod === 'mobile-money') {
    const ready = Boolean(
      application.network.trim() &&
        application.payoutPhone.trim() &&
        application.accountName.trim(),
    )
    return {
      ready,
      label: ready ? 'Mobile money destination ready' : 'Mobile money details incomplete',
      detail: ready
        ? `${application.accountName} • ${application.network} • ${application.payoutPhone}`
        : 'Add the payout name, preferred network, and payout phone number.',
    }
  }

  const ready = Boolean(
    application.bankName.trim() &&
      application.accountName.trim() &&
      application.accountNumber.trim(),
  )
  return {
    ready,
    label: ready ? 'Bank settlement ready' : 'Bank details incomplete',
    detail: ready
      ? `${application.bankName} • ${application.accountNumber}`
      : 'Add the bank name, account name, and account number.',
  }
}

export function getReviewTimeline(status: OrganizerApplicationStatus) {
  if (status === 'active' || status === 'approved') {
    return [
      {
        label: 'Account created',
        detail: 'Your Eventora Studio workspace is live and ready to use.',
        state: 'complete',
      },
      {
        label: 'Workspace setup',
        detail: 'Brand details and payout preferences can be updated anytime.',
        state: 'complete',
      },
      {
        label: 'First event',
        detail: 'Create, publish, and manage events directly from your dashboard.',
        state: 'current',
      },
    ] as const
  }

  const submittedOrBeyond =
    status === 'submitted' || status === 'under_review' || status === 'rejected'
  const reviewedOrResolved = status === 'under_review' || status === 'rejected'

  const timeline = [
    {
      label: 'Merchant details captured',
      detail: 'Identity, trust context, and payout profile are saved in Studio.',
      state: status === 'not_started' ? 'pending' : 'complete',
    },
    {
      label: 'Application submitted',
      detail: 'Your workspace enters the review queue for Eventora operations.',
      state: submittedOrBeyond ? 'complete' : 'pending',
    },
    {
      label: 'Operations review',
      detail: 'Verification documents, payout details, and organizer fit are checked.',
      state: status === 'under_review' ? 'current' : reviewedOrResolved ? 'complete' : 'pending',
    },
    {
      label: status === 'rejected' ? 'Changes requested' : 'Publishing unlocked',
      detail:
        status === 'rejected'
          ? 'Update the flagged items, then resubmit to move forward.'
          : 'Approved workspaces can create and publish events in the main portal.',
      state: status === 'rejected' ? 'current' : 'pending',
    },
  ] as const

  return timeline
}
