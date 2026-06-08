import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import './index.css'
import App from './App.tsx'
import { initProductAnalytics } from './lib/analytics'
import { initErrorReporting } from './lib/errorReporting'

// Initialise Sentry before rendering. No-ops when VITE_SENTRY_DSN is unset.
initErrorReporting()
initProductAnalytics()

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <App />
  </StrictMode>,
)
