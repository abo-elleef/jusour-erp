# Pickup orders: capture the customer (with a skip button)

Status: BUILT 2026-11-23 on feature/pickup-customer-capture (uncommitted). Approved idea: branch managers agreed pickup orders should carry a customer, so visit frequency and spend per customer stop missing pickup regulars.

## Goal

When a cashier places or charges a **pickup** order with no customer, the POS asks for the customer's phone first. The cashier either:
- types the phone → existing customer matched, or a new one created from the phone alone (name optional), or
- presses **Skip** and picks a reason (refused / walk-in in a hurry / other).

An honest skip is always cheaper than a fake number. Skips are recorded and reported per cashier and branch.

## Decisions (proposed defaults — confirm before building)

1. **Per-branch switch** `Location#pickup_customer_prompt` (boolean, default **off**). Turned on branch by branch.
2. **A skip always needs a reason.** No plain "close and continue".
3. **Only pickup.** Table (dine-in) and delivery are unchanged. Delivery already requires a customer for its address.
4. **Offline mode never blocks.** An optional phone field only.
5. **Online/self-orders** already come with a phone, so they are not touched.

## Where it hooks in (existing code)

- `Orders::SubmitService.validate_fulfillment!` (`app/services/orders/submit_service.rb`) is the single check that runs before **Place** (`PosController#submit`) and before any money is taken (`Pos::PaymentsController#require_submittable_order!`). Add the pickup rule there:
  `order.pickup? && order.location&.pickup_customer_prompt? && order.customer.nil? && order.customer_skip_reason.blank?` → raise `InvalidFulfillment` ("Enter the customer's phone or skip with a reason").
  This is the server safety net; the popup below means cashiers normally never see the error.
- `Orders::CompleteService` already rescues `InvalidFulfillment` and skips that order in bulk complete. Pickup drafts with no customer get skipped the same way, which is acceptable: unpaid drafts are rare in pay-first.
- Place-order popup pattern: `app/views/pos/_cart_actions.html.erb` already swaps the F8 button for a `<dialog>` when a delivery order has no fee. The pickup phone popup copies that pattern.

## Build steps

### 1. Data
- Migration: `locations.pickup_customer_prompt boolean default false null false`.
- Migration: `orders.customer_skip_reason string null` (values: `refused`, `in_a_hurry`, `other`), validated by inclusion, `nil` allowed.
- Order: clear `customer_skip_reason` when a customer gets attached (`PosController#attach_customer`) or when the type changes away from pickup (`clear_fulfillment_fields_for_type`).
- Admin location form: checkbox + hint, next to `free_table_on_payment`, and permit it in `Admin::LocationsController`.

### 2. POS popup (`pos/_pickup_customer_dialog.html.erb`)
- Shown when `order.pickup? && location.pickup_customer_prompt? && order.customer.nil? && order.customer_skip_reason.blank?`.
- Both **Place (F8)** and **Charge (F9)** open it instead of going straight on. F9 needs a small change in `pos_controller.js#openPayment`: if the dialog exists, open it, and remember that the next step is to charge.
- Contents: one phone field (autofocus, `inputmode="tel"`, arabic-numerals controller so Arabic digits work), an optional name field, live match line ("Ahmed — 12 visits" / "New customer"), reusing the customer search endpoint `pos_customer_controller.js` already calls.
- **Enter** = save the customer and continue. **Skip** opens three reason buttons (keys 1/2/3), and picking one continues.
- Posts to a new action `PosController#pickup_customer` with `phone`, `name`, `skip_reason` and `next` (`place` | `charge`):
  - phone given → `find_or_create_customer` (existing helper, so normalising and matching stay identical) + `apply_customer_defaults!`
  - skip → save `customer_skip_reason`
  - `next=place` → run the same code path as `submit`; `next=charge` → redirect to `pos_path(open_payment: 1)` and the POS opens the payment modal on load.
- Keyboard flow target: F9 → type phone → Enter → payment modal. One extra Enter compared with today.

### 3. Offline register
- `offline_pos_controller.js`: on pickup orders, show an optional phone field in the checkout step (never required).
- `Orders::SyncOfflineOrderService#build_order`: today it attaches `delivery_customer` only for delivery. Attach the matched/created customer for pickup too **when a phone is present**; a blank phone stays a customer-less order. Keep the JS and Rails behaviour in step (see the POS offline mode memory).

### 4. Report: capture rate
- Add to **Sales performance** (`Accounting::SalesPerformanceService`, the who/where report): per cashier and per branch, pickup orders, with customer, skipped (by reason), and capture %. Exclude void/cancelled/draft (status-filter rule).
- Managers use this for coaching; there's no automatic penalty.

### 5. Tests
- SubmitService: pickup with prompt on + no customer + no reason raises; with a customer or a reason it passes; prompt off passes; table and delivery unchanged.
- Payments: charging a pickup order blocked before money is taken (no paid draft left behind).
- `pickup_customer` action: existing phone matches (no duplicate), new phone creates a customer, skip saves the reason, attaching a customer later clears the reason.
- Offline sync: pickup with a phone attaches a customer; without one it still syncs.
- System spec: F9 → phone → Enter → payment modal opens.

## Rollout
1. Deploy with the switch off everywhere (no behaviour change).
2. Turn it on at one SAQR branch for a week. Watch the capture % and any cashier complaints.
3. Then turn it on at the other branches.

## Open notes
- **Loyalty:** points are already **earned** automatically on any order with a customer (`Loyalty::AwardPointsJob`), so "for your points" holds. Redeeming is hidden on the POS (`if false` block in `_cart_actions.html.erb`). Decide whether to switch redemption on before telling customers about points.
- Fake-number guard (later, if needed): flag customers whose phone is used on an unusual number of orders per day, e.g. on the capture report.
