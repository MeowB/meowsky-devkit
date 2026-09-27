#include <stddef.h>
#include <stdio.h>
#define MAX_ITEMS 4

/* Inspect types, pointers, fields, constants and ordinary identifiers. */
typedef struct Item {
    const char *name;
    int count;
} Item;

static int total(const Item *item, int extra);

static int total(const Item *item, int extra) {
    if (item == NULL) {
        return 0;
    } else {
        return item->count + extra;
    }
}

int main(void) {
    const int limit = MAX_ITEMS;
    Item item = {"Matrix", 2};
    const Item *pointer = &item;
    int result = total(pointer, limit);
    // Function calls and strings should differ from control-flow keywords.
    printf("%s: %d\n", pointer->name, result);
    return 0;
}
