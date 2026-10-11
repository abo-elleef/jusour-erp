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

  validates :name, presence: true
  validate :phone_or_email_present
  validates :source, inclusion: { in: SOURCES }, allow_blank: true
  validates :stage, inclusion: { in: STAGES }
  validates :lost_reason, inclusion: { in: LOST_REASONS }, allow_blank: true
  validate :lost_reason_required_when_lost

  scope :open_leads, -> { where.not(stage: TERMINAL_STAGES) }
  scope :due_for_follow_up, -> { open_leads.where(next_follow_up_at: ..Date.current) }

  def self.ransackable_attributes(_auth_object = nil)
    %w[name phone email stage source created_at]
  end

  def open?      = TERMINAL_STAGES.exclude?(stage)
  def converted? = stage == "converted"
  def lost?      = stage == "lost"

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
      new_customer = Customer.create!(
        name: name, phone: phone, phone_secondary: phone_secondary, email: email,
        customer_type: customer_type, originating_lead: self
      )
      update!(stage: "converted", customer: new_customer, converted_at: Time.current)
      log_activity!(by, "stage_change", I18n.t("sales.leads.activity.converted", customer: new_customer.name))
      new_customer
    end
  end

  def mark_lost!(by:, lost_reason:, lost_reason_note: nil)
    update!(stage: "lost", lost_reason: lost_reason, lost_reason_note: lost_reason_note, lost_at: Time.current)
    log_activity!(by, "stage_change", I18n.t("sales.leads.activity.lost",
      reason: I18n.t("sales.leads.lost_reasons.#{lost_reason}", default: lost_reason)))
  end

  private

  def default_assigned_user
    self.assigned_user_id ||= created_by_id
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

  def log_activity!(user, activity_type, note)
    lead_activities.create!(user: user, activity_type: activity_type, occurred_at: Time.current, note: note)
  end

  def stage_label(stage)
    I18n.t("sales.leads.stages.#{stage}", default: stage.to_s)
  end
end
