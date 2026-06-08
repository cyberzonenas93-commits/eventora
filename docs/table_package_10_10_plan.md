# Vennuzo Table Package 10/10 Plan

Date: 2026-06-03

This document locks in the target direction for turning Vennuzo table packages
from a basic event add-on into a full event table revenue and operations
engine. The goal is not to copy GPlus exactly. The goal is to combine the best
of GPlus table operations with Vennuzo's event commerce, CRM, AI creative
services, promotions, and organizer Studio.

## Product Target

Vennuzo should let organizers create, market, sell, operate, and analyze event
table packages from one place.

A 10/10 table package system should support:

- Beautiful table package creation and editing.
- Optional real table inventory behind packages.
- Sections or zones such as VIP, Terrace, Front Row, Backstage, Balcony.
- Public event page table package sales.
- Deposit, full payment, comp, and pay-at-event modes.
- Checkout inventory holds to prevent overselling.
- Hubtel checkout, callback, return, and status reconciliation.
- Customer booking confirmation with QR and shareable receipt.
- Organizer check-in, seating, cancellation, refund, no-show, and completion
  actions.
- CRM-powered table upsell campaigns.
- AI flyer generation, minor edits, and Instagram story/post downloads for
  table packages.
- Analytics for revenue, conversion, availability, abandoned checkout, and top
  table buyers.
- Optional staff day-of-event tools.

## Current Vennuzo Baseline

Vennuzo currently supports an event-scoped table package commerce flow:

- Studio creates packages with name, description, included items, price,
  capacity, and quantity.
- Public event pages list active table packages.
- Buyers select a package, enter details, choose quantity, and pay through
  Hubtel when the package has a price.
- Successful paid callback confirms the booking and increments package booked
  count.

This is a good foundation for selling packages, but it is not yet a full table
operations product.

## GPlus Comparison

GPlus has a deeper venue/table operations model:

- Actual table inventory through `tables`.
- Sections, VIP labels, capacity, deposits, amenities, and floor-plan
  positions.
- Date and time availability checks.
- Deposit checkout through Hubtel.
- Booking statuses: pending, confirmed, seated, completed, cancelled, no-show.
- Arrival and seating actions.
- Bill splitting and pre-orders.
- Admin table management and floor-plan views.

GPlus is conceptually richer, but parts are unfinished and rough. For example,
its public table routes are commented as not ready, and its Hubtel booking
callback references an undefined `depositStatus` variable. Vennuzo should use
the product ideas, not copy implementation bugs or single-venue assumptions.

## Locked Product Direction

The Vennuzo version should be a hybrid:

| Layer | Purpose |
| --- | --- |
| `tablePackages` | Sellable bundles such as Gold Table, Birthday Table, or Bottle Service Table. |
| `tableSections` | Event or venue zones such as VIP, Terrace, Main Floor, Balcony. |
| `tables` | Optional real table inventory with capacity, amenities, status, and floor-plan position. |
| `tablePackageBookings` | Customer reservation and purchase record. |
| `tableHolds` | Temporary checkout holds that reserve inventory while payment is pending. |
| `tableAssignments` | Manual or automatic assignment of bookings to actual table(s). |
| `tableBookingEvents` | Audit/lifecycle history for paid, checked in, seated, cancelled, refunded, and no-show events. |

Packages should remain the buyer-facing product. Real tables should be optional
underneath, because many Vennuzo organizers sell experiences or zones rather
than numbered tables.

## Required UX Surfaces

### Organizer Studio

Studio should become the table command center:

- Packages tab.
- Bookings tab.
- Holds and pending payments tab.
- Floor plan or zones tab.
- Analytics tab.
- Package create/edit/archive.
- Manual booking creation.
- Assign or reassign table.
- Confirm, check in, seat, complete, cancel, no-show, refund actions.
- CRM campaign launch from table buyer segments.
- Direct AI flyer generation from a table package.

### Public Event Page

The public event table section should move from a dropdown to a premium sales
experience:

- Visual package cards.
- Included items.
- Capacity.
- Price, deposit, or full-payment label.
- Availability count such as "2 left".
- Add-ons.
- Buyer details.
- Checkout hold timer.
- Clear success/failure state after Hubtel return.
- QR booking receipt.

### Customer App

The app should support:

- My table bookings.
- Booking detail with QR.
- Share booking.
- Cancel request where allowed.
- Add guests or notes where allowed.
- Optional pre-order/add-on purchase.

### Staff/Event Operations

Day-of-event tools should support:

- QR scan/check-in.
- Host list.
- Table assignment.
- Arrived, seated, completed, no-show status.
- Guest notes.
- Optional open-tab or pre-order handoff later.

## Data Model Direction

### `tablePackages`

Recommended fields:

- `organizationId`
- `eventId`
- `name`
- `description`
- `items`
- `structuredItems`
- `priceGhs`
- `depositGhs`
- `paymentMode`: `full`, `deposit`, `free`, `pay_at_event`, `comp`
- `capacity`
- `quantity`
- `booked`
- `held`
- `status`: `draft`, `active`, `archived`, `sold_out`
- `visibility`: `public`, `private_link`, `admin_only`
- `sectionIds`
- `tableIds`
- `saleStartsAt`
- `saleEndsAt`
- `media`
- `createdAt`
- `updatedAt`

### `tableHolds`

Recommended fields:

- `organizationId`
- `eventId`
- `tablePackageId`
- `tableIds`
- `quantity`
- `buyerName`
- `buyerPhone`
- `buyerEmail`
- `status`: `active`, `confirmed`, `expired`, `released`
- `expiresAt`
- `checkoutId`
- `clientReference`
- `createdAt`
- `updatedAt`

### `tablePackageBookings`

Recommended fields:

- `organizationId`
- `eventId`
- `tablePackageId`
- `holdId`
- `buyerName`
- `buyerPhone`
- `buyerEmail`
- `guestCount`
- `quantity`
- `totalAmount`
- `depositAmount`
- `balanceDue`
- `currency`
- `status`: `pending_payment`, `confirmed`, `checked_in`, `seated`,
  `completed`, `cancelled`, `no_show`, `refunded`
- `paymentStatus`: `pending`, `paid`, `failed`, `cancelled`, `refunded`
- `paymentProvider`
- `paymentReference`
- `assignedTableIds`
- `qrToken`
- `specialRequests`
- `crmContactId`
- `source`
- `createdAt`
- `updatedAt`

### `tableBookingEvents`

Recommended fields:

- `organizationId`
- `eventId`
- `bookingId`
- `actorId`
- `actorType`
- `type`
- `fromStatus`
- `toStatus`
- `note`
- `createdAt`

## Critical Engineering Requirements

### Prevent Overselling

Vennuzo should not rely only on `booked` after payment. When a buyer starts
checkout, the system should create a short-lived hold and increment held
inventory transactionally.

Recommended hold window: 10 to 15 minutes.

On payment success:

- Mark hold confirmed.
- Mark booking confirmed.
- Decrement held.
- Increment booked.

On payment failure or expiry:

- Mark hold released or expired.
- Decrement held.
- Keep booking failed/expired or remove draft booking depending on audit needs.

### Keep Server Authority

All booking creation, hold creation, package inventory updates, payment
callbacks, status transitions, QR validation, and refund-sensitive actions must
be server-side callables or HTTP functions with organization/event role checks.

### Multi-Organizer Safety

Every table record must be tenant scoped with `organizationId`. GPlus is
single-venue in many places; Vennuzo must remain multi-organizer and
multi-event.

## Event Inventory And Waiter Operations

The table package system should connect to a broader event inventory and order
operations module. The product idea: when an organizer creates an event, they
can optionally activate "Event Inventory & Bar Ops". They then create all
sellable and stock-tracked items for that event: bottles, food, merch, shisha,
add-ons, table package inclusions, and service items.

This turns Vennuzo into a temporary event POS and inventory system, not just an
event ticketing app.

### GPlus Waiter And Open Tab Findings

GPlus has a useful waiter/order pattern:

- `inventory` stores stock items with quantity, unit, category, low-stock
  behavior, and unit cost.
- `menu_items` are the customer/waiter-facing sellable items. They can link to
  one or more inventory items through `linkedInventoryItems`, essentially a
  recipe.
- `take_order_screen.dart` lets staff choose a table, section, customer name,
  menu items, discount/tip, and optional sales-credit waiter.
- When an order is placed, GPlus checks stock, creates or merges into one open
  `orders` document per table, writes a mirrored `bar_orders` document, deducts
  linked inventory, and emits an `order_updates` document for push
  notifications.
- `open_tabs_screen.dart` shows open tabs grouped by waiter and table. Waiters
  see only assigned tables/sections; managers and owners see all.
- Closing a tab supports cash and Hubtel payment. Hubtel payment marks the tab
  as paid, but staff still manually close the tab after service/payment
  reconciliation.
- Reports include bar totals, payment method breakdown, category/item sales,
  waiter sales, raw sales versus gross sales, service charge, tax, tips, and
  date/time filters.

GPlus' product flow is strong, but Vennuzo should not copy the implementation
one-to-one. Much of GPlus writes directly from the app into Firestore and is
single-venue. Vennuzo should make all money, inventory, order, payment, and
role actions server-authoritative and tenant scoped.

### Vennuzo Product Model

An organizer should be able to enable this service per event:

1. Create event inventory.
2. Create sellable catalog items and table package inclusions from inventory.
3. Publish selected items to the event hub for customer pre-purchase.
4. Let customers pre-order or buy add-ons through Hubtel.
5. Invite waiters, bartenders, cashiers, managers, and owners into a special
   event staff app experience.
6. Let waiters punch in, receive order assignments, place orders, and manage
   tabs during the event.
7. Notify bartenders, admins, owners, or managers when orders are placed or
   paid.
8. Produce event-level bar, stock, waiter, and financial reports.

### Event Inventory Data Model

Recommended collections:

| Collection | Purpose |
| --- | --- |
| `event_inventory_items` | Stock-tracked event inventory: bottles, cups, food stock, merch, shisha, wristbands. |
| `event_catalog_items` | Sellable items on the event hub or staff POS. |
| `event_inventory_movements` | Audit ledger for stock in, sold, reserved, wasted, comped, returned, adjusted. |
| `event_orders` | Customer pre-orders, waiter orders, bar orders, table add-ons, and open tabs. |
| `event_order_events` | Order lifecycle and audit log. |
| `event_staff_members` | Organizer-created staff identities, roles, permissions, event access. |
| `event_staff_sessions` | Clock-in/clock-out, device, location, and shift state. |
| `event_staff_assignments` | Waiter-to-section/table/bar-station assignments. |
| `event_payment_sessions` | Hubtel checkout sessions for inventory/order payments. |

### `event_inventory_items`

Recommended fields:

- `organizationId`
- `eventId`
- `name`
- `category`
- `unit`
- `quantityOnHand`
- `quantityReserved`
- `quantitySold`
- `quantityWasted`
- `costPriceGhs`
- `supplierName`
- `lowStockThreshold`
- `trackStock`
- `reusable`
- `status`: `active`, `hidden`, `archived`
- `createdAt`
- `updatedAt`

### `event_catalog_items`

Recommended fields:

- `organizationId`
- `eventId`
- `name`
- `description`
- `category`
- `imageUrl`
- `sellingPriceGhs`
- `costPriceSnapshotGhs`
- `availableForPublicPreorder`
- `availableForWaiterOrder`
- `availableForTablePackage`
- `availableForAddOn`
- `linkedInventoryItems`: list of `{ inventoryItemId, quantityPerUnit }`
- `taxable`
- `serviceChargeEligible`
- `status`: `draft`, `active`, `sold_out`, `archived`
- `createdAt`
- `updatedAt`

### `event_orders`

Recommended fields:

- `organizationId`
- `eventId`
- `source`: `public_event_hub`, `waiter_app`, `admin_studio`, `table_package`,
  `customer_app`
- `orderType`: `preorder`, `open_tab`, `table_addon`, `walkup`, `comp`
- `customerName`
- `customerPhone`
- `customerEmail`
- `buyerUserId`
- `tablePackageBookingId`
- `assignedTableIds`
- `sectionId`
- `waiterId`
- `waiterName`
- `createdByStaffId`
- `items`
- `subtotalGhs`
- `discountGhs`
- `serviceChargeGhs`
- `taxGhs`
- `tipGhs`
- `totalGhs`
- `cogsGhs`
- `grossMarginGhs`
- `paymentStatus`: `unpaid`, `pending`, `paid`, `failed`, `refunded`
- `paymentMethod`: `hubtel`, `cash`, `comp`, `mixed`
- `fulfillmentStatus`: `new`, `accepted`, `preparing`, `ready`, `served`,
  `closed`, `voided`, `cancelled`
- `hubtelReference`
- `qrToken`
- `createdAt`
- `updatedAt`

### `event_staff_members`

Recommended fields:

- `organizationId`
- `eventId`
- `displayName`
- `phone`
- `email`
- `role`: `waiter`, `bartender`, `cashier`, `manager`, `owner`, `runner`,
  `inventory_manager`, or organizer-defined role.
- `permissions`
- `credentialType`: `pin`, `magic_link`, `phone_otp`, `email_password`,
  `temporary_password`
- `credentialStatus`: `active`, `expired`, `revoked`
- `linkedAuthUid`
- `allowedDeviceIds`
- `mustClockIn`
- `status`
- `createdAt`
- `updatedAt`

### Special Staff App Experience

When a waiter or staff member logs in with event staff credentials, the app
should route them into a different staff shell:

- No attendee social/discovery app.
- No organizer business settings unless permitted.
- Only event-specific tools for the active event.
- Role-based home screen.

This should feel like a second app, even if it initially runs inside the same
Vennuzo mobile app. The staff member should not see the normal attendee feed,
event discovery, organizer setup, creative services, or public marketplace
surfaces. They should enter a focused operational workspace for the event.

Presentation options:

| Option | Recommendation | Notes |
| --- | --- | --- |
| Same app, separate staff shell | Phase 1 recommendation | Fastest to build. Staff log in with event credentials and see a different app experience. |
| Separate branded staff app | Later option | Useful if organizers want a dedicated "Vennuzo Staff" app on devices. More App Store and maintenance overhead. |
| Web/PWA staff console | Useful add-on | Good for tablets, cashier desks, and bars without app installs. |

The first version should be same app, separate shell. It gives the effect of a
second app without forcing staff to install a different product.

### Staff App UI/UX

The staff shell should be designed for speed, clarity, and low cognitive load.
Staff may be working in a noisy venue, under pressure, with one hand, and with
limited time.

Design principles:

- Big tap targets.
- High contrast.
- Minimal text.
- Fast search.
- Persistent event and role context.
- Clear order status colors.
- No decorative clutter.
- Offline-aware states.
- One primary action per screen.
- Bottom navigation for the most common role actions.

Default staff app navigation:

| Tab | Purpose |
| --- | --- |
| Home | Role-specific dashboard and next actions. |
| Orders | Incoming/new/preparing/ready orders. |
| Tabs | Open and closed tabs for assigned tables/sections. |
| Sell | Take order or add items to a tab. |
| Reports | My sales, shift totals, or manager reports depending on role. |

Role-specific home screens:

| Role | Home Screen |
| --- | --- |
| Waiter | Clock status, assigned tables, open tabs, take order, my sales. |
| Bartender | New orders, preparing queue, ready-to-serve queue, low-stock alerts. |
| Cashier | Payment/close-tab queue, closed tabs, merchant-collected declarations. |
| Manager | Live event overview, staff online, open tabs, void/discount approvals, alerts. |
| Owner | Revenue snapshot, staff sales, inventory risk, end-of-event report. |
| Inventory manager | Stock levels, adjustments, low-stock items, wastage/refills. |

Waiter UX:

- Login with temporary credential or staff PIN/OTP.
- Choose active event if assigned to more than one.
- Clock in if required.
- See assigned section/tables.
- Tap "Take Order".
- Select table/section/customer.
- Add catalog items quickly.
- Submit order.
- See order added to open tab.
- Close tab only after customer has paid.
- View "My Sales" breakdown.

Bartender UX:

- See incoming order queue.
- Filter by station/category.
- Tap order to view items.
- Mark accepted, preparing, ready, served.
- Toggle item availability if permitted.
- Receive low-stock warnings.

Manager/Owner UX:

- See live event operations dashboard.
- Staff currently clocked in.
- Orders by status.
- Open tabs count and value.
- Closed tabs count and value.
- Staff sales leaderboard.
- Low-stock alerts.
- Void/discount approvals.
- Generate end-of-event PDF.

Visual style:

- Operational and premium, not social.
- Dark or high-contrast base for event environments.
- Status colors:
  - New: blue.
  - Preparing: amber.
  - Ready: green.
  - Paid: teal.
  - Needs attention: red.
  - Closed: neutral.
- Use icons heavily for speed: order, table, staff, money, report, inventory.
- Keep cards dense and scannable.

The staff app should feel like a command center in the user's pocket: fewer
features, faster actions, and zero ambiguity about what needs attention next.

Recommended role dashboards:

| Role | Default App Surface |
| --- | --- |
| Waiter | Take order, my open tabs, assigned tables/sections, my sales, clock in/out. |
| Bartender | Incoming orders, preparing/ready controls, inventory alerts, item availability toggles. |
| Cashier | Payment collection, Hubtel/cash reconciliation, close tabs, receipts. |
| Manager | All orders, waiter assignments, void/discount approval, staff sessions, reports. |
| Owner | Financial reports, inventory value, profit/loss, payouts, audit logs. |
| Inventory manager | Stock setup, stock adjustments, wastage, refills, low-stock report. |

Organizers should be able to create custom roles by selecting permissions:

- `inventory.read`
- `inventory.write`
- `catalog.write`
- `orders.create`
- `orders.view_assigned`
- `orders.view_all`
- `orders.accept`
- `orders.prepare`
- `orders.serve`
- `orders.close`
- `orders.void`
- `payments.initiate`
- `payments.confirm_cash`
- `discounts.apply`
- `reports.view_sales`
- `reports.view_profit`
- `staff.manage`
- `staff.assign_tables`

### Staff Punch-In Flow

For events using this service:

- Staff must clock in before taking orders if `mustClockIn` is enabled.
- Clock-in records staff ID, event ID, time, device, and optional location.
- Clock-out ends the session and locks order-taking for that staff member.
- Managers see live clocked-in staff and late/no-show state.
- Reports can filter sales by clocked-in session.

### Public Event Hub Sales

Inventory items can be listed on the event hub in three ways:

- Pre-purchase before the event: merch, bottle package, food voucher,
  table add-on, fast-track add-on.
- Order for pickup/service during event: customer pays first, staff fulfills.
- Table package bundle: included inventory is reserved/deducted when table
  package payment is confirmed or when the table is checked in.

The public checkout should use Hubtel and follow the same hold pattern as table
packages:

1. Customer selects items.
2. Server creates an order hold and reserves stock.
3. Hubtel checkout starts.
4. Callback confirms payment, converts hold to paid order, and notifies staff.
5. Failed/expired payment releases stock.

### Waiter Open Tab Flow

The Vennuzo waiter flow should support:

1. Waiter clocks in.
2. Waiter selects event, table/section, customer, and catalog items.
3. Server creates a new open tab or appends to the existing open tab for that
   table/customer.
4. Server checks and reserves/deducts stock transactionally.
5. Bartender/manager receives push notification.
6. Bartender accepts/prepares/marks ready.
7. Waiter serves and can add more items.
8. Customer pays through Hubtel, cash, comp, or split/mixed payment.
9. Staff closes tab.
10. Reports update.

For table-package bookings, the table booking can automatically create or link
an open tab so add-ons and extra bottles attach to the original VIP table.

### Payment And Hubtel Flow

Recommended payment modes:

- Public pre-order Hubtel checkout.
- Waiter-initiated Hubtel checkout link.
- Cash recorded by cashier/manager.
- Comp/discount requiring approval permission.
- Split payment later if needed.

### How Waiters Take Money From Customers

Waiters should be able to collect payment in controlled ways, depending on the
organizer's event settings and staff permissions.

Recommended collection options:

| Method | Flow | Control |
| --- | --- | --- |
| Merchant-collected payment | Vendor/merchant collects money outside Vennuzo through their own MoMo, POS, cash, bank transfer, QR, or existing process. Staff marks the tab closed with the payment method and reference/note. | Vennuzo records the closed tab, inventory movement, revenue declaration, staff attribution, and reconciliation state, but does not custody the funds. |
| Hubtel checkout link | Waiter opens a tab/order and taps "Collect Payment". Vennuzo creates a Hubtel checkout session and shows a QR/link or sends SMS/WhatsApp-style link to the customer. | Payment is only confirmed by Hubtel callback. |
| Customer QR checkout | Waiter shows a payment QR on the staff app. Customer scans and pays from their phone. | Payment is tied to the order ID and callback. |
| Cash to cashier | Waiter marks "Cash requested" or sends customer to cashier. Cashier/manager confirms cash received and closes the order. | Waiter cannot self-confirm unless given permission. |
| Cash collected by waiter | Waiter records cash collected, but the order enters `cash_pending_reconciliation` until cashier/manager cashes out the waiter. | Useful for mobile event setups where waiters carry cash. |
| Split/mixed payment | Part Hubtel, part cash, or multiple customer shares. | Each payment part is logged separately. |
| Comp/discount | Requires manager/owner approval or configured permission. | Creates audit trail. |

The default for vendor/merchant events should be merchant-collected payment:

- Vennuzo records what was sold.
- Vennuzo deducts or reserves inventory.
- Vennuzo records who served it.
- The merchant collects money their own way.
- Staff closes the tab with `paymentCollectionMode: merchant_collected`.
- Reports clearly label the money as declared merchant-collected revenue, not
  Vennuzo-processed money.

For organizers who want Vennuzo payment control, enable Hubtel/cash
reconciliation as an optional stricter mode:

- Waiters can initiate Hubtel payment.
- Waiters can record cash collected.
- Managers/cashiers/owners confirm cash reconciliation.
- Orders paid by Hubtel are marked `paid` automatically by callback.
- Orders paid in cash are marked `cash_pending_reconciliation` until confirmed.

Vennuzo-controlled mode should be gated behind a Coming Soon screen until the
full payment custody/reconciliation workflow is ready. The available default
mode should be merchant-collected payments. In setup screens, organizers can see
the Vennuzo-controlled option, but selecting it should open a Coming Soon state
instead of enabling Hubtel/cash reconciliation.

Coming Soon copy:

- Title: "Vennuzo-controlled payments are coming soon"
- Body: "For now, vendors can collect money through their own MoMo, POS, cash,
  transfer, or payment process while Vennuzo records orders, inventory, closed
  tabs, and reports."
- Primary action: "Use merchant-collected mode"
- Secondary action: "Join waitlist" or "Notify me"

Suggested merchant-collected flow:

1. Waiter creates or opens an order.
2. Vendor/merchant collects payment using their own method.
3. Once the order has been paid for, waiter or cashier taps "Close Tab".
4. Staff selects payment method: merchant MoMo, merchant POS, cash, bank
   transfer, complimentary, other.
5. Staff enters optional external reference or note.
6. Vennuzo closes the tab, records inventory movement, records declared revenue,
   and updates reports.
7. Owner/manager can later review, dispute, or reconcile closed tabs.

The core rule: an order stays open until staff intentionally closes the tab.
Payment can happen outside Vennuzo, through Hubtel, or through cash/POS, but
closing the tab is the action that finalizes the sale operationally inside
Vennuzo.

Suggested cash flow:

1. Waiter creates or opens an order.
2. Customer pays cash to waiter.
3. Waiter records amount collected.
4. Order status becomes `cash_pending_reconciliation`.
5. At cash-out, cashier/manager counts waiter cash.
6. Cashier confirms the cash collected for each waiter/session.
7. Orders become `paid` or `closed`.
8. Any shortage/overage is logged against the staff session.

Suggested Hubtel flow:

1. Waiter creates or opens an order.
2. Waiter taps "Collect Payment".
3. Vennuzo creates `event_payment_sessions/{paymentSessionId}` with
   `clientReference`.
4. Customer pays via Hubtel checkout link or QR.
5. Hubtel callback marks the payment session paid.
6. Vennuzo marks the order paid and notifies waiter/cashier/owner.
7. Staff clicks "Close Tab" after confirming the customer has paid and service
   is complete.

Important payment records:

- `event_order_payments`: individual payments for an order.
- `event_payment_sessions`: Hubtel checkout sessions.
- `event_cash_collections`: cash declared by waiter/session.
- `event_cash_reconciliations`: cashier/manager cash-out verification.
- `event_merchant_payment_declarations`: merchant-collected payment records and
  external references.

Recommended payment statuses:

- `unpaid`
- `payment_requested`
- `pending_hubtel`
- `paid`
- `merchant_collected`
- `cash_pending_reconciliation`
- `partially_paid`
- `failed`
- `refunded`
- `voided`

This model lets waiters and vendors move quickly while still protecting the
organizer's inventory, tab history, staff attribution, and reports. Vennuzo can
support both lightweight merchant-collected payments and stricter Vennuzo
Hubtel/cash reconciliation for organizers who want it.

Hubtel callback should:

- Verify callback signature when configured.
- Write an idempotent payment event.
- Mark `event_orders.paymentStatus` paid/failed/refunded.
- Keep open-tab orders open until staff closes them.
- Notify waiter, cashier, bartender, manager, and owner depending on role
  notification settings.
- Add customer to CRM/audience when consent permits.

### Push Notifications

Recommended notification events:

- New public pre-order paid.
- New waiter order placed.
- Items appended to a table tab.
- Order accepted/preparing/ready.
- Payment initiated.
- Payment successful.
- Payment failed.
- Tab closed.
- Low stock threshold crossed.
- Stock adjustment/wastage created.
- Discount/void requested.
- Staff clocked in/out.

Each event should route to roles, not hardcoded user IDs.

Examples:

- Waiter places order -> bartender, manager, owner.
- Hubtel payment succeeds -> waiter who initiated payment, cashier, owner.
- Low stock -> inventory manager, manager, owner.
- Void/discount request -> manager/owner.

### Reports And Analytics

Event organizers should get:

- Event bar revenue.
- Gross collected.
- Core item revenue.
- Cost of goods sold.
- Gross margin.
- Profit by category.
- Profit by item.
- Stock remaining and stock value.
- Wastage and comps.
- Sales by waiter.
- Sales by table/section.
- Sales by hour.
- Payment method breakdown.
- Open tabs outstanding.
- Pre-orders awaiting fulfillment.
- Table package add-on revenue.
- Hubtel/cash reconciliation.
- Staff clock-in and productivity report.
- Sales breakdown for each staff member.
- End-of-event PDF report generator.

Cost price should be visible only to owner/manager roles with permission.

### Staff Sales Breakdown

Organizers should be able to view sales by staff member for each event. This is
especially important for waiter accountability, commission, bonuses, and
end-of-event reconciliation.

Each staff report should show:

- Staff name.
- Role.
- Clock-in/clock-out window.
- Assigned tables/sections.
- Orders created.
- Orders served.
- Open tabs.
- Closed tabs.
- Voided/cancelled orders.
- Items sold.
- Sales by item.
- Sales by category.
- Gross declared sales.
- Discounts/comps.
- Tips.
- Service charge.
- Tax.
- Net item revenue.
- Cost of goods sold, if permitted.
- Gross margin, if permitted.
- Merchant-collected payment breakdown.
- Cash declared.
- Hubtel/Vennuzo-controlled payments, if enabled later.
- Shortage/overage, if cash reconciliation is enabled.

Breakdown dimensions:

- By staff member.
- By role.
- By table.
- By section.
- By hour/time slot.
- By payment method.
- By catalog category.
- By inventory item.

Attribution rules:

- `createdByStaffId` records who entered the order.
- `waiterId` records who receives waiter credit.
- `servedByStaffId` records who fulfilled/served the order.
- `closedByStaffId` records who closed the tab.
- Line items should also support `creditedStaffId` so a single tab can credit
  different staff members for different additions.

This prevents a common reporting problem where one staff member opens the tab,
another adds bottles, and another closes it. The report should be able to show
all three roles clearly.

### End-Of-Event PDF Report Generator

Organizers, owners, and permitted managers should be able to generate an
end-of-event report as a PDF for each event. This should be available from the
event operations/reporting area after the event starts, and especially after
tabs are closed.

The report should support:

- Generate PDF.
- Download PDF.
- Share/send PDF to owner email.
- Regenerate report after late tab closures or corrections.
- Include generated-by, generated-at, event, organization, and date window.
- Optional sections based on permissions.

Default PDF sections:

- Executive summary.
- Gross declared sales.
- Net item revenue.
- Payment method breakdown.
- Merchant-collected revenue summary.
- Open tabs still outstanding.
- Closed tabs count.
- Voids, comps, discounts, refunds.
- Item/category sales.
- Inventory used and remaining.
- Low-stock and sold-out items.
- Table package sales and add-ons.
- Staff sales leaderboard.
- Staff-by-staff sales breakdown.
- Clock-in/clock-out summary.
- Cash declaration/reconciliation summary, if enabled.
- Notes and exceptions.

Owner/manager-only PDF sections:

- Cost of goods sold.
- Gross margin.
- Profit by item/category.
- Staff shortage/overage.
- Inventory value remaining.
- Sensitive audit trail.

Recommended collection:

- `event_report_exports`

Recommended fields:

- `organizationId`
- `eventId`
- `type`: `end_of_event`
- `status`: `queued`, `generating`, `ready`, `failed`
- `requestedBy`
- `requestedByName`
- `dateWindow`
- `includeSensitiveFinancials`
- `pdfUrl`
- `storagePath`
- `summary`
- `createdAt`
- `completedAt`
- `expiresAt`

Recommended function:

- `generateEventEndOfEventReport`

The PDF should be generated server-side so sensitive financial sections are
permission-gated and the report cannot be manipulated from the client.

### Server-Authority Requirements

Unlike GPlus, Vennuzo should not let clients directly mutate inventory and
financial records for production flows. Use callables/HTTP functions:

- `createEventInventoryItem`
- `updateEventInventoryItem`
- `createEventCatalogItem`
- `listEventCatalogItems`
- `createPublicEventOrder`
- `createEventOrderPaymentSession`
- `createStaffEventOrder`
- `appendEventOrderItems`
- `updateEventOrderFulfillmentStatus`
- `closeEventOrder`
- `voidEventOrderItem`
- `adjustEventInventory`
- `createEventStaffCredential`
- `revokeEventStaffCredential`
- `clockInEventStaff`
- `clockOutEventStaff`
- `getEventBarReport`
- `getEventWaiterSalesReport`
- `getEventInventoryReport`

Every function must validate:

- Auth/session.
- `organizationId`.
- `eventId`.
- Staff credential status.
- Role permissions.
- Clock-in state where required.
- Inventory availability.
- Idempotency keys for payment/order actions.

## Revenue Points

Table package flow can generate revenue through:

- Table package sales.
- Event inventory/pre-order checkout fees.
- Waiter POS/open-tab payment processing fees.
- Inventory and event bar ops activation fee.
- Premium reporting/export fee if priced.
- Platform fee on table package checkout.
- Table package flyer generation.
- Minor AI flyer edits.
- Instagram story/post flyer downloads or export packages if priced.
- Paid CRM table upsell campaigns.
- Paid SMS/push promotions.
- Featured placement or premium event visibility.
- Optional add-on purchases.
- Optional commission on concierge/table package upsells.

This supports the earlier decision to remove generic billing plans. Revenue
should come from transactional and usage-based flows tied to organizer value.

## Event Ops Pricing

Event Inventory and Staff POS should be priced as a paid event operations
add-on, not as a generic billing plan.

Because the default payment mode is merchant-collected, Vennuzo should not take
a percentage of declared merchant-collected sales. If vendors collect money
outside Vennuzo, charging a commission on declared revenue can encourage
under-reporting. Instead, charge for access, staff seats, usage volume,
reporting, and setup support.

Recommended launch packages:

| Package | Price | Best For |
| --- | ---: | --- |
| Event Inventory Lite | GHS 250/event | Small events, pop-ups, simple vendor sales. |
| Event Ops Pro | GHS 500/event | Parties, concerts, table packages, waiter tabs. |
| Festival / Multi-Vendor Ops | From GHS 1,500/event | Multiple bars, vendors, stations, and larger teams. |

### Event Inventory Lite

Price: GHS 250/event.

Includes:

- Inventory/catalog setup.
- Merchant-collected closed tabs.
- Up to 5 staff credentials.
- Up to 200 closed tabs/orders.
- Basic sales summary.
- End-of-event PDF report.

### Event Ops Pro

Price: GHS 500/event.

This should be the hero/default package.

Includes:

- Everything in Lite.
- Up to 15 staff credentials.
- Up to 1,000 closed tabs/orders.
- Table package inventory linkage.
- Staff sales breakdown.
- Inventory movement ledger.
- Bar/vendor reports.
- End-of-event PDF with staff, item, and category breakdowns.

### Festival / Multi-Vendor Ops

Price: from GHS 1,500/event.

Includes:

- Multiple vendors, bars, or stations.
- Larger staff limits.
- Advanced reports.
- Setup support.
- Custom role permissions.
- Multi-vendor breakdowns.

### Overage Pricing

- Extra staff credential: GHS 20/staff.
- Extra 500 closed tabs/orders: GHS 100.
- Extra PDF/regenerated report pack: GHS 50.
- Assisted setup/import: GHS 200-500.

### Future Vennuzo-Controlled Payment Pricing

When Vennuzo-controlled payments come out of Coming Soon, charge a processing
fee because Vennuzo will be facilitating payment and reconciliation:

- 1.5%-2.5% platform fee on Vennuzo-processed order payments; or
- GHS 1-2 per paid order, whichever is higher.

This does not apply to merchant-collected mode.

## Event Ops Onboarding

The Event Inventory and Staff POS feature has a lot of moving parts, so it
should be presented through a guided onboarding form, not dumped into settings.
The onboarding should feel visual, progressive, and confidence-building.

Goal: help an organizer set up event operations in under 10 minutes without
needing to understand the whole system at once.

### Pre-Setup Introduction

Before the setup wizard begins, organizers should see an onboarding-like
introduction explaining what Event Ops is, why it matters, and how it works.
This should be created with Gemini so it feels visual, premium, and tailored to
the organizer's selected event.

The intro should not ask for setup details yet. Its job is to orient the user
and make the feature feel easy.

Recommended intro flow:

1. Hero visual: "Run sales, staff, inventory, and reports for this event."
2. Visual story: inventory -> catalog -> staff orders -> close tabs -> report.
3. Package/pricing explanation.
4. Merchant-collected payment explanation.
5. Coming Soon card for Vennuzo-controlled payments.
6. Staff app preview.
7. End-of-event report preview.
8. "Start setup" CTA.

Gemini should generate:

- Event-specific intro artwork or visual cards.
- A simple order-flow diagram.
- Staff app preview cards.
- Inventory/catalog preview cards.
- End-of-event PDF preview mock.
- Short, plain-language explanations tailored to the event type.

Example copy:

- "Create the items you want to sell."
- "Let waiters record orders and close tabs."
- "Vendors collect money their own way."
- "Vennuzo tracks inventory, staff sales, and reports."
- "Generate an end-of-event PDF when the event is done."

The intro should include a "Skip intro" action for returning users and the
owner/test account, but first-time organizers should see it before setup.

### Onboarding Flow

Recommended steps:

1. Choose package: Lite, Pro, or Festival.
2. Select event.
3. Choose payment mode.
4. Add inventory categories.
5. Add inventory items.
6. Create sellable catalog items.
7. Link catalog items to inventory.
8. Add table package inclusions, if relevant.
9. Create staff roles.
10. Create staff credentials.
11. Assign staff to sections/tables/stations.
12. Review setup.
13. Pay activation fee.
14. Launch event ops.

### Gemini Visual Layer

Use Gemini to generate 10/10 visual onboarding aids from the organizer's event
details and setup choices. The visuals should make complex operations legible.

Recommended Gemini-generated visuals:

- Setup summary poster for the event operations plan.
- Inventory category cards.
- Staff role cards.
- Table/section assignment map concept.
- Vendor station cards.
- "How orders flow" visual.
- "How to close a tab" visual.
- End-of-event report preview mock.
- Public event hub preview imagery.
- Staff app preview imagery.

Gemini should help produce:

- Clear step illustrations.
- Role-specific onboarding cards.
- Visual summaries before launch.
- Branded setup previews using the event flyer/brand colors.
- Simple diagrams explaining inventory, tabs, staff, and reports.

### Onboarding UX Rules

- Show only one decision at a time.
- Use a true one-step-at-a-time wizard. Each screen should focus on one setup
  task, save that task, then move to the next step.
- Use visual cards instead of long paragraphs.
- Provide smart defaults.
- Let organizers import from CSV or paste a simple list.
- Let organizers skip advanced steps.
- Use examples like "Vodka bottle", "Shisha pot", "VIP Table Add-on".
- Clearly mark Coming Soon features, especially Vennuzo-controlled payments.
- Always show the default available path: merchant-collected payments.
- Show final price before activation.
- Generate a setup checklist after completion.

### One-Step Setup Pattern

Each onboarding step should behave like this:

1. Explain the current setup task visually.
2. Show only the fields/choices needed for that task.
3. Let Gemini generate a helpful preview or visual aid where useful.
4. Save the current step to a draft activation record.
5. Validate the minimum needed to continue.
6. Mark the step complete.
7. Move to the next step.

Example step sequence:

| Step | Page Goal | Saved Output |
| --- | --- | --- |
| Package | Pick Lite, Pro, or Festival. | `event_ops_activation.packageId` |
| Event | Select the event this setup belongs to. | `eventId`, `organizationId` |
| Payment Mode | Choose merchant-collected payments. Show Vennuzo-controlled as Coming Soon. | `paymentMode` |
| Inventory Categories | Add categories such as Drinks, Food, Merch, Shisha. | `event_inventory_categories` |
| Inventory Items | Add stock with cost price, unit, and quantity. | `event_inventory_items` |
| Catalog Items | Add things customers/staff can sell. | `event_catalog_items` |
| Recipes/Links | Link catalog items to inventory quantities. | `linkedInventoryItems` |
| Table Packages | Attach inventory/catalog items to table packages. | package inclusions |
| Staff Roles | Create waiter, bartender, cashier, manager, owner, or custom roles. | `event_staff_roles` |
| Staff Credentials | Create temporary staff logins. | `event_staff_members` |
| Assignments | Assign staff to sections, tables, or vendor stations. | `event_staff_assignments` |
| Review | Show Gemini-generated setup summary and launch checklist. | reviewed draft |
| Activate | Pay activation fee and launch. | active `event_ops_activation` |

Users should be able to leave and resume onboarding from the last completed
step. Every page should have Back, Save draft, and Continue actions.

### Owner/Test Override

For the owner account `angelonartey@hotmail.com`, onboarding steps should be
skippable so the full flow can be tested without entering every setup detail.

Owner/test behavior:

- Show a "Skip for testing" action on each onboarding step.
- Allow activation of a test event ops setup with missing optional details.
- Auto-create safe placeholder records where a downstream step needs data.
- Clearly mark the activation as `testMode: true`.
- Keep test data scoped to the selected organization/event.
- Do not expose this skip flow to ordinary organizers.
- Do not skip real payment for public users unless the environment/test flag
  explicitly allows it.

Recommended access condition:

- `session.user.email == "angelonartey@hotmail.com"`; or
- superadmin/owner role with a dedicated `eventOps.testOverride` permission.

Suggested placeholder defaults:

- Inventory categories: Drinks, Food, Merch.
- Inventory item: Test Bottle, quantity 100, unit bottles, cost GHS 10.
- Catalog item: Test Bottle, selling price GHS 50.
- Staff role: Waiter.
- Staff credential: Test Waiter.
- Assignment: General section.

### Onboarding Output

After onboarding, Vennuzo should create:

- Event ops activation record.
- Inventory items.
- Catalog items.
- Table package inventory links.
- Staff roles.
- Staff credentials.
- Staff assignment records.
- Public event hub sales settings.
- Staff app access state.
- Report/export settings.

## Implementation Roadmap

### Phase 1: Package Management Upgrade

- Add package edit/archive/reactivate.
- Add package status and visibility.
- Add structured included items.
- Improve Studio package list and booking list.
- Improve public event package cards.

### Phase 2: Checkout Holds

- Add `tableHolds`.
- Change public booking creation to reserve inventory during checkout.
- Add hold expiry release job.
- Reconcile Hubtel callback and return status.
- Add oversell-safe transactions.

### Phase 3: Booking Lifecycle

- Add booking status actions in Studio.
- Add lifecycle audit records.
- Add QR token and booking detail page.
- Add check-in/scan action.
- Add customer confirmation and share state.

### Phase 4: Real Table Inventory

- Add `tableSections`.
- Add `tables`.
- Add section/table assignment.
- Add optional floor-plan position fields.
- Add automatic or manual assignment to bookings.

### Phase 5: CRM And Promotions

- Connect confirmed table buyers to CRM.
- Add table buyer segments.
- Add campaign launch from package or booking lists.
- Track campaign source and conversion.

### Phase 6: AI Creative Integration

- Generate table package flyer directly from package.
- Attach flyer to package.
- Generate Instagram story-first output and post-size exports.
- Show package creative assets in Studio and public event page.

### Phase 7: Analytics And Staff Ops

- Add revenue analytics.
- Add abandoned checkout analytics.
- Add top buyers and repeat buyers.
- Add day-of-event host list.
- Add optional pre-order/add-ons.
- Add event inventory, catalog, waiter credentials, staff app, open tabs,
  Hubtel checkout, bar reports, waiter reports, and inventory reports as the
  full event operations layer.

### Phase 8: Event Inventory MVP

- Add `event_inventory_items`.
- Add `event_catalog_items`.
- Add inventory movements ledger.
- Add Studio inventory/catalog builder on an event.
- Add public event hub pre-purchase cards.
- Add Hubtel order checkout with stock holds.

### Phase 9: Event Staff And Waiter App

- Add `event_staff_members`.
- Add temporary staff credential creation/revocation.
- Add role/permission builder.
- Add staff login routing into a special event staff shell.
- Add waiter clock-in/out.
- Add waiter order creation and open tabs.
- Add bartender/manager notifications.

### Phase 10: Event Bar Reports

- Add bar revenue report.
- Add payment reconciliation report.
- Add waiter sales report.
- Add inventory remaining/value report.
- Add COGS and margin reporting.
- Add exports for owner/manager roles.

### Phase 11: Event Ops Onboarding And Gemini Visuals

- Add guided onboarding form.
- Add package selection and activation pricing.
- Add merchant-collected payment mode as the default option.
- Show Vennuzo-controlled payment mode as Coming Soon.
- Add Gemini-generated setup visuals.
- Add CSV/paste import for inventory.
- Add staff credential creation inside onboarding.
- Add launch checklist.

## Success Definition

Vennuzo reaches 10/10 when organizers can do all of this without leaving the
platform:

1. Build a premium table package.
2. Generate promotional creative for it.
3. Promote it to the right CRM segment.
4. Sell it publicly with oversell protection.
5. Confirm the buyer through Hubtel.
6. Issue a QR booking receipt.
7. Check in and seat the guest at the event.
8. Sell inventory and add-ons through the event hub.
9. Let waiters place orders and manage open tabs in a special staff app.
10. Track table revenue, bar revenue, stock, margin, staff performance, and
    campaign conversion.
