// Inspect functions, parameters, properties and constants.
const LIMIT = 4;
class Item {
  constructor(name, count) { this.name = name; this.count = count; }
}
function total(item, extra = 2) {
  if (item === null) return 0;
  return item.count + extra;
}
const item = new Item("Matrix", LIMIT);
console.log(`${item.name}: ${total(item, 2)}`);
