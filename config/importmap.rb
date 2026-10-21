# Pin npm packages by running ./bin/importmap

pin "application"
pin "@hotwired/turbo-rails", to: "turbo.min.js"
pin "@hotwired/stimulus", to: "stimulus.min.js"
pin "@hotwired/stimulus-loading", to: "stimulus-loading.js"
pin_all_from "app/javascript/controllers", under: "controllers"
pin_all_from "app/javascript/utils", under: "utils"
# Rich-text editing (Action Text) — loaded only by pages that render an editor,
# via javascript_import_module_tag "rich_text_editor", so the public site
# never downloads Trix.
# preload: false keeps them out of the <link rel="modulepreload"> list every
# page gets.
pin "trix", preload: false
pin "@rails/actiontext", to: "actiontext.esm.js", preload: false
pin "rich_text_editor", preload: false
