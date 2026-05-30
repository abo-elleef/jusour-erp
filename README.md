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
