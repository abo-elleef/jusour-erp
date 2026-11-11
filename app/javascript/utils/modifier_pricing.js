// Prices shown in the "customize" modal of the POS (online and offline).
//
// The cashier sees the price of the whole item for each choice instead of
// "+35.00", so nobody has to add numbers in their head. The rule mirrors what
// the server charges:
//   list   = branch price + every chosen modifier's adjustment
//   promo  = the first promo (already in Menus::ActivePromo priority order)
//            that covers the whole item or a choice on the line
//   final  = list − promo discount (a fixed amount per unit)
// Tax is added on top at the order level, like the cart, so it is not here.
//
// config = {
//   base_cents,
//   groups: [{ id, multi_select, modifiers: [{ id, price_adjustment_cents }] }],
//   promos: [{ modifier_id, discount_cents }]
// }

export function priceFor(config, selectedIds) {
  const selected = new Set(selectedIds)
  let list = config.base_cents
  for (const group of config.groups) {
    for (const modifier of group.modifiers) {
      if (selected.has(modifier.id)) list += modifier.price_adjustment_cents
    }
  }
  const promo = (config.promos || []).find((row) => !row.modifier_id || selected.has(row.modifier_id))
  const discount = promo ? Math.min(promo.discount_cents, Math.max(list, 0)) : 0
  return { list, discount, final: list - discount }
}

// The item's price if the cashier picks this option, keeping what is already
// picked in the other groups. A radio choice replaces its group's choice; a
// checkbox adds to it.
export function priceWithOption(config, selectedIds, group, modifierId) {
  const groupIds = new Set(group.modifiers.map((modifier) => modifier.id))
  const next = group.multi_select
    ? [...selectedIds, modifierId]
    : [...selectedIds.filter((id) => !groupIds.has(id)), modifierId]
  return priceFor(config, [...new Set(next)])
}

// Only groups whose choices change the price get a price per row; showing
// "110.00" next to both hot and cold would just be noise.
export function groupShowsPrices(group, promos) {
  const targeted = new Set((promos || []).map((row) => row.modifier_id).filter(Boolean))
  return group.modifiers.some((modifier) => modifier.price_adjustment_cents !== 0 || targeted.has(modifier.id))
}
