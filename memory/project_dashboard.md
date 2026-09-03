---
name: project-dashboard
description: Dashboard home page feature — what was built and what was discussed but skipped
metadata:
  type: project
---

Dashboard (`Admin::DashboardController#index`, `app/views/admin/dashboard/index.html.erb`) was rebuilt as the main home page.

**Implemented sections (all queries are COUNT/SUM only — no full object loading):**

- **Today at a glance** — revenue, order count, avg order value (`orders:view` gate)
- **Treasury flow today** — total money in vs money out across all visible treasuries for today's `occurred_on` (`accounting_any_access?` gate); green/red cards
- **Inventory alerts** — low stock, out of stock, missing cost counts with links to filtered ingredient list (`inventory_any_access?` gate)
- **Pending work** — open stock takes, outstanding AP invoices, payroll finalized badge (`inventory_any_access?` / `payroll:view` gates)
- **Quick links** — Orders, Menu, Customers, Expenses, Income, Treasury (→ default treasury show page), Vendor invoices, Stock transfers, Inventory; each permission-gated

**Treasury quick link** goes directly to the default treasury show page (`is_default: true`, or first active ordered treasury as fallback), visible only to `accounting:ledgers`.

**Discussed but skipped for now:**
- Open orders right now (submitted/in_progress/ready count)
- Unpaid orders count + total due
- MTD revenue alongside today's revenue
- Top 5 items today (heavier — needs order_items join)
- Net treasury movement (derived from existing in/out)
- Staff on shift today

**Why:** User was happy with current scope — "we are good so far, nothing to be added for now."
