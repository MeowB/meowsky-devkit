"""Inspect annotations, comments, strings and ordinary names."""
LIMIT = 4

class Item:
    def __init__(self, name: str, count: int):
        self.name = name
        self.count = count

def total(item: Item | None, extra: int = 2) -> int:
    # Parameters and fields should stay readable.
    if item is None:
        return 0
    else:
        return item.count + extra

item = Item("Matrix", LIMIT)
print(f"{item.name}: {total(item)}")
