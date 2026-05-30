# frozen_string_literal: true

module Admin
  class CustomersController < BaseController
    before_action :set_customer, only: %i[show edit update destroy]

    def index
      @q = Customer.ransack(params[:q])
      @pagy, @customers = pagy(:offset, @q.result.order(created_at: :desc), limit: 25)
      authorize Customer
    end

    def show
      authorize @customer
      @orders = @customer.orders.order(created_at: :desc).limit(50)
      @loyalty_transactions = @customer.loyalty_transactions.order(created_at: :desc).limit(20)
    end

    def new
      @customer = Customer.new
      authorize @customer
    end

    def create
      @customer = Customer.new(customer_params)
      authorize @customer
      if @customer.save
        redirect_to admin_customer_path(@customer), notice: "Customer created."
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit
      authorize @customer
    end

    def update
      authorize @customer
      if @customer.update(customer_params)
        redirect_to admin_customer_path(@customer), notice: "Customer updated."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      authorize @customer
      if @customer.orders.exists?
        redirect_to admin_customer_path(@customer),
                    alert: "Cannot delete a customer with orders. Their order history is kept."
        return
      end

      @customer.destroy
      redirect_to admin_customers_path, notice: "Customer removed."
    end

    private

    def set_customer
      @customer = Customer.find(params[:id])
    end

    def customer_params
      params.require(:customer).permit(:name, :email, :phone)
    end
  end
end
