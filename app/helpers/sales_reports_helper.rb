# frozen_string_literal: true

module SalesReportsHelper
  # A sortable <th> for the sales-reports tabs (see sortable_table_controller.js):
  # clicking it sorts the table body by the <td data-sort-key="key"> in each row.
  def sortable_report_th(label, key, type: :string, align: :end, pe: false)
    classes = +"p-3 cursor-pointer select-none hover:text-gray-700 transition-colors"
    classes << (align == :start ? " text-start ps-5" : " text-end")
    classes << " pe-5" if pe

    data = { sortable_table_target: "header", action: "click->sortable-table#sort", sort_key: key }
    data[:sort_type] = "number" if type == :number

    tag.th(class: classes, data: data) do
      safe_join([label, tag.span("", class: "inline-block w-3 text-[10px] align-middle", data: { sort_indicator: true })])
    end
  end
end
