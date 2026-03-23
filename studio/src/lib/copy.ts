/**
 * Shared user-facing copy for errors, loading, and success states.
 * Use these so language is consistent and easy to update across the app.
 */
export const copy = {
  /** Generic */
  somethingWentWrong: 'Something went wrong.',
  pleaseTryAgain: 'Please try again.',
  tryAgain: 'Try again',
  loading: 'Loading…',
  save: 'Save',
  cancel: 'Cancel',

  /** Auth */
  authFailed: 'We couldn’t sign you in. Check your email and password, then try again.',
  signUpFailed: 'We couldn’t create your account. Please check the form and try again.',
  completeRequiredFields: 'Please complete all required fields and use a stronger password.',
  validEmailAndPassword: 'Enter a valid email address and password to continue.',
  googleSignInFailed: 'Google sign-in didn’t work. Please try again.',
  appleSignInFailed: 'Apple sign-in didn’t work. Please try again.',

  /** Data loading */
  loadFailed: 'We couldn’t load this. Check your connection and try again.',
  overviewLoadFailed: 'We couldn’t load your overview.',
  ordersLoadFailed: 'We couldn’t load orders.',
  eventsLoadFailed: 'We couldn’t load events.',
  contactsLoadFailed: 'We couldn’t load contacts.',
  paymentsLoadFailed: 'We couldn’t load payout data.',
  campaignsLoadFailed: 'We couldn’t load campaigns.',
  pricingLoadFailed: 'We couldn’t load pricing.',
  applicationsLoadFailed: 'We couldn’t load organizer applications.',
  adminAccountsLoadFailed: 'We couldn’t load admin accounts.',
  adminCreateFailed: 'We couldn’t create the admin account. Please try again.',

  /** Saving / actions */
  saveFailed: 'We couldn’t save. Please try again.',
  eventSaveFailed: 'We couldn’t save the event. Please try again.',
  setupSaveFailed: 'We couldn’t save your details. Please try again.',
  uploadFailed: 'We couldn’t upload the file. Please try again.',
  campaignLaunchFailed: 'We couldn’t launch the campaign. Please try again.',
  campaignLaunchInsufficient: 'Load your wallet in Payments & Payouts to run SMS campaigns.',
  recordOptOutFailed: 'We couldn’t record the opt-out. Please try again.',
  reviewFailed: 'We couldn’t submit your decision. Please try again.',
  pricingSaveFailed: 'We couldn’t save. Please try again.',
  packageSaveFailed: 'We couldn’t save the package. Please try again.',

  /** Validation */
  selectEventMessageAndChannel: 'Select an event, enter a message, and choose at least one channel (Push or SMS).',
  packageNameRequired: 'Package name is required.',
  defaultSmsRateInvalid: 'Default SMS rate must be a non-negative number.',
  smsMarginInvalid: 'SMS margin multiplier must be at least 1.',

  /** Success */
  saved: 'Saved.',
  updated: 'Updated.',
  optOutRecorded: 'Opt-out recorded.',
  campaignLaunched: 'Campaign launched.',

  /** Unsubscribe (public) */
  unsubscribeError: 'We couldn’t process your request. Please try again.',
  unsubscribeNetworkError: 'Network error. Please try again.',

  /** Error boundary */
  errorBoundaryTitle: 'Something went wrong',
  errorBoundaryMessage: 'We hit an unexpected error. You can try again or go back to the start.',
  errorBoundaryAction: 'Try again',
  errorBoundaryHome: 'Go to home',
} as const
