// Inspect interface/type names and readonly properties.
interface Item { readonly name: string; count: number; }
type Count = number;
const LIMIT: Count = 4;
function total(item: Item | null, extra: Count = 2): Count {
  if (item === null) return 0;
  return item.count + extra;
}
const item: Item = { name: "Matrix", count: LIMIT };
console.log(`${item.name}: ${total(item)}`);
