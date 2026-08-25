# frozen_string_literal: true

require "rails_helper"

RSpec.describe Customers::LegacyImporter do
  let(:company) { create(:company) }

  # Tenant scope for the assertions; the service manages its own inside #call.
  before { Current.company = company }

  def row(legacy_code: "", name: "", phone1: "", phone2: "", address: "", notes: "")
    { "legacy_code" => legacy_code, "name" => name, "phone1" => phone1,
      "phone2" => phone2, "address" => address, "notes" => notes }
  end

  def import(rows, dry_run: false)
    described_class.new(rows: rows, company: company, dry_run: dry_run).call
  end

  it "imports name, phones, address, notes and legacy code" do
    result = import([row(legacy_code: "368", name: "Acme Dental", phone1: "01271219191",
      phone2: "0223456789", address: "12 Golf Land St", notes: "VIP")])

    expect(result.created).to eq(1)
    c = Customer.where(company: company).find_by(legacy_code: "368")
    expect(c.name).to eq("Acme Dental")
    expect(c.phone).to eq("01271219191")
    expect(c.phone_secondary).to eq("0223456789")
    expect(c.notes).to eq("VIP")
    expect(c.addresses.first.address).to eq("12 Golf Land St")
    expect(c.addresses.first.is_default).to be(true)
    expect(result.addresses_created).to eq(1)
  end

  it "nulls junk names but still imports when a phone exists" do
    import([row(name: "...", phone1: "01000000001")])
    c = Customer.where(company: company).find_by(phone: "01000000001")
    expect(c).to be_present
    expect(c.name).to be_nil
  end

  it "skips rows with no usable phone (email-or-phone rule can't pass)" do
    result = import([row(name: "No Contact Guy", phone1: "0")])
    expect(result.skipped_no_contact).to eq(1)
    expect(Customer.where(company: company).count).to eq(0)
  end

  it "promotes a secondary phone to primary when the primary is invalid" do
    import([row(name: "Only Secondary", phone1: "0", phone2: "01055556666")])
    c = Customer.where(company: company).find_by(phone: "01055556666")
    expect(c).to be_present
    expect(c.phone_secondary).to be_nil
  end

  it "merges rows that share a phone into a single customer (last wins)" do
    result = import([
      row(name: "First", phone1: "01234567890"),
      row(name: "Second", phone1: "01234567890")
    ])
    # Same phone => same customer: one created, the next updates it.
    expect(result.created).to eq(1)
    expect(result.updated).to eq(1)
    expect(Customer.where(company: company).count).to eq(1)
    expect(Customer.where(company: company).first.name).to eq("Second")
  end

  it "drops a secondary phone that collides with a different customer" do
    result = import([
      row(name: "Primary Owner", phone1: "01234567890"),
      row(name: "Other", phone1: "01555550000", phone2: "01234567890")
    ])
    expect(result.phone_conflicts).to eq(1)
    other = Customer.where(company: company).find_by(phone: "01555550000")
    expect(other.phone_secondary).to be_nil # the colliding secondary was dropped
    expect(Customer.where(company: company).count).to eq(2)
  end

  it "de-dupes legacy codes that repeat in the source" do
    result = import([
      row(legacy_code: "DUP", name: "A", phone1: "01111111111"),
      row(legacy_code: "DUP", name: "B", phone1: "02222222222")
    ])
    expect(result.legacy_deduped).to eq(2)
    expect(Customer.where(company: company).where.not(legacy_code: nil)).to be_empty
    expect(Customer.where(company: company).count).to eq(2)
  end

  it "is idempotent — re-running updates the same customers by legacy code" do
    rows = [row(legacy_code: "500", name: "Repeat Co", phone1: "01500000000", address: "Old Addr")]
    import(rows)
    expect(Customer.where(company: company).count).to eq(1)

    # Second run with an updated name; should update, not duplicate.
    rows[0]["name"] = "Repeat Co Updated"
    result = import(rows)
    expect(result.created).to eq(0)
    expect(result.updated).to eq(1)
    expect(Customer.where(company: company).count).to eq(1)
    expect(Customer.where(company: company).first.name).to eq("Repeat Co Updated")
    # Address not duplicated on re-run.
    expect(Customer.where(company: company).first.addresses.count).to eq(1)
  end

  it "dry_run persists nothing" do
    result = import([row(name: "Ghost", phone1: "01999999999")], dry_run: true)
    expect(result.created).to eq(1)
    expect(Customer.where(company: company).count).to eq(0)
  end
end
