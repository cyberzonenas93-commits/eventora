import { connectAuthEmulator, getAuth } from 'firebase/auth'

import { app } from './firebaseApp'

export const auth = getAuth(app)

if (import.meta.env.VITE_USE_FIREBASE_EMULATORS === 'true') {
  connectAuthEmulator(
    auth,
    `http://${import.meta.env.VITE_FIREBASE_AUTH_EMULATOR_HOST || '127.0.0.1'}:${import.meta.env.VITE_FIREBASE_AUTH_EMULATOR_PORT || 9099}`,
    { disableWarnings: true },
  )
}
