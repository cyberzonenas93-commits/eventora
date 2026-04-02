import { Suspense, lazy, type ReactElement } from 'react'
import { BrowserRouter, Navigate, Outlet, Route, Routes } from 'react-router-dom'

import { ErrorBoundary } from './components/ErrorBoundary'
import { ThemeProvider } from './lib/ThemeContext'
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
const OrdersPage = lazy(() =>
  import('./pages/OrdersPage').then((module) => ({ default: module.OrdersPage })),
)
const ContactsPage = lazy(() =>
  import('./pages/ContactsPage').then((module) => ({ default: module.ContactsPage })),
)
const PaymentsPayoutsPage = lazy(() =>
  import('./pages/PaymentsPayoutsPage').then((module) => ({
    default: module.PaymentsPayoutsPage,
  })),
)
const PromotersPage = lazy(() =>
  import('./pages/PromotersPage').then((module) => ({ default: module.PromotersPage })),
)
const PromotePage = lazy(() =>
  import('./pages/PromotePage').then((module) => ({ default: module.PromotePage })),
)
const PortalLayout = lazy(() =>
  import('./components/PortalLayout').then((module) => ({ default: module.PortalLayout })),
)
const SuperadminLayout = lazy(() =>
  import('./components/SuperadminLayout').then((module) => ({ default: module.SuperadminLayout })),
)
const SuperadminApprovalsPage = lazy(() =>
  import('./pages/SuperadminApprovalsPage').then((module) => ({
    default: module.SuperadminApprovalsPage,
  })),
)
const SuperadminPricingPage = lazy(() =>
  import('./pages/SuperadminPricingPage').then((module) => ({ default: module.SuperadminPricingPage })),
)
const SuperadminCampaignsPage = lazy(() =>
  import('./pages/SuperadminCampaignsPage').then((module) => ({ default: module.SuperadminCampaignsPage })),
)
const SuperadminOptOutPage = lazy(() =>
  import('./pages/SuperadminOptOutPage').then((module) => ({ default: module.SuperadminOptOutPage })),
)
const UnsubscribePage = lazy(() =>
  import('./pages/UnsubscribePage').then((module) => ({ default: module.UnsubscribePage })),
)
const PublicLayout = lazy(() =>
  import('./components/PublicLayout').then((module) => ({ default: module.PublicLayout })),
)
const HomePage = lazy(() =>
  import('./pages/HomePage').then((module) => ({ default: module.HomePage })),
)
const PublicEventsPage = lazy(() =>
  import('./pages/PublicEventsPage').then((module) => ({ default: module.PublicEventsPage })),
)
const PublicEventDetailPage = lazy(() =>
  import('./pages/PublicEventDetailPage').then((module) => ({ default: module.PublicEventDetailPage })),
)
const CheckoutPage = lazy(() =>
  import('./pages/CheckoutPage').then((module) => ({ default: module.CheckoutPage })),
)
const CheckoutConfirmationPage = lazy(() =>
  import('./pages/CheckoutConfirmationPage').then((module) => ({
    default: module.CheckoutConfirmationPage,
  })),
)

function AppRoutes() {
  const session = usePortalSession()

  if (session.loading) {
    return <StudioSplash />
  }

  return (
    <ErrorBoundary>
      <Suspense fallback={<StudioSplash />}>
        <Routes>
        <Route element={<PublicLayout />} path="/">
          <Route index element={<HomePage />} />
          <Route element={<PublicEventsPage />} path="events" />
          <Route element={<PublicEventDetailPage />} path="events/:eventId" />
          <Route element={<CheckoutPage />} path="checkout/:eventId" />
          <Route element={<CheckoutConfirmationPage />} path="checkout/:orderId/confirmation" />
        </Route>
        <Route element={<UnsubscribePage />} path="/unsubscribe" />
        <Route path="/studio" element={session.user ? <Outlet /> : <LandingPage />}>
          <Route index element={<Navigate replace to="/studio/overview" />} />
          <Route
            element={
              <RequireSignedIn>
                <SetupPage />
              </RequireSignedIn>
            }
            path="setup/:step"
          />
          <Route element={<RequireOrganizer><PortalLayout /></RequireOrganizer>} path="">
            <Route index element={<Navigate replace to="/studio/overview" />} />
            <Route element={<OverviewPage />} path="overview" />
            <Route element={<OrdersPage />} path="orders" />
            <Route element={<EventsPage />} path="events" />
            <Route element={<EventEditorPage />} path="events/new" />
            <Route element={<EventEditorPage />} path="events/:eventId/edit" />
            <Route element={<ContactsPage />} path="contacts" />
            <Route element={<PaymentsPayoutsPage />} path="payments" />
            <Route element={<PromotersPage />} path="promoters" />
            <Route element={<PromotePage />} path="promote" />
            <Route element={<SettingsPage />} path="settings" />
          </Route>
        </Route>
        <Route
          element={
            <RequireSignedIn>
              <Navigate replace to="/studio/overview" />
            </RequireSignedIn>
          }
          path="/review"
        />
        <Route
          element={
            <RequireAdmin>
              <SuperadminLayout />
            </RequireAdmin>
          }
          path="/superadmin"
        >
          <Route index element={<Navigate replace to="/superadmin/approvals" />} />
          <Route element={<SuperadminApprovalsPage />} path="approvals" />
          <Route element={<SuperadminPricingPage />} path="pricing" />
          <Route element={<SuperadminCampaignsPage />} path="campaigns" />
          <Route element={<SuperadminOptOutPage />} path="optout" />
        </Route>
        <Route element={<Navigate replace to="/" />} path="*" />
        </Routes>
      </Suspense>
    </ErrorBoundary>
  )
}

function StudioSplash() {
  return (
    <div className="splash-screen">
      <div className="splash-screen__content">
        <img src="/logo-transparent.png" alt="Vennuzo" className="splash-screen__logo" />
        <p>Loading…</p>
      </div>
    </div>
  )
}

function RequireSignedIn({ children }: { children: ReactElement }) {
  const session = usePortalSession()
  if (!session.user) {
    return <Navigate replace to="/studio" />
  }
  if (session.isAdmin) {
    return <Navigate replace to="/superadmin" />
  }
  return children
}

function RequireOrganizer({ children }: { children: ReactElement }) {
  const session = usePortalSession()
  if (!session.user) {
    return <Navigate replace to="/studio" />
  }
  if (session.isAdmin) {
    return <Navigate replace to="/superadmin" />
  }
  return children
}

function RequireAdmin({ children }: { children: ReactElement }) {
  const session = usePortalSession()
  if (!session.user) {
    return <Navigate replace to="/studio" />
  }
  if (!session.isAdmin) {
    return <Navigate replace to="/studio/overview" />
  }
  return children
}

function App() {
  return (
    <ThemeProvider>
      <PortalSessionProvider>
        <BrowserRouter>
          <AppRoutes />
        </BrowserRouter>
      </PortalSessionProvider>
    </ThemeProvider>
  )
}

export default App
