# Saqr POS

Production-ready Point of Sale for a fried chicken and smash burger quick-service restaurant.

**Stack:** Rails 7.1 · PostgreSQL (UUID PKs) · Hotwire · Tailwind · Devise · Pundit · Stripe · Sidekiq · SendGrid · Twilio

## Quick start

```bash
bundle install
rails db:create db:migrate db:seed
bin/dev   # or: rails server
```

**Seed logins** (password: `changeme123`):

| Role    | Email                    |
|---------|--------------------------|
| Owner   | owner@restaurant.com     |
| Manager | manager@restaurant.com   |
| Cashier | cashier@restaurant.com   |
| Kitchen | kitchen@restaurant.com   |

## Routes

| Path | Description |
|------|-------------|
| `/pos` | Cashier POS screen |
| `/kitchen` | Kitchen display (KDS) |
| `/admin` | Menu, combos, discounts, customers |
| `/receipts/:token` | Public receipt (SMS link) |

## Environment

Copy `.env.example` and set keys for Stripe, SendGrid, Twilio, Redis, and Cloudinary.

```bash
cp .env.example .env
```

## Offline mode (POS)

When the internet drops but the restaurant's LAN is up, the POS keeps taking cash
orders and printing.

- **How it switches.** Every online POS page checks `/up` every 8 s (the browser's own
  "online" flag is not enough — a router with a dead uplink still reads online). Two
  misses in a row → the page goes to `/pos/offline`, a register drawn in the browser
  from a menu snapshot kept in IndexedDB. Opening `/pos` with no internet lands there
  too (the service worker serves the cached page). When the server answers again it
  syncs and returns to `/pos` by itself.
- **What works offline:** items, modifiers, notes, table/pickup, cash payment with change,
  customer receipt, kitchen/bar/expo tickets. Not offline: card, Instapay, Vodafone
  Cash, gift cards, staff meals, customers, coupons, delivery.
- **Printing** is built in the browser (canvas → ESC/POS raster, so Arabic shapes
  correctly) and sent to the print agent on the same computer. The agent only needs the LAN.
- **Sync:** `POST /pos/offline/orders`, one order at a time, idempotent on
  `orders.client_uuid`. The order keeps its real time and cashier, goes into that
  cashier's open drawer, and is **not** printed again. The offline receipt number
  (`OFF-n`) is stored in `orders.offline_number`. A price that differs from the menu is
  accepted but logged as `order.offline_price_differs`.
- **A computer is ready for an outage** once any POS page has loaded online on it
  (that caches the snapshot, the offline page and the JS/CSS). A brand-new computer
  that has never loaded `/pos` online cannot go offline.
- Orders that could not sync (e.g. a menu item was deleted) stay in the browser; the
  amber banner on the POS links to the offline page, which lists them.

## Heroku

```bash
heroku create your-app-name
heroku addons:create heroku-postgresql:essential-0
heroku addons:create heroku-redis:mini
# Set all vars from .env.example
git push heroku main
heroku run rails db:seed
heroku ps:scale web=1 worker=1
```

Uses `Procfile` (web + worker + release migrate).

## Tests

```bash
bundle exec rspec
```

## Modules

- **A** — Menu builder, combos, POS cart, split/merge, kitchen notes
- **B** — Cash, card (Stripe Terminal), gift cards, coupons, tax, tips, refunds/voids
- **C** — Customers, loyalty points, email/SMS receipts
