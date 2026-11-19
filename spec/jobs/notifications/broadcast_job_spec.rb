# frozen_string_literal: true

require "rails_helper"

RSpec.describe Notifications::BroadcastJob, type: :job do
  let(:company) { create(:company) }
  let(:owner) { create(:user, :owner, company: company) }

  before { Current.company = company }

  def stream_for(user, locale)
    Turbo::StreamsChannel.send(:stream_name_from, Notifications::Broadcast.stream(user, locale))
  end

  def notify!(read_at: nil)
    Notification.create!(
      recipient: owner, company: company, notification_type: "sales", read_at: read_at,
      params: { message_key: "customer_invoice_payment_pending",
                message_params: { invoice_number: "INV-7", customer_invoice_id: 42 },
                customer_invoice_id: 42 }
    )
  end

  describe "the model callbacks" do
    it "enqueues a popup push when a notification is created" do
      expect { notify! }.to have_enqueued_job(described_class).with(owner.id, kind_of(String), popup: true)
    end

    it "enqueues a badge-only push when it is marked read" do
      notification = notify!
      expect { notification.mark_as_read! }
        .to have_enqueued_job(described_class).with(owner.id, notification.id, popup: false)
    end

    it "does not push when something other than read_at changes" do
      notification = notify!
      expect { notification.update!(notification_type: "inventory") }.not_to have_enqueued_job(described_class)
    end
  end

  describe "#perform" do
    it "pushes the badge and the popup card to every locale stream of the recipient" do
      notification = notify!

      I18n.available_locales.each do |locale|
        expect { described_class.perform_now(owner.id, notification.id, popup: true) }
          .to have_broadcasted_to(stream_for(owner, locale)).at_least(2).times
      end

      messages = ActionCable.server.pubsub.broadcasts(stream_for(owner, :en)).map { |m| JSON.parse(m) }.join
      expect(messages).to include(Notifications::Broadcast::BADGE_ID)
      expect(messages).to include(Notifications::Broadcast::POPUPS_ID)
      expect(messages).to include("INV-7")
      expect(messages).to include("/admin/notifications/#{notification.id}/open")
    end

    it "renders the card in each stream's own language" do
      notification = notify!
      described_class.perform_now(owner.id, notification.id, popup: true)

      ar = ActionCable.server.pubsub.broadcasts(stream_for(owner, :ar)).map { |m| JSON.parse(m) }.join
      expect(ar).to include(I18n.t("notifications.popup.open", locale: :ar))
    end

    it "counts only the recipient's unread notifications, even with no tenant set" do
      notify!
      notify!(read_at: Time.current)
      other = create(:user, :owner, company: company)
      Notification.create!(recipient: other, company: company, notification_type: "sales", params: {})
      Current.company = nil

      described_class.perform_now(owner.id)

      badge = ActionCable.server.pubsub.broadcasts(stream_for(owner, :en)).map { |m| JSON.parse(m) }.last
      expect(badge).to match(%r{>1</span>})
    end

    it "skips the popup for a notification already read by the time the job runs" do
      notification = notify!(read_at: Time.current)
      described_class.perform_now(owner.id, notification.id, popup: true)

      expect(ActionCable.server.pubsub.broadcasts(stream_for(owner, :en))).to be_empty
    end
  end
end
