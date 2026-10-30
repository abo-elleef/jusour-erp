# frozen_string_literal: true

Rails.application.routes.draw do
  # Storefronts on their own subdomain (acme.<storefront_domain>). Must come
  # first: on a storefront host nothing else of the app may match, sign-in included.
  constraints(->(request) { Storefront.host_match?(request) }) do
    scope module: :public, as: :storefront_host do
      get "/", to: "storefronts#show", as: :home
      get "p/:listing_slug", to: "storefront_products#show", as: :product
      get "pages/:page_slot", to: "storefront_pages#show", as: :page
      get "sitemap.xml", to: "storefronts#sitemap", as: :sitemap, defaults: { format: :xml }
    end
    # Nothing else of the app answers on a storefront host — no sign-in page or
    # admin under a client's brand. Active Storage stays reachable for photos.
    match "*path", to: "public/storefronts#not_found", via: :all, format: false,
      # Restates the host check: a route-level constraint replaces the block's.
      constraints: ->(request) { Storefront.host_match?(request) && !request.path.start_with?("/rails/") }
  end

  devise_for :users, controllers: {
    sessions: "users/sessions",
    passwords: "users/passwords"
  }

  devise_for :super_admin_users, path: "super_admin/auth", controllers: {
    sessions: "super_admin/sessions"
  }, skip: %i[registrations passwords confirmations unlocks]

  namespace :super_admin do
    root to: "dashboard#index"
    resources :companies do
      member { get :impersonate }
      resources :locations, only: %i[new create edit update]
      resources :users, only: %i[new create]
      resource :storefront_domain, only: %i[edit update]
    end
  end

  root "home#index"

  patch "locale", to: "locales#update", as: :locale

  # Self-service password change — every signed-in role reaches this, not just
  # the owners/accountants who can open /admin/users.
  namespace :account do
    resource :password, only: %i[edit update]
  end

  get "up" => "rails/health#show", as: :rails_health_check

  get "pos", to: "pos#index"
  post "pos/new_order", to: "pos#new_order", as: :pos_new_order
  patch "pos/apply_coupon", to: "pos#apply_coupon"
  patch "pos/manager_discount", to: "pos#manager_discount"
  patch "pos/redeem_points", to: "pos#redeem_points"
  patch "pos/location", to: "pos#set_location", as: :pos_set_location
  patch "pos/workstation", to: "pos#set_workstation", as: :pos_set_workstation
  patch "pos/submit", to: "pos#submit"
  patch "pos/attach_customer", to: "pos#attach_customer"
  patch "pos/fulfillment", to: "pos#update_fulfillment", as: :pos_update_fulfillment
  patch "pos/notes", to: "pos#update_notes", as: :pos_update_notes
  post "pos/split", to: "pos#split"
  post "pos/merge", to: "pos#merge"

  patch "pos/customer/:id", to: "pos/customers#update", as: :pos_customer

  namespace :pos do
    resource :shift, only: [:show] do
      post :open_drawer
      post :clock_in
      get :count
      patch :reconcile
      patch :clock_out
    end

    post "verify_manager_pin", to: "manager_pin#verify"
    get "modifier_form", to: "order_items#modifier_form", as: :modifier_form
    resources :orders, only: %i[index show destroy] do
      collection do
        post :sync_offline
        post :complete_all
        post :collect_all_cash
      end
      member do
        post :print_receipt
        post :print_all
        post :resume
        post :complete
        patch :update_fulfillment
      end
    end
    resources :order_items, only: %i[create update destroy]
    resources :print_logs, only: [] do
      collection do
        get :pending
      end
      member do
        get :payload
        patch :confirm
      end
    end
    resources :payments, only: [:create] do
      collection do
        post :stripe_intent
        post :capture_stripe
      end
    end
  end

  get "kitchen", to: "kitchen#index"
  patch "kitchen/:id/start", to: "kitchen#start", as: :kitchen_start
  patch "kitchen/:id/ready", to: "kitchen#ready", as: :kitchen_ready

  get "production", to: "production#index"
  post "production/bulk", to: "production#bulk_create", as: :production_bulk
  # Must come before the :manufacturing_template_id catch-all below, or a POST
  # here would be routed as create with "transfer_batch" as the template id.
  post "production/transfer_batch", to: "production#transfer_batch", as: :production_transfer_batch
  post "production/:manufacturing_template_id", to: "production#create", as: :production_run

  namespace :customers do
    get "search", to: "search#index"
  end

  get "receipts/:token", to: "receipts#show", as: :receipt

  scope module: :public, path: "m" do
    get ":company_slug", to: "menus#index", as: :public_menus
    get ":company_slug/:location_slug", to: "menus#show", as: :public_menu
  end

  # Storefront by path — always works, before (or without) a subdomain.
  scope module: :public, path: "s/:company_slug", as: :public_storefront do
    get "/", to: "storefronts#show", as: :home
    get "p/:listing_slug", to: "storefront_products#show", as: :product
    get "pages/:page_slot", to: "storefront_pages#show", as: :page
    get "sitemap.xml", to: "storefronts#sitemap", as: :sitemap, defaults: { format: :xml }
  end

  get "staff/payroll/:token", to: "staff_payroll#show", as: :staff_payroll
  post "staff/payroll/:token/verify", to: "staff_payroll#verify", as: :verify_staff_payroll
  delete "staff/payroll/:token", to: "staff_payroll#lock", as: :lock_staff_payroll

  namespace :admin do
    root "dashboard#index"

    # Distribution sales (AR / credit sales) — gated behind the ar_credit_sales feature.
    namespace :sales do
      resources :customer_invoices, only: %i[index new create show edit update] do
        member do
          post :confirm
          post :approve_payment
          post :reject_payment
          post :mark_dispatched
          patch :void
          patch :attach_payment_proof_image
        end
      end
      resources :payment_methods, controller: "payment_methods", except: %i[show]
      resources :credit_notes, only: %i[index new create show] do
        member do
          post :confirm
          patch :void
        end
      end
      resources :price_tiers, except: %i[show]
      resources :shipping_companies
      resources :customer_statements, only: %i[index show]
      resources :leads do
        member do
          post :convert
          post :mark_lost
        end
        resources :lead_activities, only: %i[create]
      end
      resources :lead_reports, only: %i[index]
      # The public catalog website — gated on the `storefront` feature.
      resource :storefront, only: %i[show update]
      # Keyed by the inventory category's id: the storefront row is created on
      # first save, so a category without one can still be edited.
      resources :storefront_categories, only: %i[index edit update]
      # The four fixed info pages, keyed by slot (about, contact, ...).
      resources :storefront_pages, only: %i[index edit update], param: :slot
      resources :storefront_sections, except: %i[show new] do
        member do
          patch :toggle
          patch :move
          delete :remove_logo
        end
        collection { patch :reorder }
      end
      resources :storefront_listings, except: %i[show] do
        collection do
          get :bulk_new
          post :bulk_create
        end
        member { delete :remove_image }
      end
      resources :reports, only: %i[index]
    end

    resources :categories do
      patch :reorder, on: :collection
    end
    resources :menu_items, except: [:show] do
      resources :recipes, only: %i[create destroy], module: :menu_items
    end
    resources :menu_promos, except: [:show]
    resources :modifier_groups, except: [] do
      resources :modifiers, except: %i[index show] do
        resources :modifier_recipes, only: %i[create destroy], module: :modifiers
      end
    end
    resources :combos
    resources :customers
    resources :users do
      member do
        patch :activate
        post :create_assigned_treasury
      end
      resources :payroll_adjustments, only: %i[create destroy], module: :users
      resource :payroll_snapshot, only: %i[create destroy], module: :users
    end
    get "settings", to: "settings#index", as: :settings
    patch "settings", to: "settings#update"
    get "reports", to: "reports#index", as: :reports
    resources :roles, except: %i[show]
    resources :tax_rates, only: %i[new create edit update destroy]
    resources :printers do
      member { post :test_print }
    end
    resources :workstations, except: [:show]
    get "print_agent/test_payload/:printer_id", to: "print_agent#test_payload", as: :print_agent_test_payload
    get "print_debug", to: "print_debug#show", as: :print_debug
    resources :orders, only: %i[index show] do
      member do
        post :void
        post :refund
        patch :change_payment_method
      end
    end

    resources :locations do
      resources :menu_items, only: %i[index update], module: :locations do
        collection do
          post :bulk_update
        end
      end
      resources :ingredients, only: %i[index update destroy], module: :locations do
        member { post :adjust }
        collection { post :clear_stock }
      end
    end

    resources :notifications, only: [:index] do
      member { patch :mark_read }
      collection { patch :mark_all_read }
    end

    namespace :accounting do
      root to: "dashboard#index"

      resources :sales_reports, only: [:index]
      resources :food_costs, only: [:index]
      resources :usage_reports, only: [:index]
      resources :category_analysis, only: [:index]
      resources :expense_categories do
        collection { patch :reorder }
      end
      resources :expenses
      resources :income_categories do
        collection { patch :reorder }
      end
      resources :incomes
      # A voucher is issued or voided, never edited — an amended one is a new
      # document with its own number.
      resources :vouchers, except: %i[edit update]
      resources :discount_rules, except: [:show]
      resources :treasuries do
        member { post :adjust }
      end
      resources :treasury_transfers, only: %i[new create]
      resources :payment_method_treasuries, only: %i[index create destroy]
      resources :chart_of_accounts, only: [:index]
      resources :financial_statements, only: [] do
        collection do
          get  :profit_loss
          get  :balance_sheet
          get  :cash_flow
          get  :profit_vs_cash
          get  :cash_flow_lines
          get  :balance_sheet_lines
          post :update_inventory_snapshot
        end
      end
      resources :journal_entries, only: %i[index show new create]
      resources :partners, only: %i[index show new create edit update] do
        member do
          get  :new_advance,    path: "advance/new"
          post :create_advance, path: "advance"
        end
      end
      get  "profit_distribution/new",  to: "partners#new_profit_distribution",    as: :new_profit_distribution
      post "profit_distribution",      to: "partners#create_profit_distribution",  as: :profit_distribution

      resources :loans, only: %i[index show new create edit update] do
        member do
          get  :new_disbursement,   path: "disbursement/new"
          post :create_disbursement, path: "disbursement"
          get  :new_opening_balance,   path: "opening_balance/new"
          post :create_opening_balance, path: "opening_balance"
          get  :new_repayment,      path: "repayment/new"
          post :create_repayment,   path: "repayment"
          get  :new_interest,       path: "interest/new"
          post :create_interest,    path: "interest"
        end
      end
      resources :fixed_assets do
        member { post :record_payment }
        member { patch :dispose }
      end
      resources :budgets, only: [:index] do
        collection { patch :update }
      end

      resources :shift_logs, only: %i[index show] do
        collection do
          post :clock_in
        end
        member do
          patch :clock_out
        end
      end

      get "attendance", to: "attendance#index"
      patch "attendance", to: "attendance#update"
      post "attendance/adjustment", to: "attendance#adjustment", as: :attendance_adjustment
      get "attendance/cell_history", to: "attendance#cell_history", as: :attendance_cell_history
      resources :late_penalties, only: %i[index destroy]

      get "payroll", to: "payroll#index"
      get "payroll/export", to: "payroll#export", as: :payroll_export
      get "monthly_payroll", to: "monthly_payroll#index"
      post "monthly_payroll/finalize_all", to: "monthly_payroll#finalize_all", as: :monthly_payroll_finalize_all
      get "monthly_payroll/export", to: "monthly_payroll#export", as: :monthly_payroll_export
      resources :staff_payments_reports, only: [:index]

      resources :tax_reports, only: [:index]

      resources :cash_drawer, only: [:index], controller: "cash_drawer" do
        collection do
          post :open_session
        end
        member do
          get :count
          patch :reconcile
        end
      end

      resource :digital_wallet_day_close, only: %i[show update], controller: "digital_wallet_day_closes"

      resources :business_days, only: [:index] do
        collection do
          patch :update_defaults
          post :advance
          post :advance_all
        end
      end
      patch "business_days/:location_id", to: "business_days#update", as: :business_day

      resources :audit_log, only: [:index], controller: "audit_log"

      resources :integrations, only: [:index] do
        collection do
          get "connect/:provider", action: :connect, as: :connect
          get "callback/:provider", action: :callback, as: :callback
        end
        member do
          post :sync
          delete :disconnect
        end
      end
    end

    namespace :inventory do
      resources :units, except: %i[show]
      resources :unit_conversions, only: %i[index] do
        collection { patch :bulk_update }
      end
      resources :ingredient_availabilities, only: %i[index] do
        collection { patch :bulk_update }
      end
      resources :ingredient_categories do
        member { get :count_sheet }
        collection { patch :reorder }
      end
      resources :ingredients do
        member do
          post :adjust
          get :adjustments
          get :batches
          post :sync_cost_from_last_invoice
          post :sync_cost_from_batches
        end
        collection { get :low_stock }
        resources :recipes, only: %i[create destroy]
        resources :supplier_ingredients, only: %i[create update destroy]
        resource :consolidation, only: %i[new create], controller: "ingredient_consolidations"
      end
      resources :suppliers do
        member do
          get :purchase_request
          get :count_sheet
        end
      end
      resources :vendor_invoices, only: %i[index show new create edit update] do
        member do
          get :export
          post :mark_historical
          delete :mark_historical, action: :unmark_historical
          post :receive
          patch :void
          patch :attach_invoice_image
        end
        resources :vendor_invoice_payments, only: [:destroy], module: :vendor_invoices
      end
      resources :vendor_credit_notes, only: %i[index show new create] do
        member do
          post :confirm
          patch :void
        end
      end
      resources :stock_takes, only: %i[index show new create update] do
        member do
          post :complete
          post :cancel
          get :count_sheet
        end
      end
      resources :stock_transfers, only: %i[index show new create edit update destroy] do
        member do
          get :duplicate
          post :submit
          post :send_transfer
          post :confirm_receipt
          post :close_short
          post :cancel
          post :void_shipment
          post :revert_shipment
        end
      end
      resources :stock_transfer_templates do
        member { post :duplicate }
      end
      resources :manufacturing_templates do
        member { post :run }
        collection { patch :reorder }
        resources :lines, only: %i[create destroy], controller: "manufacturing_template_lines"
      end
      resources :import_shipments, only: %i[index new create show] do
        member do
          post :add_cost
          delete :remove_cost
          post :attach_invoice
          delete :detach_invoice
          post :finalize
        end
      end
      resources :manufacturing_runs, only: %i[index show new create] do
        member { post :reverse }
      end
      namespace :reports do
        get :movements
        get :valuation
        get :variance
        get :transfer_trends
        get :vendor_basket
        get :vendor_purchases_summary
      end
    end
  end

  require "sidekiq/web"
  authenticate :user, ->(u) { u.owner? } do
    mount Sidekiq::Web => "/sidekiq"
  end
end
