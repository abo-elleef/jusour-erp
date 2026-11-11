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

    # The logo as printer bytes, or nil when there is none. Drawn once per process and
    # reused: the key is the upload's storage key (a new upload is a new key) or the
    # legacy URL, so a cached logo also skips the storage download.
    def escpos(location:, company:, doc_width:)
      key = cache_key(location: location, company: company)
      return nil unless key

      Printing::RasterCache.fetch("logo:#{key}:#{doc_width}") do
        with_source(location: location, company: company) do |source|
          source.present? ? Escpos::ArabicImageRenderer.render_logo(source, doc_width: doc_width) : nil
        end
      end
    end

    def cache_key(location:, company:)
      attachment = attachment_for(location: location, company: company)
      return "blob:#{attachment.blob.key}" if attachment

      url = Printing::Config.receipt_logo_url.presence
      url && "url:#{url}"
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
