import { connectFunctionsEmulator, getFunctions } from 'firebase/functions'

import { app } from './firebaseApp'

export const functions = getFunctions(app, 'us-central1')

if (import.meta.env.VITE_USE_FIREBASE_EMULATORS === 'true') {
  connectFunctionsEmulator(
    functions,
    import.meta.env.VITE_FIREBASE_FUNCTIONS_EMULATOR_HOST || '127.0.0.1',
    Number(import.meta.env.VITE_FIREBASE_FUNCTIONS_EMULATOR_PORT || 5001),
  )
}
