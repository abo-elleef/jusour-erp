# frozen_string_literal: true

module Printing
  # Picks the logo for a receipt: the branch's own upload, else the company's
  # upload, else the legacy `receipt_logo_url` setting, else nothing.
  module ReceiptLogo
    module_function

    # The uploaded attachment to use, or nil when neither level has one.
    def attachment_for(location:, company:)
      [location, company&.company_setting].each do |owner|
        logo = owner&.receipt_logo
        return logo if logo&.attached?
      end
      nil
    end

    # Yields something ImageMagick can read (a local file path or a URL), or nil
    # when there is no logo. The file exists only for the duration of the block.
    # A missing or unreadable upload never stops a receipt from printing.
    def with_source(location:, company:)
      attachment = attachment_for(location: location, company: company)
      if attachment
        begin
          attachment.blob.open { |file| return yield(file.path) }
        rescue ActiveStorage::FileNotFoundError => e
          Rails.logger.warn("[ReceiptLogo] upload missing in storage: #{e.message}")
        end
      end

      yield Printing::Config.receipt_logo_url.presence
    end
  end
end
