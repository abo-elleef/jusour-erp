# Jusour — customer onboarding checklist

Use one copy of this per customer. Fill in the **Time** column as you go: after
the first 3 customers it tells you what onboarding really costs and what to
automate next. Target: a restaurant/café with 1–3 branches live within a week
of the pilot starting.

Customer: ____________  Start date: ________  Branches: ___  Plan / price: ________

## 0. Before you commit (qualification — 15 min call)

- [ ] 2–10 branches (or one strong branch with growth plans). Skip single stalls.
- [ ] Owner (or a decision-maker) will attend setup and training.
- [ ] Who keys in sales today (cashier app, paper, another system)? Is there a system to export from?
- [ ] Printers: how many, which model, thermal 80 mm? Network (LAN) or USB?
- [ ] Do they have reliable internet at each branch? (Explain the offline register.)
- [ ] Do they sell on credit or only cash/card/wallet? Delivery? Online orders?
- [ ] Agree the pilot: 2–4 weeks, one branch, one success metric (e.g. "day close < 10 min", "see branch profit daily"), and the price they convert to.
- [ ] Setup fee agreed and invoiced; annual prepay offered.

## 1. Collect from the customer (before you touch the system)

Ask for these as a shared sheet/WhatsApp photos; chasing them is the biggest delay.

| Item | Detail | Done | Time |
|---|---|---|---|
| Company details | Legal/trading name, logo (for receipts), receipt footer text, timezone, currency | | |
| Branches | Name, address, type (branch / central kitchen), opening hours, business-day start hour | | |
| Menu | Items, categories, prices, modifiers/extras, combos, tax category | | |
| Ingredients | Name, unit, category, purchase cost, reorder level (needed for recipes / food cost) | | |
| Recipes | Which ingredients (and how much) go into each menu item | | |
| Suppliers | Name, phone, payment terms, outstanding balance | | |
| Staff | Name, role, branch, salary, phone, start date | | |
| Opening cash | Safe, each drawer, bank, wallets: balance on go-live day | | |
| Opening stock | Counted quantity per ingredient per branch on go-live day | | |
| Tax | Which tax rates apply (confirm with their accountant — do not guess) | | |
| Payment methods | Cash, card, wallets (names), online/delivery companies | | |

## 2. Set up the company (in this order — later steps depend on earlier ones)

Done in the super-admin area first, then as the customer's owner in the admin area.

| # | Step | Where | Notes | Done | Time |
|---|---|---|---|---|---|
| 1 | Create the company | Super admin → New company | Locale `ar`, timezone `Africa/Cairo`, currency `EGP`, business type `restaurant`. Roles, units and attendance statuses are created automatically. | | |
| 2 | Set subscription | Same page → Plan + Paid until | Set the term you agreed (pilot = short term). Blank = no expiry. | | |
| 3 | Create the owner account | Company page → Add owner | Give the owner a real password; they can change it themselves. | | |
| 4 | Branches | Admin → Locations | One per branch; central kitchen if they have one. | | |
| 5 | Tax rates | Admin → Tax rates | Only the rates confirmed in step 1. | | |
| 6 | Treasuries + opening cash | Admin → Accounting → Treasuries | Opening balance = cash on go-live day. Create safe, drawers, bank, wallets. | | |
| 7 | Expense/income categories | Admin → Accounting | Review defaults; keep names meaningful to the owner. | | |
| 8 | Ingredient categories + ingredients | Admin → Inventory → Ingredients | Set **cost per unit** for every ingredient (it is a hand-kept standard cost and drives food cost reports). For long lists use `products:import` (dry run first). | | |
| 9 | Suppliers | Admin → Inventory → Suppliers | Link supplier ingredients if they reorder from fixed lists. | | |
| 10 | Menu: categories, items, modifiers | Admin → Menu items / Modifiers / Combos | Biggest manual step today. Tick availability per branch. | | |
| 11 | Recipes | Menu item → Recipes | Needed for food cost and stock deduction. | | |
| 12 | Staff accounts + roles | Admin → Users / Roles | Cashier, kitchen, manager. Assign branches. Set PINs for manager approvals. | | |
| 13 | Opening stock | Admin → Inventory → Stock takes (per branch) | Count on go-live day. Completing a count applies the difference as `cycle_count_correction` adjustments **valued at each ingredient's cost, so do step 8 first**. It runs as a background job (the Sidekiq worker must be up). Expect these to appear as positive corrections in the adjustments/shrinkage reports; tell the owner, or filter that first take out when reading them. | | |
| 14 | Opening balances for suppliers/customers | Vendor invoices / customers | Only if needed; mark old invoices as historical rather than recreating them. | | |
| 15 | Receipt settings | Admin → Settings | Restaurant name, logo, footer, business-day settings. | | |

## 3. Hardware and printing

| Step | Done | Time |
|---|---|---|
| Add each register as a workstation (Admin → Workstations) and link its receipt printer, so receipts print on the right device | | |
| Add printers (receipt, kitchen) and set print routing | | |
| **Test-print an Arabic receipt on the real printer**, including a long item name and a modifier | | |
| Test the kitchen ticket / KDS flow | | |
| Open the offline register once on each device so it is cached; test one cash sale with Wi-Fi off | | |

## 4. Dry run before go-live (owner present)

- [ ] Ring a cash order, a card order and a delivery order from a test account.
- [ ] Take a payment, apply a discount, void an order (needs manager PIN).
- [ ] Open and close a shift and the cash drawer; do a day close.
- [ ] Check the dashboard and the branch P&L show the test sales (then clear or ignore them as agreed).
- [ ] Check stock went down for a recipe item.

## 5. Training (about 2 hours, on their screens)

1. Cashier: open shift, take order, pay, refund/void, close shift (30 min).
2. Kitchen: tickets / KDS (15 min).
3. Manager: day close, stock transfers, stock take (30 min).
4. Owner: dashboard, branch profit, labour cost %, supplier invoices, who can see what (45 min).
- [ ] Leave a one-page Arabic quick guide at each register.
- [ ] Give them your WhatsApp support number and hours.

## 6. Go-live day and follow-up

| When | What | Done |
|---|---|---|
| Day 0 | Be reachable all day. Check the first orders and the first day close together. | |
| Day 3 | Call: what is confusing? Anything wrongly set up? | |
| Day 7 | Review: stock movements make sense, drawer balances reconcile. | |
| Day 14 | Show the owner their first branch profit and labour reports. | |
| End of pilot | Review the success metric; convert to the annual plan, collect payment, record it in super admin (Record payment). | |

## 7. Log for yourself (feeds your pricing and what to build)

- Hours spent: setup ____  training ____  first-month support ____
- Questions/requests that came up more than once: ____________
- Anything you did manually that could be a button or an import: ____________

---

## Known gaps in the tooling (what slows onboarding today)

Ordered by how much time each would save:

1. **No menu import.** Menu items, categories and prices are entered one by one (or via a seed script written per customer, as for SAQR). A CSV menu importer (dry run, like `products:import`) is the biggest saving.
2. **The demo starter is a US-style fried-chicken template.** `demo:fried_chicken` seeds a US "State Food Tax" (8%), "Beverage Tax" (8.5%) and a "Federal Standard" overtime rule. Use it for demos only; never copy it to a real customer without replacing those.
3. **`products:import` is rake-only and expects a legacy-system layout** (`code,name,unit_raw,cost,selling_price`, Arabic piece names mapped to `pieces`). A generic ingredient CSV import in the admin UI would remove the console step.
4. **No workstation in the starter data.** The demo bootstrap creates printers but no workstation; each register needs one linked to its receipt printer (section 3).
5. **No "new customer" wizard.** Steps 1–5 and 15 are separate screens; a short guided flow after "New company" would cut mistakes.
6. **Opening stock and balances are manual** (stock take per branch; treasury opening balances). Fine for 1–3 branches; revisit if you onboard bigger chains.
