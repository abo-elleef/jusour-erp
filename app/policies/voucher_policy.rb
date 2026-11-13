# frozen_string_literal: true

# A voucher is a document, not a draft. It is issued or it is voided and
# reissued — there is no editing one, which is why there is no `update?` route
# to authorize. Voiding takes the cash back, so it stays with owners and
# accountants, as deleting an expense does.
class VoucherPolicy < AccountingPolicy
  def destroy?
    return false if record.is_a?(Voucher) && (record.backfilled? || record.voided?)
    return false if record.is_a?(Voucher) && record.drawer_variance_document?

    user.owner? || user.accountant?
  end
end
