# frozen_string_literal: true

# A prospect in the distribution sales funnel. Tracks where a lead sits, who owns
# following up with them, and (if lost) why they didn't buy — the funnel/drop-off
# reporting reads straight off `stage`/`lost_reason`. Converting creates a real
# Customer (see #convert!); a Lead never gets AR/billing state of its own.
#
# Every transition below takes `by:` (the acting user) explicitly, rather than
# reading an ambient "current user" — it's what gets attributed in the
# LeadActivity timeline, and keeps the model testable without request state.
class Lead < ApplicationRecord
  include Tenantable
  include ContactPhones

  audited associated_with: :company

  SOURCES = %w[referral walk_in call_in social_media other].freeze
  STAGES = %w[new contacted qualified proposal_sent negotiation converted lost].freeze
  TERMINAL_STAGES = %w[converted lost].freeze
  LOST_REASONS = %w[price no_budget chose_competitor unresponsive not_a_fit other].freeze

  INDEX_SORTABLE_COLUMNS = %w[name stage assigned_user next_follow_up_at created_at].freeze
  INDEX_DEFAULT_SORT = "created_at"
  INDEX_DEFAULT_SORT_DIRECTION = "desc"

  belongs_to :location, optional: true
  belongs_to :assigned_user, class_name: "User"
  belongs_to :created_by, class_name: "User"
  belongs_to :customer, optional: true
  has_many :lead_activities, -> { order(occurred_at: :desc) }, dependent: :destroy

  before_validation :default_assigned_user, on: :create
  before_validation :default_next_follow_up, on: :create

  validates :name, presence: true
  validate :phone_or_email_present
  validates :source, inclusion: { in: SOURCES }, allow_blank: true
  validates :stage, inclusion: { in: STAGES }
  validates :lost_reason, inclusion: { in: LOST_REASONS }, allow_blank: true
  validate :lost_reason_required_when_lost
  validate :phones_not_used_by_another_lead_or_customer

  scope :open_leads, -> { where.not(stage: TERMINAL_STAGES) }
  scope :due_for_follow_up, -> { open_leads.where(next_follow_up_at: ..Date.current) }

  def self.ransackable_attributes(_auth_object = nil)
    %w[name phone email stage source created_at]
  end

  # Follow-up cadence (company settings, see Setting.lead_first_follow_up_days /
  # .lead_follow_up_every_days). nil when that part is turned off.
  def self.first_follow_up_date(from = Date.current)
    days = Setting.lead_first_follow_up_days
    from.to_date + days if days.positive?
  end

  def self.next_follow_up_date_after(contact_on)
    days = Setting.lead_follow_up_every_days
    contact_on.to_date + days if days.positive?
  end

  def open?      = TERMINAL_STAGES.exclude?(stage)
  def converted? = stage == "converted"
  def lost?      = stage == "lost"

  def follow_up_overdue?   = open? && next_follow_up_at.present? && next_follow_up_at < Date.current
  def follow_up_due_today? = open? && next_follow_up_at == Date.current

  # Moves the lead to any non-terminal stage (new/contacted/qualified/
  # proposal_sent/negotiation). Use #convert!/#mark_lost! for the terminal ones.
  def change_stage!(new_stage, by:)
    raise ArgumentError, "use convert!/mark_lost! for terminal stages" if TERMINAL_STAGES.include?(new_stage)

    from = stage
    update!(stage: new_stage)
    log_activity!(by, "stage_change", I18n.t("sales.leads.activity.stage_changed",
      from: stage_label(from), to: stage_label(new_stage)))
  end

  def reassign!(to:, by:)
    from = assigned_user
    update!(assigned_user: to)
    log_activity!(by, "assignment_change", I18n.t("sales.leads.activity.reassigned",
      from: from&.name || I18n.t("sales.leads.activity.nobody"), to: to.name))
  end

  # Creates the real Customer this lead has been chasing, and marks the lead
  # converted. Deterministic — no fuzzy matching against existing customers.
  def convert!(by:, customer_type: "regular")
    return customer if converted?

    transaction do
      # The lead's phones were already accepted on the lead (maybe before the
      # 11-digit rule existed), so the length rule must not block the sale here.
      new_customer = Customer.create!(
        name: name, phone: phone, phone_secondary: phone_secondary, email: email,
        customer_type: customer_type, originating_lead: self, skip_phone_length_check: true,
        assigned_user: assigned_user
      )
      update!(stage: "converted", customer: new_customer, converted_at: Time.current, next_follow_up_at: nil)
      log_activity!(by, "stage_change", I18n.t("sales.leads.activity.converted", customer: new_customer.name))
      new_customer
    end
  end

  def mark_lost!(by:, lost_reason:, lost_reason_note: nil)
    update!(stage: "lost", lost_reason: lost_reason, lost_reason_note: lost_reason_note, lost_at: Time.current,
      next_follow_up_at: nil)
    log_activity!(by, "stage_change", I18n.t("sales.leads.activity.lost",
      reason: I18n.t("sales.leads.lost_reasons.#{lost_reason}", default: lost_reason)))
  end

  private

  def default_assigned_user
    self.assigned_user_id ||= created_by_id
  end

  # The form pre-fills this too; this covers leads created elsewhere (imports,
  # console) and a form submitted with the date cleared. Terminal leads (a lead
  # created already converted/lost) need no follow-up.
  def default_next_follow_up
    return if next_follow_up_at.present? || !open?

    self.next_follow_up_at = self.class.first_follow_up_date(created_at || Date.current)
  end

  def phone_or_email_present
    return if phone.present? || email.present?

    errors.add(:base, I18n.t("sales.leads.errors.phone_or_email_required"))
  end

  def lost_reason_required_when_lost
    return unless stage == "lost"
    return if lost_reason.present?

    errors.add(:lost_reason, I18n.t("sales.leads.errors.lost_reason_required"))
  end

  # One phone number, one lead: neither of this lead's phones may match another
  # lead's phone or phone_secondary (lost and converted leads included), nor a
  # customer's — that person is already a customer, so the rep logs the contact
  # on the customer instead. Each error carries the clashing record as
  # `conflict:` so the form can link to it. Runs only for a phone being set or
  # changed, so old duplicates don't lock anyone out of editing other fields.
  def phones_not_used_by_another_lead_or_customer
    return if company_id.blank?

    contact_phone_columns_to_check.each do |column|
      number = self[column]
      if (lead = lead_with_phone(number))
        errors.add(column, I18n.t("sales.leads.errors.phone_used_by_lead", phone: number, name: lead.name),
          conflict: lead)
      elsif (customer = customer_with_phone(number))
        errors.add(column, I18n.t("sales.leads.errors.phone_used_by_customer", phone: number,
          name: customer.display_name), conflict: customer)
      end
    end
  end

  def lead_with_phone(number)
    scope = Lead.unscoped_by_company.where(company_id: company_id)
    scope = scope.where.not(id: id) if persisted?
    with_phone(scope, number).order(:id).first
  end

  # A converted lead shares its numbers with the customer it became; that one
  # customer is not a clash.
  def customer_with_phone(number)
    scope = Customer.unscoped_by_company.where(company_id: company_id)
    scope = scope.where.not(id: customer_id) if customer_id.present?
    scope = scope.where("customers.originating_lead_id IS NULL OR customers.originating_lead_id <> ?", id) if persisted?
    with_phone(scope, number).order(:id).first
  end

  def with_phone(scope, number)
    table = scope.klass.table_name
    scope.where(
      "#{scope.klass.normalized_phone_sql("#{table}.phone")} = :number OR " \
      "#{scope.klass.normalized_phone_sql("#{table}.phone_secondary")} = :number",
      number: number
    )
  end

  def log_activity!(user, activity_type, note)
    lead_activities.create!(user: user, activity_type: activity_type, occurred_at: Time.current, note: note)
  end

  def stage_label(stage)
    I18n.t("sales.leads.stages.#{stage}", default: stage.to_s)
  end
end
