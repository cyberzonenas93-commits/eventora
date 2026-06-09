import { Suspense, lazy, useEffect, type ComponentType, type ReactElement } from 'react'
import { BrowserRouter, Navigate, Outlet, Route, Routes, useLocation, useParams } from 'react-router-dom'

import { ErrorBoundary } from './components/ErrorBoundary'
import { ThemeProvider } from './lib/ThemeContext'
import type { AdminCollectionId } from './lib/adminConsole'
import { canPerformAdminAction, canReadAdminCollection, type AdminAction } from './lib/adminRoles'
import { identifyAnalyticsUser, trackPageView } from './lib/analytics'
import { PortalSessionProvider, usePortalSession } from './lib/portalSession'

// A new deploy invalidates the previous build's chunk hashes, so a still-open tab
// can hit a ChunkLoadError when it lazily imports a route. Retry the import once,
// then fall back to a hard reload to pull the fresh build.
// eslint-disable-next-line @typescript-eslint/no-explicit-any
function lazyWithRetry<T extends ComponentType<any>>(
  factory: () => Promise<{ default: T }>,
) {
  return lazy(() =>
    factory().catch((error) => {
      const isChunkError =
        error instanceof Error &&
        (error.name === 'ChunkLoadError' || /Loading chunk|dynamically imported module/i.test(error.message))
      if (!isChunkError) {
        throw error
      }
      return factory().catch(() => {
        window.location.reload()
        // Reload is async; return a never-resolving promise so React keeps the
        // Suspense fallback up until the page navigates away.
        return new Promise<{ default: T }>(() => {})
      })
    }),
  )
}

const LandingPage = lazyWithRetry(() =>
  import('./pages/LandingPage').then((module) => ({ default: module.LandingPage })),
)
const SetupPage = lazyWithRetry(() =>
  import('./pages/SetupPage').then((module) => ({ default: module.SetupPage })),
)
const OverviewPage = lazyWithRetry(() =>
  import('./pages/OverviewPage').then((module) => ({ default: module.OverviewPage })),
)
const EventsPage = lazyWithRetry(() =>
  import('./pages/EventsPage').then((module) => ({ default: module.EventsPage })),
)
const EventEditorPage = lazyWithRetry(() =>
  import('./pages/EventEditorPage').then((module) => ({
    default: module.EventEditorPage,
  })),
)
const SettingsPage = lazyWithRetry(() =>
  import('./pages/SettingsPage').then((module) => ({ default: module.SettingsPage })),
)
const OrdersPage = lazyWithRetry(() =>
  import('./pages/OrdersPage').then((module) => ({ default: module.OrdersPage })),
)
const ContactsPage = lazyWithRetry(() =>
  import('./pages/ContactsPage').then((module) => ({ default: module.ContactsPage })),
)
const PaymentsPayoutsPage = lazyWithRetry(() =>
  import('./pages/PaymentsPayoutsPage').then((module) => ({
    default: module.PaymentsPayoutsPage,
  })),
)
const PromotersPage = lazyWithRetry(() =>
  import('./pages/PromotersPage').then((module) => ({ default: module.PromotersPage })),
)
const TablesPage = lazyWithRetry(() =>
  import('./pages/TablesPage').then((module) => ({ default: module.TablesPage })),
)
const PlacesPage = lazyWithRetry(() =>
  import('./pages/PlacesPage').then((module) => ({ default: module.PlacesPage })),
)
const OperationsPage = lazyWithRetry(() =>
  import('./pages/OperationsPage').then((module) => ({ default: module.OperationsPage })),
)
const PromotePage = lazyWithRetry(() =>
  import('./pages/PromotePage').then((module) => ({ default: module.PromotePage })),
)
const CreativeServicesPage = lazyWithRetry(() =>
  import('./pages/CreativeServicesPage').then((module) => ({ default: module.CreativeServicesPage })),
)
const PortalLayout = lazyWithRetry(() =>
  import('./components/PortalLayout').then((module) => ({ default: module.PortalLayout })),
)
const SuperadminLayout = lazyWithRetry(() =>
  import('./components/SuperadminLayout').then((module) => ({ default: module.SuperadminLayout })),
)
const SuperadminApprovalsPage = lazyWithRetry(() =>
  import('./pages/SuperadminApprovalsPage').then((module) => ({
    default: module.SuperadminApprovalsPage,
  })),
)
const SuperadminPricingPage = lazyWithRetry(() =>
  import('./pages/SuperadminPricingPage').then((module) => ({ default: module.SuperadminPricingPage })),
)
const SuperadminCampaignsPage = lazyWithRetry(() =>
  import('./pages/SuperadminCampaignsPage').then((module) => ({ default: module.SuperadminCampaignsPage })),
)
const AdminSupportPage = lazyWithRetry(() =>
  import('./pages/AdminSupportPage').then((module) => ({ default: module.AdminSupportPage })),
)
const AdminAnalyticsPage = lazyWithRetry(() =>
  import('./pages/AdminAnalyticsPage').then((module) => ({ default: module.AdminAnalyticsPage })),
)
const SuperadminOptOutPage = lazyWithRetry(() =>
  import('./pages/SuperadminOptOutPage').then((module) => ({ default: module.SuperadminOptOutPage })),
)
const AdminDashboardPage = lazyWithRetry(() =>
  import('./pages/AdminDashboardPage').then((module) => ({ default: module.AdminDashboardPage })),
)
const AdminDataPage = lazyWithRetry(() =>
  import('./pages/AdminDataPage').then((module) => ({ default: module.AdminDataPage })),
)
const AdminModerationPage = lazyWithRetry(() =>
  import('./pages/AdminModerationPage').then((module) => ({ default: module.AdminModerationPage })),
)
const UnsubscribePage = lazyWithRetry(() =>
  import('./pages/UnsubscribePage').then((module) => ({ default: module.UnsubscribePage })),
)
const PublicLayout = lazyWithRetry(() =>
  import('./components/PublicLayout').then((module) => ({ default: module.PublicLayout })),
)
const HomePage = lazyWithRetry(() =>
  import('./pages/HomePage').then((module) => ({ default: module.HomePage })),
)
const PublicEventsPage = lazyWithRetry(() =>
  import('./pages/PublicEventsPage').then((module) => ({ default: module.PublicEventsPage })),
)
const PublicEventDetailPage = lazyWithRetry(() =>
  import('./pages/PublicEventDetailPage').then((module) => ({ default: module.PublicEventDetailPage })),
)
const CheckoutPage = lazyWithRetry(() =>
  import('./pages/CheckoutPage').then((module) => ({ default: module.CheckoutPage })),
)
const CheckoutConfirmationPage = lazyWithRetry(() =>
  import('./pages/CheckoutConfirmationPage').then((module) => ({
    default: module.CheckoutConfirmationPage,
  })),
)
const OrganizerFeedPage = lazyWithRetry(() =>
  import('./pages/OrganizerFeedPage').then((module) => ({ default: module.OrganizerFeedPage })),
)
const StaffModePage = lazyWithRetry(() =>
  import('./pages/StaffModePage').then((module) => ({ default: module.StaffModePage })),
)
const EventTeamPage = lazyWithRetry(() =>
  import('./pages/EventTeamPage').then((module) => ({ default: module.EventTeamPage })),
)
const HostAnalyticsPage = lazyWithRetry(() =>
  import('./pages/HostAnalyticsPage').then((module) => ({ default: module.HostAnalyticsPage })),
)
const TeamInviteAcceptPage = lazyWithRetry(() =>
  import('./pages/TeamInviteAcceptPage').then((module) => ({ default: module.TeamInviteAcceptPage })),
)

function AppRoutes() {
  const session = usePortalSession()
  const location = useLocation()
  const adminHost = isAdminHost()

  useEffect(() => {
    if (session.loading) return
    void identifyAnalyticsUser(
      session.user?.uid ?? null,
      {
        admin_role: session.adminRole || 'none',
        signed_in: Boolean(session.user),
      },
    )
    void trackPageView({
      organizationId: session.organizationId,
      path: location.pathname,
      role: session.adminRole || (session.user ? 'organizer' : 'guest'),
      title: document.title,
    })
  }, [
    location.pathname,
    session.adminRole,
    session.loading,
    session.organizationId,
    session.user,
  ])

  if (session.loading) {
    return <StudioSplash />
  }

  return (
    <ErrorBoundary>
      <Suspense fallback={<StudioSplash />}>
        <Routes>
        <Route element={<PublicLayout />} path="/">
          <Route index element={adminHost ? <Navigate replace to="/admin/overview" /> : <HomePage />} />
          <Route element={<PublicEventsPage />} path="events" />
          <Route element={<PublicEventDetailPage />} path="events/:eventId" />
          <Route element={<CheckoutPage />} path="checkout/:eventId" />
          <Route element={<CheckoutConfirmationPage />} path="checkout/:orderId/confirmation" />
          <Route element={<CheckoutConfirmationPage />} path="tickets/:orderId" />
          <Route element={<OrganizerFeedPage />} path="organizer-feed/:shareId" />
        </Route>
        <Route element={<UnsubscribePage />} path="/unsubscribe" />
        <Route element={<TeamInviteAcceptPage />} path="/invite/:inviteId" />
        <Route element={<StaffModePage />} path="/staff" />
        <Route element={<StaffModePage />} path="/staff/:eventId" />
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
            <Route element={<HostAnalyticsPage />} path="analytics" />
            <Route element={<PaymentsPayoutsPage />} path="payments" />
            <Route element={<PromotersPage />} path="promoters" />
            <Route element={<TablesPage />} path="tables" />
            <Route element={<PlacesPage />} path="places" />
            <Route element={<OperationsPage />} path="operations" />
            <Route element={<EventTeamPage />} path="team" />
            <Route element={<PromotePage />} path="promote" />
            <Route element={<CreativeServicesPage />} path="creative" />
            <Route element={<Navigate replace to="/studio/payments" />} path="billing" />
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
        <Route element={<AdminRoutesGate />} path="/admin">
          <Route index element={<Navigate replace to="/admin/overview" />} />
          <Route element={<AdminDashboardPage />} path="overview" />
          <Route
            element={
              <RequireAdminPermission action="read_analytics">
                <AdminAnalyticsPage />
              </RequireAdminPermission>
            }
            path="analytics"
          />
          <Route
            element={
              <RequireAdminPermission action="review_organizers">
                <SuperadminApprovalsPage />
              </RequireAdminPermission>
            }
            path="approvals"
          />
          <Route
            element={
              <RequireAdminPermission action="read_pricing">
                <SuperadminPricingPage />
              </RequireAdminPermission>
            }
            path="pricing"
          />
          <Route
            element={
              <RequireAdminPermission action="read_campaigns">
                <SuperadminCampaignsPage />
              </RequireAdminPermission>
            }
            path="campaigns"
          />
          <Route
            element={
              <RequireAdminPermission action="manage_support">
                <AdminSupportPage />
              </RequireAdminPermission>
            }
            path="support"
          />
          <Route
            element={
              <RequireAdminPermission collectionId="event_reports">
                <AdminModerationPage />
              </RequireAdminPermission>
            }
            path="moderation"
          />
          <Route
            element={
              <RequireAdminPermission action="record_sms_opt_out">
                <SuperadminOptOutPage />
              </RequireAdminPermission>
            }
            path="optout"
          />
          <Route
            element={
              <RequireAdminPermission collectionId="app_config">
                <Navigate replace to="/admin/data/app_config" />
              </RequireAdminPermission>
            }
            path="settings"
          />
          <Route
            element={
              <RequireAdminPermission collectionId="users">
                <Navigate replace to="/admin/data/users" />
              </RequireAdminPermission>
            }
            path="data"
          />
          <Route element={<AdminDataPage />} path="data/:collectionId" />
        </Route>
        <Route element={<Navigate replace to="/admin/approvals" />} path="/superadmin" />
        <Route element={<LegacySuperadminRedirect />} path="/superadmin/:section" />
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

// Both guards share identical logic: require a signed-in session and bounce
// admins (who aren't studio testers) to the admin console. Kept as two named
// exports so existing call sites/routes read clearly, but the implementation
// lives in one place to avoid drift.
function RequireSignedIn({ children }: { children: ReactElement }) {
  const session = usePortalSession()
  if (!session.user) {
    return <Navigate replace to="/studio" />
  }
  if (session.isAdmin && !isStudioTester(session.user.email)) {
    return <Navigate replace to="/admin/overview" />
  }
  return children
}

const RequireOrganizer = RequireSignedIn

function AdminRoutesGate() {
  const session = usePortalSession()
  if (!session.user) {
    return <LandingPage />
  }
  if (!session.isAdmin) {
    return <AdminAccessDenied />
  }
  return <SuperadminLayout />
}

function RequireAdminPermission({
  action,
  children,
  collectionId,
}: {
  action?: AdminAction
  children: ReactElement
  collectionId?: AdminCollectionId
}) {
  const session = usePortalSession()
  const actionAllowed = action ? canPerformAdminAction(session.adminRole, action) : true
  const collectionAllowed = collectionId ? canReadAdminCollection(session.adminRole, collectionId) : true

  if (!actionAllowed || !collectionAllowed) {
    return <AdminPermissionDenied />
  }

  return children
}

function AdminAccessDenied() {
  const session = usePortalSession()
  return (
    <main className="landing-page landing-page--admin-denied">
      <section className="auth-panel auth-panel--centered">
        <div className="studio-brand">
          <div className="studio-brand__mark" aria-hidden>
            <img src="/logo-mark.png" alt="" />
          </div>
          <div>
            <strong>Vennuzo Admin</strong>
            <span>Platform console</span>
          </div>
        </div>
        <div className="auth-panel__header">
          <p className="eyebrow">Access restricted</p>
          <h2>This account is not an admin.</h2>
        </div>
        <p className="text-subtle">
          Sign in with an account listed in the Vennuzo admin directory.
        </p>
        <button className="button button--secondary" onClick={() => void session.signOut()} type="button">
          Sign out
        </button>
      </section>
    </main>
  )
}

function AdminPermissionDenied() {
  return (
    <div className="page-loader">
      <p>This admin role cannot use that area.</p>
      <p className="text-subtle">Choose another work area from the admin sidebar.</p>
    </div>
  )
}

function LegacySuperadminRedirect() {
  const params = useParams()
  return <Navigate replace to={`/admin/${params.section ?? 'approvals'}`} />
}

function isAdminHost() {
  if (typeof window === 'undefined') {
    return false
  }
  const hostname = window.location.hostname.toLowerCase()
  return hostname === 'admin.vennuzo.com' || hostname.startsWith('admin.') || hostname.includes('vennuzo-admin')
}

function isStudioTester(email?: string | null) {
  return email?.trim().toLowerCase() === 'angelonartey@hotmail.com'
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
