import type { ReactElement } from 'react'
import { BrowserRouter, Navigate, Route, Routes } from 'react-router-dom'

import { PortalLayout } from './components/PortalLayout'
import { PortalSessionProvider, usePortalSession } from './lib/portalSession'
import { EventEditorPage } from './pages/EventEditorPage'
import { EventsPage } from './pages/EventsPage'
import { LandingPage } from './pages/LandingPage'
import { OverviewPage } from './pages/OverviewPage'
import { ReviewStatusPage } from './pages/ReviewStatusPage'
import { SettingsPage } from './pages/SettingsPage'
import { SetupPage } from './pages/SetupPage'

function AppRoutes() {
  const session = usePortalSession()

  if (session.loading) {
    return <div className="page-loader">Loading Eventora Studio...</div>
  }

  return (
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
            <ReviewStatusPage />
          </RequireSignedIn>
        }
        path="/review"
      />
      <Route
        element={
          <RequireApproved>
            <PortalLayout />
          </RequireApproved>
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
  )
}

function RequireSignedIn({ children }: { children: ReactElement }) {
  const session = usePortalSession()
  if (!session.user) {
    return <Navigate replace to="/" />
  }
  return children
}

function RequireApproved({ children }: { children: ReactElement }) {
  const session = usePortalSession()
  if (!session.user) {
    return <Navigate replace to="/" />
  }
  if (session.status !== 'approved') {
    if (session.status === 'submitted' || session.status === 'under_review') {
      return <Navigate replace to="/review" />
    }
    return <Navigate replace to="/setup/account" />
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
