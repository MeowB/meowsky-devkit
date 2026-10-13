# Code style conventions

Follow the formatting and naming conventions already used by the project. These guidelines describe maintainable code across languages; project tooling and established style determine exact syntax and layout.

- Use clear, descriptive names for files, functions, variables, and types. Prefer a name that states a responsibility over a broad name such as `helper` or `data`.
- Format code consistently with neighboring code and the project's formatter, if one exists. Avoid formatting unrelated files as part of a focused change.
- Handle expected errors explicitly and make failures understandable to callers or users. Do not silently discard failures unless that behavior is intentional and explained.
- Minimize hidden side effects. Make state changes, file writes, external calls, and other consequential behavior apparent at the call site or in the function's contract.
- Comment on intent, constraints, tradeoffs, and non-obvious behavior. Avoid comments that merely restate what the next line does; update comments when behavior changes.
- Remove dead code and unused abstractions when they are part of the scoped change. Do not add speculative options, extension points, or features without a current use.
- Test meaningful behavior and regressions, especially where a bug was found or a boundary changed. Choose checks that can fail for a real defect rather than tests that only mirror the implementation.

For responsibility boundaries and when to introduce modules, see [architecture conventions](architecture.md). For naming and placement of files, see [filesystem conventions](filesystem.md).
