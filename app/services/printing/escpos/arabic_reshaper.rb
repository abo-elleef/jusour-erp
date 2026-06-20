# frozen_string_literal: true

# Converts logical Arabic text (isolated Unicode codepoints) to visually shaped
# text using Arabic Presentation Forms (U+FE70–U+FEFF), so thermal printers
# that do no internal shaping render connected Arabic script correctly.
#
# After reshaping, text must still be reversed for RTL output (handled by Bidi).

module Printing
  module Escpos
    module ArabicReshaper
      # :right  = joins only to the right (previous char in logical order)
      # :dual   = joins on both sides
      # :none   = non-joining
      JOINING_TYPE = {
        "ء" => :none,  # ء
        "آ" => :right, # آ
        "أ" => :right, # أ
        "ؤ" => :right, # ؤ
        "إ" => :right, # إ
        "ئ" => :dual,  # ئ
        "ا" => :right, # ا
        "ب" => :dual,  # ب
        "ة" => :right, # ة
        "ت" => :dual,  # ت
        "ث" => :dual,  # ث
        "ج" => :dual,  # ج
        "ح" => :dual,  # ح
        "خ" => :dual,  # خ
        "د" => :right, # د
        "ذ" => :right, # ذ
        "ر" => :right, # ر
        "ز" => :right, # ز
        "س" => :dual,  # س
        "ش" => :dual,  # ش
        "ص" => :dual,  # ص
        "ض" => :dual,  # ض
        "ط" => :dual,  # ط
        "ظ" => :dual,  # ظ
        "ع" => :dual,  # ع
        "غ" => :dual,  # غ
        "ف" => :dual,  # ف
        "ق" => :dual,  # ق
        "ك" => :dual,  # ك
        "ل" => :dual,  # ل
        "م" => :dual,  # م
        "ن" => :dual,  # ن
        "ه" => :dual,  # ه
        "و" => :right, # و
        "ى" => :dual,  # ى
        "ي" => :dual,  # ي
        # Extended
        "ٱ" => :right, # ٱ
        "ٲ" => :right, "ٳ" => :right,
        "ٴ" => :none,
        "ٵ" => :right, "ٶ" => :right, "ٷ" => :right,
        "ٸ" => :dual,
        "ٹ" => :dual, "ٺ" => :dual, "ٻ" => :dual,
        "ټ" => :dual, "ٽ" => :dual, "پ" => :dual,
        "ٿ" => :dual, "ڀ" => :dual,
        "ځ" => :dual, "ڂ" => :dual, "ڃ" => :dual,
        "ڄ" => :dual, "څ" => :dual, "چ" => :dual,
        "ڇ" => :dual,
        "ڈ" => :right, "ډ" => :right, "ڊ" => :right,
        "ڋ" => :right, "ڌ" => :right, "ڍ" => :right,
        "ڎ" => :right, "ڏ" => :right, "ڐ" => :right,
        "ڑ" => :right, "ڒ" => :right, "ړ" => :right,
        "ڔ" => :right, "ڕ" => :right, "ږ" => :right,
        "ڗ" => :right, "ژ" => :right, "ڙ" => :right,
        "ښ" => :dual, "ڛ" => :dual, "ڜ" => :dual,
        "ڝ" => :dual, "ڞ" => :dual, "ڟ" => :dual,
        "ڠ" => :dual, "ڡ" => :dual, "ڢ" => :dual,
        "ڣ" => :dual, "ڤ" => :dual, "ڥ" => :dual,
        "ڦ" => :dual, "ڧ" => :dual, "ڨ" => :dual,
        "ک" => :dual, "ڪ" => :dual, "ګ" => :dual,
        "ڬ" => :dual, "ڭ" => :dual, "ڮ" => :dual,
        "گ" => :dual, "ڰ" => :dual, "ڱ" => :dual,
        "ڲ" => :dual, "ڳ" => :dual, "ڴ" => :dual,
        "ڵ" => :dual, "ڶ" => :dual, "ڷ" => :dual,
        "ڸ" => :dual, "ڹ" => :dual, "ں" => :right,
        "ڻ" => :dual, "ڼ" => :dual, "ڽ" => :dual,
        "ھ" => :dual, "ڿ" => :dual,
        "ۀ" => :right, "ہ" => :dual, "ۂ" => :dual,
        "ۃ" => :right, "ۄ" => :right, "ۅ" => :right,
        "ۆ" => :right, "ۇ" => :right, "ۈ" => :right,
        "ۉ" => :right, "ۊ" => :right, "ۋ" => :right,
        "ی" => :dual, "ۍ" => :right, "ێ" => :dual,
        "ۏ" => :right, "ې" => :dual, "ۑ" => :dual,
        "ے" => :right, "ۓ" => :right
      }.freeze

      # [isolated, final, initial, medial]
      FORMS = {
        "ء" => ["ﺀ", nil,     nil,     nil    ], # ء
        "آ" => ["ﺁ", "ﺂ", nil,    nil    ], # آ
        "أ" => ["ﺃ", "ﺄ", nil,    nil    ], # أ
        "ؤ" => ["ﺅ", "ﺆ", nil,    nil    ], # ؤ
        "إ" => ["ﺇ", "ﺈ", nil,    nil    ], # إ
        "ئ" => ["ﺉ", "ﺊ", "ﺋ", "ﺌ"], # ئ
        "ا" => ["ﺍ", "ﺎ", nil,    nil    ], # ا
        "ب" => ["ﺏ", "ﺐ", "ﺑ", "ﺒ"], # ب
        "ة" => ["ﺓ", "ﺔ", nil,    nil    ], # ة
        "ت" => ["ﺕ", "ﺖ", "ﺗ", "ﺘ"], # ت
        "ث" => ["ﺙ", "ﺚ", "ﺛ", "ﺜ"], # ث
        "ج" => ["ﺝ", "ﺞ", "ﺟ", "ﺠ"], # ج
        "ح" => ["ﺡ", "ﺢ", "ﺣ", "ﺤ"], # ح
        "خ" => ["ﺥ", "ﺦ", "ﺧ", "ﺨ"], # خ
        "د" => ["ﺩ", "ﺪ", nil,    nil    ], # د
        "ذ" => ["ﺫ", "ﺬ", nil,    nil    ], # ذ
        "ر" => ["ﺭ", "ﺮ", nil,    nil    ], # ر
        "ز" => ["ﺯ", "ﺰ", nil,    nil    ], # ز
        "س" => ["ﺱ", "ﺲ", "ﺳ", "ﺴ"], # س
        "ش" => ["ﺵ", "ﺶ", "ﺷ", "ﺸ"], # ش
        "ص" => ["ﺹ", "ﺺ", "ﺻ", "ﺼ"], # ص
        "ض" => ["ﺽ", "ﺾ", "ﺿ", "ﻀ"], # ض
        "ط" => ["ﻁ", "ﻂ", "ﻃ", "ﻄ"], # ط
        "ظ" => ["ﻅ", "ﻆ", "ﻇ", "ﻈ"], # ظ
        "ع" => ["ﻉ", "ﻊ", "ﻋ", "ﻌ"], # ع
        "غ" => ["ﻍ", "ﻎ", "ﻏ", "ﻐ"], # غ
        "ف" => ["ﻑ", "ﻒ", "ﻓ", "ﻔ"], # ف
        "ق" => ["ﻕ", "ﻖ", "ﻗ", "ﻘ"], # ق
        "ك" => ["ﻙ", "ﻚ", "ﻛ", "ﻜ"], # ك
        "ل" => ["ﻝ", "ﻞ", "ﻟ", "ﻠ"], # ل
        "م" => ["ﻡ", "ﻢ", "ﻣ", "ﻤ"], # م
        "ن" => ["ﻥ", "ﻦ", "ﻧ", "ﻨ"], # ن
        "ه" => ["ﻩ", "ﻪ", "ﻫ", "ﻬ"], # ه
        "و" => ["ﻭ", "ﻮ", nil,    nil    ], # و
        "ى" => ["ﻯ", "ﻰ", nil,    nil    ], # ى
        "ي" => ["ﻱ", "ﻲ", "ﻳ", "ﻴ"]  # ي
      }.freeze

      # Diacritics (tashkeel) — zero-width marks that follow their base letter
      TASHKEEL = /[ً-ٰٟ]/

      module_function

      def reshape(text)
        return text if text.nil? || text.empty?

        chars = text.chars
        result = []
        i = 0

        while i < chars.length
          ch = chars[i]

          # Collect any tashkeel immediately following this char
          diacritics = +""
          j = i + 1
          while j < chars.length && chars[j].match?(TASHKEEL)
            diacritics << chars[j]
            j += 1
          end

          forms = FORMS[ch]
          if forms
            prev_joins = i > 0 && joining_type(chars[i - 1]) == :dual
            next_char  = chars[j] # first non-diacritic char after ch
            next_joins = next_char && JOINING_TYPE.key?(next_char) &&
                         JOINING_TYPE[next_char] != :none

            form_index =
              if prev_joins && next_joins && forms[3]
                3  # medial
              elsif prev_joins && forms[1]
                1  # final
              elsif next_joins && forms[2]
                2  # initial
              else
                0  # isolated
              end

            result << (forms[form_index] || forms[0])
            result << diacritics unless diacritics.empty?
          else
            result << ch
          end

          i = j
        end

        result.join
      end

      def joining_type(char)
        JOINING_TYPE[char] || :none
      end
    end
  end
end
