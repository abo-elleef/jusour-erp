# frozen_string_literal: true

module Admin
  module Sales
    # The storefront home page builder: add predefined blocks, switch them on
    # and off, order them, and fill in their options. The first visit saves the
    # default layout, so admins start from what the site already shows.
    class StorefrontSectionsController < StorefrontBaseController
      before_action :set_storefront
      before_action :set_section, only: %i[edit update destroy toggle move remove_logo]

      def index
        ::StorefrontSection.seed_defaults!(@storefront)
        @sections = @storefront.sections.includes(image_attachment: :blob, logos_attachments: :blob).to_a
        @categories = IngredientCategory.active.ordered.index_by(&:id)
      end

      def create
        section = @storefront.sections.build(section_type: params[:section_type], position: next_position)
        section.assign_settings({})
        if section.save
          redirect_to edit_admin_sales_storefront_section_path(section), notice: t("sales.storefront_sections.flash.created")
        else
          redirect_to admin_sales_storefront_sections_path, alert: section.errors.full_messages.to_sentence
        end
      end

      def edit
        load_form_data
      end

      def update
        @section.assign_settings(settings_params)
        @section.enabled = ActiveModel::Type::Boolean.new.cast(params[:enabled]) if params.key?(:enabled)
        @section.image = params[:image] if params[:image].present? && @section.image?
        new_logos = Array(params[:logos]).compact_blank
        @section.logos = @section.ordered_logos.map(&:blob) + new_logos if new_logos.any? && @section.logos?

        if @section.save
          @section.image.purge_later if ActiveModel::Type::Boolean.new.cast(params[:remove_image]) && params[:image].blank?
          redirect_to edit_admin_sales_storefront_section_path(@section), notice: t("sales.storefront_sections.flash.updated")
        else
          load_form_data
          render :edit, status: :unprocessable_entity
        end
      end

      def destroy
        @section.destroy
        renumber!
        redirect_to admin_sales_storefront_sections_path, notice: t("sales.storefront_sections.flash.deleted")
      end

      def toggle
        @section.update!(enabled: !@section.enabled)
        redirect_to admin_sales_storefront_sections_path
      end

      # Up/down buttons — the touch-friendly twin of drag-and-drop.
      def move
        sections = @storefront.sections.to_a
        index = sections.index(@section)
        target = params[:direction] == "up" ? index - 1 : index + 1
        if target.between?(0, sections.size - 1)
          sections[index], sections[target] = sections[target], sections[index]
          renumber!(sections)
        end
        redirect_to admin_sales_storefront_sections_path
      end

      # Drag-and-drop (sortable-list controller) posts { positions: { id => index } }.
      def reorder
        positions = params[:positions].presence || JSON.parse(request.body.read).fetch("positions")
        positions = positions.to_unsafe_h if positions.respond_to?(:to_unsafe_h)
        # Only this storefront's blocks move; anything else in the payload is ignored.
        ids = @storefront.sections.pluck(:id)
        positions.each do |id, position|
          next unless ids.include?(id)

          ::StorefrontSection.where(id: id).update_all(position: position.to_i, updated_at: Time.current)
        end
        head :ok
      end

      def remove_logo
        @section.logos.find(params[:attachment_id]).purge_later
        redirect_to edit_admin_sales_storefront_section_path(@section), notice: t("sales.storefront_sections.flash.logo_removed")
      end

      private

      def set_storefront
        @storefront = ::Storefront.first
        return if @storefront

        redirect_to admin_sales_storefront_path, alert: t("sales.storefront_sections.flash.settings_first")
      end

      def set_section
        @section = @storefront.sections.find(params[:id])
      end

      def next_position
        @storefront.sections.maximum(:position).to_i + 1
      end

      def renumber!(ordered = @storefront.sections.reload.to_a)
        ordered.each_with_index do |section, index|
          section.update_columns(position: index) if section.position != index
        end
      end

      # Only the keys this block's schema declares (plus their Arabic twins).
      def settings_params
        keys = @section.fields.flat_map { |f| %i[text long_text].include?(f[:kind]) ? [f[:name], "#{f[:name]}_ar"] : [f[:name]] }
        params.fetch(:settings, {}).permit(*keys).to_h
      end

      def load_form_data
        @categories = IngredientCategory.active.ordered
      end
    end
  end
end
