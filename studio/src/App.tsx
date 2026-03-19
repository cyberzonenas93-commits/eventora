import { Suspense, lazy, type ReactElement, useEffect, useState } from 'react'
import { BrowserRouter, Navigate, Route, Routes } from 'react-router-dom'

import { PortalSessionProvider, usePortalSession } from './lib/portalSession'

const LandingPage = lazy(() =>
  import('./pages/LandingPage').then((module) => ({ default: module.LandingPage })),
)
const SetupPage = lazy(() =>
  import('./pages/SetupPage').then((module) => ({ default: module.SetupPage })),
)
const OverviewPage = lazy(() =>
  import('./pages/OverviewPage').then((module) => ({ default: module.OverviewPage })),
)
const EventsPage = lazy(() =>
  import('./pages/EventsPage').then((module) => ({ default: module.EventsPage })),
)
const EventEditorPage = lazy(() =>
  import('./pages/EventEditorPage').then((module) => ({
    default: module.EventEditorPage,
  })),
)
const SettingsPage = lazy(() =>
  import('./pages/SettingsPage').then((module) => ({ default: module.SettingsPage })),
)
const PortalLayout = lazy(() =>
  import('./components/PortalLayout').then((module) => ({ default: module.PortalLayout })),
)
const SuperadminApprovalsPage = lazy(() =>
  import('./pages/SuperadminApprovalsPage').then((module) => ({
    default: module.SuperadminApprovalsPage,
  })),
)

function AppRoutes() {
  const session = usePortalSession()
  const [showSplash, setShowSplash] = useState(true)

  useEffect(() => {
    const timer = window.setTimeout(() => setShowSplash(false), 1800)
    return () => window.clearTimeout(timer)
  }, [])

  if (showSplash || session.loading) {
    return <StudioSplash />
  }

  return (
    <Suspense fallback={<StudioSplash />}>
      <Routes>
        <Route element={<LandingPage />} path="/" />
        <Route
          element={
            <RequireSignedIn>
              <SetupPage />
            </RequireSignedIn>
          }
          path="/setup/:step"
        />
        <Route
          element={
            <RequireSignedIn>
              <Navigate replace to="/overview" />
            </RequireSignedIn>
          }
          path="/review"
        />
        <Route
          element={
            <RequireAdmin>
              <SuperadminApprovalsPage />
            </RequireAdmin>
          }
          path="/superadmin/approvals"
        />
        <Route
          element={
            <RequireOrganizer>
              <PortalLayout />
            </RequireOrganizer>
          }
        >
          <Route element={<Navigate replace to="/overview" />} path="/dashboard" />
          <Route element={<OverviewPage />} path="/overview" />
          <Route element={<EventsPage />} path="/events" />
          <Route element={<EventEditorPage />} path="/events/new" />
          <Route element={<EventEditorPage />} path="/events/:eventId/edit" />
          <Route element={<SettingsPage />} path="/settings" />
        </Route>
        <Route element={<Navigate replace to="/" />} path="*" />
      </Routes>
    </Suspense>
  )
}

function StudioSplash() {
  return (
    <div className="splash-screen">
      <div className="splash-screen__orb splash-screen__orb--top" />
      <div className="splash-screen__orb splash-screen__orb--bottom" />
      <div className="splash-screen__content">
        <div className="splash-screen__mark">
          <span>E</span>
          <i>*</i>
        </div>
        <p className="eyebrow">Vennuzo</p>
        <h1>Experience events differently</h1>
        <p>Premium discovery, ticketing, and creator tools in one system.</p>
      </div>
    </div>
  )
}

function RequireSignedIn({ children }: { children: ReactElement }) {
  const session = usePortalSession()
  if (!session.user) {
    return <Navigate replace to="/" />
  }
  if (session.isAdmin) {
    return <Navigate replace to="/superadmin/approvals" />
  }
  return children
}

function RequireOrganizer({ children }: { children: ReactElement }) {
  const session = usePortalSession()
  if (!session.user) {
    return <Navigate replace to="/" />
  }
  if (session.isAdmin) {
    return <Navigate replace to="/superadmin/approvals" />
  }
  return children
}

function RequireAdmin({ children }: { children: ReactElement }) {
  const session = usePortalSession()
  if (!session.user) {
    return <Navigate replace to="/" />
  }
  if (!session.isAdmin) {
    return <Navigate replace to="/overview" />
  }
  return children
}

function App() {
  return (
    <PortalSessionProvider>
      <BrowserRouter>
        <AppRoutes />
      </BrowserRouter>
    </PortalSessionProvider>
  )
}

export default App
