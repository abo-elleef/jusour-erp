# frozen_string_literal: true

# A customer complaint / satisfaction case, opened by staff on the customer's
# behalf (Bazzar slice G1 — no customer-facing filing). Optionally tied to one
# of the customer's invoices and, as a plain reference, to a credit note: a
# ticket never moves money — refunds stay with credit notes and vouchers.
#
# Status flow: open → in_progress → resolved → closed, plus reopen (resolved
# or closed back to open). Anyone with tickets:manage moves a ticket up to
# resolved; closing and reopening — and reassigning — need tickets:assign (or
# the owner). Every change goes through #change_status! / #reassign! /
# #add_comment!, which take the acting user explicitly (as Lead's transitions
# do), write the system entry on the ticket's own timeline, and notify.
#
# Who may see which ticket lives in Sales::OwnershipScope (#tickets).
class Ticket < ApplicationRecord
  include Tenantable

  audited associated_with: :company

  MANAGE_PERMISSION = "tickets:manage"
  ASSIGN_PERMISSION = "tickets:assign"

  PRIORITIES = %w[low normal urgent].freeze
  STATUSES = %w[open in_progress resolved closed].freeze
  ACTIVE_STATUSES = %w[open in_progress].freeze
  # Where each status may go next. "open" from resolved/closed is a reopen.
  TRANSITIONS = {
    "open" => %w[in_progress resolved closed],
    "in_progress" => %w[resolved closed],
    "resolved" => %w[closed open],
    "closed" => %w[open]
  }.freeze
  # Moves only a tickets:assign holder (or the owner) may make.
  MANAGER_ONLY_TARGETS = %w[closed open].freeze

  INDEX_SORTABLE_COLUMNS = %w[number subject customer status priority assigned_user created_at updated_at].freeze
  INDEX_DEFAULT_SORT = "created_at"
  INDEX_DEFAULT_SORT_DIRECTION = "desc"

  # Advisory-lock namespace for numbering (Order uses 8_301/8_302).
  NUMBER_LOCK_NAMESPACE = 8_303

  class NotAllowed < StandardError; end

  belongs_to :customer
  belongs_to :customer_invoice, optional: true
  belongs_to :credit_note, optional: true
  belongs_to :ticket_category, optional: true
  belongs_to :assigned_user, class_name: "User", optional: true
  belongs_to :opened_by, class_name: "User"
  has_many :comments, -> { chronological }, class_name: "TicketComment", inverse_of: :ticket, dependent: :destroy
  has_many :customer_activities, dependent: :nullify

  has_many_attached :images

  before_validation :default_assigned_user, on: :create
  before_create :assign_number
  after_create :record_opened

  validates :subject, presence: true, length: { maximum: 200 }
  validates :priority, inclusion: { in: PRIORITIES }
  validates :status, inclusion: { in: STATUSES }
  validate :links_belong_to_customer
  validate :images_acceptable

  scope :active, -> { where(status: ACTIVE_STATUSES) }

  # Owner, or tickets:assign — reassigns, closes, reopens, sees every ticket.
  def self.manager?(user)
    user.present? && (user.owner? || user.can?(ASSIGN_PERMISSION))
  end

  # Opens tickets, comments, moves them up to resolved.
  def self.worker?(user)
    manager?(user) || user&.can?(MANAGE_PERMISSION) == true
  end

  def self.display_number(number) = format("T-%04d", number.to_i)

  def display_number = self.class.display_number(number)

  def active? = ACTIVE_STATUSES.include?(status)
  def closed? = status == "closed"
  def resolved? = status == "resolved"

  def can_move_to?(to, user)
    return false unless TRANSITIONS.fetch(status, []).include?(to)

    MANAGER_ONLY_TARGETS.include?(to) ? self.class.manager?(user) : self.class.worker?(user)
  end

  # The moves this user can make from here, in display order.
  def next_statuses_for(user)
    TRANSITIONS.fetch(status, []).select { |to| can_move_to?(to, user) }
  end

  def change_status!(to, by:, note: nil)
    raise NotAllowed, "#{status} → #{to}" unless can_move_to?(to, by)

    from = status
    transaction do
      update!(status_attributes(to))
      comments.create!(user: by, kind: "status_change", body: note.to_s.strip.presence,
        data: { "from" => from, "to" => to })
      activity = { "resolved" => "ticket_resolved", "closed" => "ticket_closed", "open" => "ticket_reopened" }[to]
      log_customer_activity!(by, activity) if activity
    end
    Tickets::NotifyService.resolved(self, by: by) if to == "resolved"
    self
  end

  def reassign!(to:, by:)
    raise NotAllowed, "reassign" unless self.class.manager?(by)
    return self if to&.id == assigned_user_id

    from = assigned_user
    transaction do
      update!(assigned_user: to)
      comments.create!(user: by, kind: "assignment_change",
        data: { "from_id" => from&.id, "from_name" => from&.name, "to_id" => to&.id, "to_name" => to&.name })
    end
    Tickets::NotifyService.assigned(self, by: by) if to
    self
  end

  def add_comment!(by:, body:, images: [])
    raise NotAllowed, "comment" unless self.class.worker?(by)

    comment = comments.build(user: by, kind: "comment", body: body.to_s.strip.presence)
    comment.images.attach(Array(images).compact_blank)
    comment.save!
    Tickets::NotifyService.commented(self, comment, by: by)
    comment
  end

  def self.ransackable_attributes(_auth_object = nil)
    %w[number subject status priority created_at]
  end

  private

  def status_attributes(to)
    case to
    when "resolved" then { status: to, resolved_at: Time.current }
    when "closed" then { status: to, closed_at: Time.current, resolved_at: resolved_at || Time.current }
    when "open" then { status: to, resolved_at: nil, closed_at: nil }
    else { status: to }
    end
  end

  # Nobody picked: the category's default handler, if it still works here.
  def default_assigned_user
    return if assigned_user_id.present?

    handler = ticket_category&.default_handler
    self.assigned_user = handler if handler&.active?
  end

  # Sequential per company (T-0001, T-0002, ...). The advisory lock serialises
  # two people opening a ticket at the same moment, who would otherwise both
  # read the same maximum — the same approach as Order#assign_order_number.
  # Released when the transaction ends; the unique index is the backstop.
  def assign_number
    return if number.present?

    key = Zlib.crc32("tickets:#{company_id}")
    key -= 2**32 if key >= 2**31 # pg_advisory_xact_lock takes a signed int4
    self.class.connection.execute("SELECT pg_advisory_xact_lock(#{NUMBER_LOCK_NAMESPACE}, #{key})")
    self.number = Ticket.unscoped.where(company_id: company_id).maximum(:number).to_i + 1
  end

  def record_opened
    log_customer_activity!(opened_by, "ticket_opened")
    Tickets::NotifyService.assigned(self, by: opened_by) if assigned_user
  end

  def log_customer_activity!(user, activity_type)
    CustomerActivity.create!(customer: customer, ticket: self, user: user, activity_type: activity_type,
      note: "#{display_number} · #{subject}")
  end

  def links_belong_to_customer
    if customer_invoice && customer_invoice.customer_id != customer_id
      errors.add(:customer_invoice, :not_this_customer)
    end
    return unless credit_note && credit_note.customer_id != customer_id

    errors.add(:credit_note, :not_this_customer)
  end

  def images_acceptable
    TicketImages.validate(self, images)
  end
end
