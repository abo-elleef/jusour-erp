# frozen_string_literal: true

Rails.application.routes.draw do
  devise_for :users

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
    get "modifier_form", to: "order_items#modifier_form", as: :modifier_form
    resources :orders, only: %i[index show]
    resources :order_items, only: %i[create update destroy]
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

  namespace :customers do
    get "search", to: "search#index"
  end

  get "receipts/:token", to: "receipts#show", as: :receipt

  namespace :admin do
    root "dashboard#index"
    resources :categories do
      patch :reorder, on: :collection
    end
    resources :menu_items, except: [:show]
    resources :combos
    resources :discount_rules
    resources :customers
    resources :users, except: [:show]
    resources :orders, only: %i[index show] do
      member do
        post :void
        post :refund
      end
    end

    resources :notifications, only: [:index] do
      member { patch :mark_read }
      collection { patch :mark_all_read }
    end

    namespace :inventory do
      resources :ingredients do
        member { post :adjust }
        collection { get :low_stock }
        resources :recipes, only: %i[create destroy]
        resources :supplier_ingredients, only: %i[create update destroy]
      end
      resources :suppliers
      resources :purchase_orders do
        member { patch :send_to_supplier }
        collection { get :suggestions }
        resource :delivery, only: %i[new create], controller: "deliveries"
      end
      resources :stock_takes, only: %i[index show create update] do
        member { post :complete }
      end
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
