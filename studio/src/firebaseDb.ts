import { connectFirestoreEmulator, getFirestore } from 'firebase/firestore'

import { app } from './firebaseApp'

export const db = getFirestore(app)

if (import.meta.env.VITE_USE_FIREBASE_EMULATORS === 'true') {
  connectFirestoreEmulator(
    db,
    import.meta.env.VITE_FIREBASE_FIRESTORE_EMULATOR_HOST || '127.0.0.1',
    Number(import.meta.env.VITE_FIREBASE_FIRESTORE_EMULATOR_PORT || 8080),
  )
}
