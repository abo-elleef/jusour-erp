# frozen_string_literal: true

module Admin
  module Accounting
    # Every drawer shortage the accountant moved from one staff member to
    # another (DrawerShortageReassignment), with the reason. Under Reports hub →
    # Staff, authorized as payroll:view through AccountingNav like its siblings.
    #
    # Filtered by the drawer's day (the payroll month a shortage lands in), by
    # branch and by staff member (either side of the move). A per-person summary
    # sits above the paginated list of moves.
    class ShortageMovesReportsController < BaseController
      SORTABLE = {
        "date" => "cash_drawer_sessions.session_date",
        "amount" => "drawer_shortage_reassignments.amount_cents",
        "moved_at" => "drawer_shortage_reassignments.created_at"
      }.freeze

      def index
        parse_date_range(default_start: Date.current.beginning_of_month)
        @locations = Location.active.branches.ordered
        @location = @locations.find { |l| l.id == params[:location_id] }
        @staff = User.where(id: DrawerShortageReassignment.select(:from_user_id))
                     .or(User.where(id: DrawerShortageReassignment.select(:to_user_id))).order(:name)
        @user = User.find_by(id: params[:user_id]) if params[:user_id].present?
        @sort = SORTABLE.key?(params[:sort]) ? params[:sort] : "date"
        @sort_direction = params[:direction] == "asc" ? "asc" : "desc"

        scope = filtered_scope
        @total_count = scope.count
        @total_cents = scope.sum(:amount_cents)
        @people = per_person(scope)
        ordered = scope.includes(:from_user, :to_user, :reassigned_by, :old_voucher, :new_voucher, cash_drawer_session: %i[location treasury])
                       .reorder(Arel.sql("#{SORTABLE[@sort]} #{@sort_direction}, drawer_shortage_reassignments.created_at DESC"))
        @pagy, @moves = pagy(:offset, ordered, limit: 50)
      end

      private

      def filtered_scope
        scope = DrawerShortageReassignment.joins(:cash_drawer_session)
                                          .where(cash_drawer_sessions: { session_date: @start_date..@end_date })
        scope = scope.where(cash_drawer_sessions: { location_id: @location.id }) if @location
        scope = scope.where(from_user_id: @user.id).or(scope.where(to_user_id: @user.id)) if @user
        scope
      end

      Person = Struct.new(:user, :off_count, :off_cents, :onto_count, :onto_cents, keyword_init: true) do
        # Positive: this person carries more shortage than before the moves.
        def net_cents = onto_cents - off_cents
      end

      def per_person(scope)
        off = scope.group(:from_user_id).pluck(:from_user_id, Arel.sql("COUNT(*)"), Arel.sql("SUM(amount_cents)"))
        onto = scope.group(:to_user_id).pluck(:to_user_id, Arel.sql("COUNT(*)"), Arel.sql("SUM(amount_cents)"))
        users = User.where(id: (off.map(&:first) + onto.map(&:first)).uniq).index_by(&:id)
        people = Hash.new { |h, id| h[id] = Person.new(user: users[id], off_count: 0, off_cents: 0, onto_count: 0, onto_cents: 0) }
        off.each { |id, count, cents| people[id].off_count = count; people[id].off_cents = cents.to_i }
        onto.each { |id, count, cents| people[id].onto_count = count; people[id].onto_cents = cents.to_i }
        people.values.sort_by { |p| [-p.net_cents.abs, p.user.name] }
      end
    end
  end
end
