import { getApp, getApps, initializeApp } from 'firebase/app'

// Hardcoded fallbacks keep local dev working without a populated .env, but a
// production build that silently falls back to these is a misconfiguration.
// Warn (dev only) for any missing VITE_FIREBASE_* var so it's visible.
if (import.meta.env.DEV) {
  const missing = (
    [
      'VITE_FIREBASE_API_KEY',
      'VITE_FIREBASE_AUTH_DOMAIN',
      'VITE_FIREBASE_PROJECT_ID',
      'VITE_FIREBASE_STORAGE_BUCKET',
      'VITE_FIREBASE_MESSAGING_SENDER_ID',
      'VITE_FIREBASE_APP_ID',
    ] as const
  ).filter((key) => !import.meta.env[key])
  if (missing.length > 0) {
    console.warn(
      `[firebaseApp] Missing env var(s): ${missing.join(', ')}. ` +
        'Using hardcoded fallback Firebase config — set these in studio/.env to avoid a misconfigured build.',
    )
  }
}

const firebaseConfig = {
  apiKey: import.meta.env.VITE_FIREBASE_API_KEY || 'AIzaSyAKv05vJYQgLPb0vDdEUt2aPZmv5rID42U',
  authDomain: import.meta.env.VITE_FIREBASE_AUTH_DOMAIN || 'vennuzo.com',
  projectId: import.meta.env.VITE_FIREBASE_PROJECT_ID || 'eventora-10063',
  storageBucket: import.meta.env.VITE_FIREBASE_STORAGE_BUCKET || 'eventora-10063.firebasestorage.app',
  messagingSenderId: import.meta.env.VITE_FIREBASE_MESSAGING_SENDER_ID || '872808273884',
  appId: import.meta.env.VITE_FIREBASE_APP_ID || '1:872808273884:web:d73aeb08ba0941b28c2119',
  measurementId: import.meta.env.VITE_FIREBASE_MEASUREMENT_ID || undefined,
}

export const app = getApps().length > 0 ? getApp() : initializeApp(firebaseConfig)
