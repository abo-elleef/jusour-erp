# frozen_string_literal: true

Rails.application.routes.draw do
  devise_for :users, controllers: {
    sessions: "users/sessions",
    passwords: "users/passwords"
  }

  root "home#index"

  patch "locale", to: "locales#update", as: :locale

  get "up" => "rails/health#show", as: :rails_health_check

  get "pos", to: "pos#index"
  post "pos/new_order", to: "pos#new_order", as: :pos_new_order
  patch "pos/apply_coupon", to: "pos#apply_coupon"
  patch "pos/manager_discount", to: "pos#manager_discount"
  patch "pos/redeem_points", to: "pos#redeem_points"
  patch "pos/submit", to: "pos#submit"
  patch "pos/attach_customer", to: "pos#attach_customer"
  patch "pos/fulfillment", to: "pos#update_fulfillment", as: :pos_update_fulfillment
  post "pos/split", to: "pos#split"
  post "pos/merge", to: "pos#merge"

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
    resources :orders, only: %i[index show] do
      collection { post :sync_offline }
    end
    resources :order_items, only: %i[create update destroy]
    resources :print_logs, only: [] do
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
  post "production/:manufacturing_template_id", to: "production#create", as: :production_run

  namespace :customers do
    get "search", to: "search#index"
  end

  get "receipts/:token", to: "receipts#show", as: :receipt

  get "staff/payroll/:token", to: "staff_payroll#show", as: :staff_payroll
  post "staff/payroll/:token/verify", to: "staff_payroll#verify", as: :verify_staff_payroll
  delete "staff/payroll/:token", to: "staff_payroll#lock", as: :lock_staff_payroll

  namespace :admin do
    root "dashboard#index"
    resources :categories do
      patch :reorder, on: :collection
    end
    resources :menu_items, except: [:show] do
      resources :recipes, only: %i[create destroy], module: :menu_items
    end
    resources :modifier_groups, except: [] do
      resources :modifiers, except: %i[index show]
    end
    resources :combos
    resources :customers
    resources :users do
      resources :payroll_adjustments, only: %i[create destroy], module: :users
      resources :payroll_advances, only: %i[create destroy], module: :users
      resource :payroll_snapshot, only: %i[create destroy], module: :users
    end
    get "settings", to: "settings#index", as: :settings
    patch "settings", to: "settings#update"
    resources :tax_rates, only: %i[new create edit update destroy]
    resources :printers do
      member { post :test_print }
    end
    get "print_agent/test_payload/:printer_id", to: "print_agent#test_payload", as: :print_agent_test_payload
    resources :orders, only: %i[index show] do
      member do
        post :void
        post :refund
      end
    end

    resources :locations do
      resources :menu_items, only: %i[index update], module: :locations do
        collection do
          post :bulk_update
        end
      end
      resources :ingredients, only: %i[index create update destroy], module: :locations do
        member { post :adjust }
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
      resources :expense_categories do
        collection { patch :reorder }
      end
      resources :expenses
      resources :income_categories do
        collection { patch :reorder }
      end
      resources :incomes
      resources :discount_rules, except: [:show]
      resources :treasuries do
        member { post :adjust }
      end
      resources :treasury_transfers, only: %i[new create]
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

      get "payroll", to: "payroll#index"
      get "payroll/export", to: "payroll#export", as: :payroll_export
      get "monthly_payroll", to: "monthly_payroll#index"
      post "monthly_payroll/finalize_all", to: "monthly_payroll#finalize_all", as: :monthly_payroll_finalize_all
      get "monthly_payroll/export", to: "monthly_payroll#export", as: :monthly_payroll_export

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
      resources :ingredient_categories do
        collection { patch :reorder }
      end
      resources :ingredients do
        member { post :adjust }
        collection { get :low_stock }
        resources :recipes, only: %i[create destroy]
        resources :supplier_ingredients, only: %i[create update destroy]
      end
      resources :suppliers
      resources :vendor_invoices, only: %i[index show new create edit update] do
        member do
          post :record_payment
          patch :void
        end
      end
      resources :stock_takes, only: %i[index show create update] do
        member { post :complete }
      end
      resources :manufacturing_templates do
        member { post :run }
        resources :lines, only: %i[create destroy], controller: "manufacturing_template_lines"
      end
      resources :manufacturing_runs, only: %i[index show]
      namespace :reports do
        get :valuation
        get :variance
      end
    end
  end

  require "sidekiq/web"
  authenticate :user, ->(u) { u.owner? } do
    mount Sidekiq::Web => "/sidekiq"
  end
end
