# QR Code-Based Guest Ordering System

Implement a QR Code-Based Guest Ordering System allowing walk-in café guests to scan a table QR code and order directly from their mobile devices without needing to log in or register.

## User Review Required

> [!IMPORTANT]
> - Guest orders will be distinguished from registered customer orders in admin and employee dashboards using a clear **[Guest]** badge.
> - Guests receive an Order Reference Number and a 20-minute active countdown upon ordering, and can track their order status anytime via a dedicated **"Track Order"** guest lookup tool without logging in.
> - A table QR code generator screen/dialog will be available for admins and staff to display or print for tables and counters.

## Proposed Changes

### 1. Data Model Updates
- [MODIFY] `lib/models/models.dart`: Add `isGuest` (bool) and table/guest metadata to `OrderRecord`.

### 2. Guest Ordering Shell & Kiosk Interface
- [NEW] `lib/screens/guest/guest_ordering_shell.dart`: Guest-facing ordering shell providing menu browsing, cart, checkout (Cash/GCash with receipt upload, partial payment), order placement, and an accessible "Track Order" lookup dialog.
- [NEW] `lib/screens/guest/guest_track_order_screen.dart`: Guest order tracking screen allowing customers to enter their Order Reference ID to monitor live status (Pending, Preparing, Ready, Completed, Declined) without login.

### 3. QR Code Generator & Table Management
- [NEW] `lib/screens/admin/qr_generator_screen.dart`: Table QR Code generator and printable display card for café tables and counter.

### 4. Admin & Employee Interface Integration
- [MODIFY] `lib/screens/employee/kiosk_management_screen.dart` and `lib/screens/admin/admin_order_history_screen.dart`: Add distinct **[Guest]** badges and source indicators to differentiate guest orders from registered customer orders.

## Verification Plan

### Automated Tests
- Run `flutter analyze` and existing test suites.

### Manual Verification
- Test placing an order as a guest without logging in.
- Test tracking an order using the Order Reference Number.
- Verify guest orders appear in the employee kitchen management screen with a **[Guest]** badge.
- Verify QR code generation screen in the admin panel.
