# frozen_string_literal: true

require "open3"
require "base64"

module Printing
  module Escpos
    # Renders Arabic text (and logos) as ESC/POS raster image bytes.
    #
    # Thermal printers cannot shape Arabic letters internally — each character
    # prints as an isolated glyph. The only reliable fix is to render text as
    # a bitmap using the OS font stack (which handles Arabic joining and RTL),
    # then send the bitmap via the ESC/POS GS v 0 raster image command.
    #
    # NOTE: All methods are declared with module_function (including helpers).
    # Using `private` after `module_function` would make helpers instance-only,
    # so they would be unreachable when called from module-level singleton methods.
    module ArabicImageRenderer
      PAPER_PX_WIDTH = { 42 => 576, 32 => 384 }.freeze
      FONT_SIZE_PT   = 26

      CANDIDATE_FONTS = [
        # Bundled fallback — drop NotoNaskhArabic-Regular.ttf into vendor/fonts/
        Rails.root.join("vendor/fonts/NotoNaskhArabic-Regular.ttf").to_s,
        # Linux — apt-get install fonts-noto-core
        "/usr/share/fonts/truetype/noto/NotoNaskhArabic-Regular.ttf",
        "/usr/share/fonts/opentype/noto/NotoNaskhArabic-Regular.otf",
        "/usr/share/fonts/truetype/fonts-arabeyes/ae_AlArabiya.ttf",
        "/usr/share/fonts/truetype/freefont/FreeSans.ttf",
        # macOS
        "/System/Library/Fonts/Supplemental/Al Nile.ttc",
        "/Library/Fonts/Arial Unicode.ttf",
        "/System/Library/Fonts/Supplemental/GeezaPro.ttc"
      ].freeze

      module_function

      # ── Public API ────────────────────────────────────────────────────────

      # Returns raw ESC/POS bytes for a single Arabic text line.
      # align: :left | :center | :right
      # font_scale: 2 doubles the point size — the printer's double-size command
      # only enlarges built-in text, never a raster image.
      def render_line(text, doc_width: 42, align: :right, font_scale: 1)
        px_width = PAPER_PX_WIDTH.fetch(doc_width, 576)
        font     = arabic_font
        return nil unless font

        gravity = { left: "West", center: "Center", right: "East" }.fetch(align, "East")
        pbm     = render_pbm_single(text.to_s.strip, gravity, px_width, font, pt: (FONT_SIZE_PT * font_scale).to_i)
        pbm ? pbm_to_escpos(pbm) : nil
      end

      # Returns raw ESC/POS bytes for a receipt row as a single image:
      # Arabic label on the right, LTR value (price/qty) on the left.
      def render_row(arabic_label, ltr_value, doc_width: 42)
        px_width = PAPER_PX_WIDTH.fetch(doc_width, 576)
        font     = arabic_font
        return nil unless font

        pbm = render_pbm_multi(
          [
            { gravity: "West", offset: "+8+0", text: ltr_value.to_s },
            { gravity: "East", offset: "+8+0", text: arabic_label.to_s.strip }
          ],
          px_width, font
        )
        pbm ? pbm_to_escpos(pbm) : nil
      end

      # Returns raw ESC/POS bytes for a logo image.
      # source: file path or HTTP(S) URL.
      def render_logo(source, doc_width: 42)
        return nil if source.blank?

        px_width = PAPER_PX_WIDTH.fetch(doc_width, 576)
        cmd = [
          im_command, source.to_s,
          "-resize", "#{px_width}x#{px_width / 2}>",
          "-gravity", "Center",
          "-background", "white",
          "-extent", "#{px_width}x",
          "-type", "Bilevel",
          "pbm:-"
        ]
        stdout, _stderr, status = Open3.capture3(*cmd)
        stdout = stdout.b
        return nil unless status.success? && stdout.start_with?("P4".b)

        pbm_to_escpos(stdout)
      end

      # Returns the path to the first usable Arabic font, or nil.
      def arabic_font
        override = Printing::Config.arabic_font_path
        return override if override.present? && File.exist?(override)

        CANDIDATE_FONTS.find { |f| File.exist?(f) }
      end

      # Returns raw ESC/POS bytes for a 3-column receipt row (image mode).
      # item_name_visual: already reshaped+bidi-processed Arabic label
      # qty_str:          plain quantity string ("1", "2" …)
      # price_str:        price string ("ج.م.130.00" …)
      # Layout: [price — West] [qty — center-left] [item name — East]
      def render_row3(item_name_visual, qty_str, price_str, doc_width: 42)
        px_width = PAPER_PX_WIDTH.fetch(doc_width, 576)
        qty_x    = (px_width * 0.26).to_i
        sep1     = qty_x - 12              # vertical divider: price | qty
        sep2     = (px_width * 0.46).to_i  # vertical divider: qty | item name
        h        = FONT_SIZE_PT * 2
        # All columns right-aligned (East gravity). Offset = distance from right edge.
        # Text right edge sits 8px inside each column's right boundary.
        price_rx = px_width - sep1 + 8    # price col right edge → from paper right
        qty_rx   = px_width - sep2 + 8    # qty col right edge → from paper right
        font     = arabic_font
        return nil unless font

        pbm = render_pbm_multi(
          [
            { gravity: "East", offset: "+#{price_rx}+0", text: price_str },
            { gravity: "East", offset: "+#{qty_rx}+0",   text: qty_str },
            { gravity: "East", offset: "+8+0",            text: item_name_visual },
            { draw: "line #{sep1},0 #{sep1},#{h}" },
            { draw: "line #{sep2},0 #{sep2},#{h}" }
          ],
          px_width, font
        )
        pbm ? pbm_to_escpos(pbm) : nil
      end

      # ── PNG preview variants (for browser debug view) ─────────────────────

      # Same as render_line but returns a Base64-encoded PNG string.
      # font_scale: 2 doubles the point size (used for ESC/POS double-height text preview).
      def render_png(text, doc_width: 42, align: :right, font_scale: 1)
        px_width = PAPER_PX_WIDTH.fetch(doc_width, 576)
        font     = arabic_font
        return nil unless font

        pt      = (FONT_SIZE_PT * font_scale).to_i
        gravity = { left: "West", center: "Center", right: "East" }.fetch(align, "East")
        run_to_png([
          im_command,
          "-size", "#{px_width}x#{pt * 2}", "xc:white",
          "-font", font, "-pointsize", pt.to_s, "-fill", "black",
          "-gravity", gravity, "-annotate", "+0+0", text.to_s.strip
        ])
      end

      # Same as render_row but returns a Base64-encoded PNG string.
      def render_row_png(arabic_label, ltr_value, doc_width: 42)
        px_width = PAPER_PX_WIDTH.fetch(doc_width, 576)
        font     = arabic_font
        return nil unless font

        run_to_png([
          im_command,
          "-size", "#{px_width}x#{FONT_SIZE_PT * 2}", "xc:white",
          "-font", font, "-pointsize", FONT_SIZE_PT.to_s, "-fill", "black",
          "-gravity", "West", "-annotate", "+8+0", ltr_value.to_s,
          "-gravity", "East", "-annotate", "+8+0", arabic_label.to_s.strip
        ])
      end

      # Same as render_row3 but returns a Base64-encoded PNG string.
      def render_row3_png(item_name_visual, qty_str, price_str, doc_width: 42)
        px_width = PAPER_PX_WIDTH.fetch(doc_width, 576)
        qty_x    = (px_width * 0.26).to_i
        sep1     = qty_x - 12
        sep2     = (px_width * 0.46).to_i
        h        = FONT_SIZE_PT * 2
        price_rx = px_width - sep1 + 8
        qty_rx   = px_width - sep2 + 8
        font     = arabic_font
        return nil unless font

        run_to_png([
          im_command,
          "-size", "#{px_width}x#{h}", "xc:white",
          "-font", font, "-pointsize", FONT_SIZE_PT.to_s, "-fill", "black",
          "-gravity", "East", "-annotate", "+#{price_rx}+0", price_str,
          "-gravity", "East", "-annotate", "+#{qty_rx}+0",   qty_str,
          "-gravity", "East", "-annotate", "+8+0",            item_name_visual,
          "-draw", "line #{sep1},0 #{sep1},#{h}",
          "-draw", "line #{sep2},0 #{sep2},#{h}"
        ])
      end

      # Modifier/notes continuation row: text in the item-name column only,
      # with the same vertical column separators as a regular row3 image.
      def render_modifier_row(visual_text, doc_width: 42, columns: 3)
        px_width = PAPER_PX_WIDTH.fetch(doc_width, 576)
        h        = FONT_SIZE_PT * 2
        font     = arabic_font
        return nil unless font

        draws = [{ gravity: "East", offset: "+8+0", text: visual_text }]
        if columns == 3
          qty_x = (px_width * 0.26).to_i
          sep1  = qty_x - 12
          sep2  = (px_width * 0.46).to_i
          draws << { draw: "line #{sep1},0 #{sep1},#{h}" }
          draws << { draw: "line #{sep2},0 #{sep2},#{h}" }
        end

        pbm = render_pbm_multi(draws, px_width, font)
        pbm ? pbm_to_escpos(pbm) : nil
      end

      # Same as render_modifier_row but returns a Base64-encoded PNG string.
      def render_modifier_row_png(visual_text, doc_width: 42, columns: 3)
        px_width = PAPER_PX_WIDTH.fetch(doc_width, 576)
        h        = FONT_SIZE_PT * 2
        font     = arabic_font
        return nil unless font

        cmd = [
          im_command,
          "-size", "#{px_width}x#{h}", "xc:white",
          "-font", font, "-pointsize", FONT_SIZE_PT.to_s, "-fill", "black",
          "-gravity", "East", "-annotate", "+8+0", visual_text
        ]
        if columns == 3
          qty_x = (px_width * 0.26).to_i
          sep1  = qty_x - 12
          sep2  = (px_width * 0.46).to_i
          cmd += ["-draw", "line #{sep1},0 #{sep1},#{h}", "-draw", "line #{sep2},0 #{sep2},#{h}"]
        end
        run_to_png(cmd)
      end

      # Full-width 1px horizontal rule as ESC/POS bytes — used between table rows.
      def render_separator(doc_width: 42)
        px_width = PAPER_PX_WIDTH.fetch(doc_width, 576)
        pbm = capture_pbm([im_command, "-size", "#{px_width}x2", "xc:white",
                           "-draw", "line 0,0 #{px_width},0",
                           "-type", "Bilevel", "pbm:-"])
        pbm ? pbm_to_escpos(pbm) : nil
      end

      # Same as render_separator but returns a Base64-encoded PNG string.
      def render_separator_png(doc_width: 42)
        px_width = PAPER_PX_WIDTH.fetch(doc_width, 576)
        run_to_png([im_command, "-size", "#{px_width}x2", "xc:white",
                    "-draw", "line 0,0 #{px_width},0"])
      end

      # Same as render_logo but returns a Base64-encoded PNG string.
      def render_logo_png(source, doc_width: 42)
        return nil if source.blank?

        px_width = PAPER_PX_WIDTH.fetch(doc_width, 576)
        run_to_png([
          im_command, source.to_s,
          "-resize", "#{px_width}x#{px_width / 2}>",
          "-gravity", "Center",
          "-background", "white",
          "-extent", "#{px_width}x"
        ])
      end

      # ── Internal helpers (module_function so they're callable from above) ──

      # Auto-detect ImageMagick v7 (`magick`) vs v6 (`convert`).
      def im_command
        return @_im_command if defined?(@_im_command)

        @_im_command = system("which magick > /dev/null 2>&1") ? "magick" : "convert"
      end

      # Single text annotation → PBM binary.
      def render_pbm_single(text, gravity, px_width, font, pt: FONT_SIZE_PT)
        cmd = [
          im_command,
          "-size", "#{px_width}x#{pt * 2}", "xc:white",
          "-font", font, "-pointsize", pt.to_s, "-fill", "black",
          "-gravity", gravity, "-annotate", "+0+0", text,
          "-type", "Bilevel", "pbm:-"
        ]
        capture_pbm(cmd)
      end

      # Multiple text annotations (and optional draw commands) in one image → PBM binary.
      # Each entry is either:
      #   { gravity:, offset:, text: }  — text annotation
      #   { draw: "line x1,y1 x2,y2" } — raw ImageMagick -draw primitive
      def render_pbm_multi(annotations, px_width, font)
        cmd = [
          im_command,
          "-size", "#{px_width}x#{FONT_SIZE_PT * 2}", "xc:white",
          "-font", font, "-pointsize", FONT_SIZE_PT.to_s, "-fill", "black"
        ]
        annotations.each do |ann|
          if ann[:draw]
            cmd += ["-draw", ann[:draw]]
          else
            cmd += ["-gravity", ann[:gravity], "-annotate", ann.fetch(:offset, "+0+0"), ann[:text]]
          end
        end
        cmd += ["-type", "Bilevel", "pbm:-"]

        capture_pbm(cmd)
      end

      # Runs an ImageMagick command that writes a PBM to stdout; returns the PBM or nil.
      # The command is the cache key: it holds the text, the font, the size and the
      # layout, so the same command always draws the same picture.
      #
      # Inside `prefetch` nothing is drawn: the command is noted and a blank stand-in
      # comes back, so the document takes the same path it will take for real.
      def capture_pbm(cmd)
        key = cmd.join("\u0000")
        if (pending = Thread.current[:escpos_prefetch])
          pending[key] ||= cmd unless Printing::RasterCache.key?(key)
          return PREFETCH_STAND_IN
        end

        Printing::RasterCache.fetch(key) do
          stdout, _stderr, status = Open3.capture3(*cmd)
          stdout = stdout.b
          status.success? && stdout.start_with?("P4".b) ? stdout : nil
        end
      end

      PREFETCH_STAND_IN = "P4\n8 1\n\x00".b.freeze
      BATCH_SUFFIX      = %w[-type Bilevel pbm:-].freeze
      BATCH_SIZE        = 40

      # Draws every image a document needs in one ImageMagick run instead of one run
      # per line (each run costs ~0.3s on a Heroku dyno). The block composes the
      # document once with drawing switched off, which lists the images that are not
      # cached yet; those are drawn together and cached, so composing the document
      # again afterwards only reads the cache. The block's own result is thrown away.
      #
      # Anything the batch cannot account for is simply left uncached, and the real
      # build draws it one by one exactly as before, failures and fallbacks included.
      def prefetch
        return unless Printing::RasterCache.enabled && Thread.current[:escpos_prefetch].nil?

        pending = {}
        begin
          Thread.current[:escpos_prefetch] = pending
          yield
        ensure
          Thread.current[:escpos_prefetch] = nil
        end
        pending.each_slice(BATCH_SIZE) { |slice| draw_batch(slice.to_h) }
      rescue StandardError => e
        Rails.logger.warn("[Printing] image prefetch skipped: #{e.class}: #{e.message}")
      end

      # pending: { cache key => single-image command }. Every command ends with
      # BATCH_SUFFIX; each one's settings sit in its own parentheses, and
      # -respect-parentheses keeps them from leaking into the next image, so the
      # output is the same bytes the separate runs would give, one PBM after another.
      def draw_batch(pending)
        cmds = pending.select { |_key, cmd| cmd.last(3) == BATCH_SUFFIX && cmd.first == im_command }
        return if cmds.size < 2

        batch = [im_command, "-respect-parentheses"]
        cmds.each_value { |cmd| batch += ["(", *cmd[1...-3], ")"] }
        batch += BATCH_SUFFIX

        stdout, _stderr, status = Open3.capture3(*batch)
        return unless status.success?

        images = split_pbm_stream(stdout.b)
        return unless images && images.size == cmds.size

        cmds.keys.zip(images).each { |key, pbm| Printing::RasterCache.fetch(key) { pbm } }
      end

      # Splits concatenated binary PBMs ("P4\n<w> <h>\n<rows>"…). Nil if the stream
      # does not parse cleanly, so a surprise never puts a wrong picture in the cache.
      def split_pbm_stream(stream)
        images = []
        pos = 0
        while pos < stream.bytesize
          header = stream.byteslice(pos, 64).match(/\AP4\n(\d+) (\d+)\n/n)
          return nil unless header

          w = header[1].to_i
          h = header[2].to_i
          length = header[0].bytesize + ((w + 7) / 8) * h
          return nil if pos + length > stream.bytesize

          images << stream.byteslice(pos, length)
          pos += length
        end
        images
      end

      # Runs an ImageMagick command with `png:-` output; returns Base64 string.
      def run_to_png(cmd_prefix)
        stdout, _stderr, status = Open3.capture3(*(cmd_prefix + ["png:-"]))
        status.success? ? Base64.strict_encode64(stdout) : nil
      end

      # Converts a binary PBM (P4) blob to ESC/POS GS v 0 raster bytes.
      def pbm_to_escpos(pbm)
        pbm = pbm.b
        nl  = "\n".b
        i1  = pbm.index(nl)
        i2  = pbm.index(nl, i1 + 1)
        w, h = pbm[i1 + 1, i2 - i1 - 1].split(" ".b).map(&:to_i)
        data    = pbm[i2 + 1, pbm.bytesize]
        w_bytes = (w / 8.0).ceil

        # ESC/POS GS v 0: \x1D v 0 m xL xH yL yH <data>
        escpos = +"\x1D\x76\x30\x00".b
        escpos << [w_bytes].pack("v")
        escpos << [h].pack("v")
        escpos << data[0, w_bytes * h]
        escpos
      end
    end
  end
end
