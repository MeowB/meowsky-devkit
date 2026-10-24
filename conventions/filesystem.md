# Filesystem organization conventions

Use these conventions when adding or changing project files. They guide decisions; the examples below are illustrative patterns, not mandatory templates. Preserve a repository's established layout and naming unless a separate migration is explicitly approved. For Meowsky DevKit's current module ownership, see [the feature architecture](../docs/architecture.md).

## Disposable development workspace

Projects opened through Meowsky use a root `.meowsky/` directory for user-supplied task inputs and temporary Codex artifacts. Meowsky creates it on project open and adds `/.meowsky/` to the root `.gitignore` when no equivalent rule exists. Keep maintained source, tests, configuration, documentation, and required assets outside it. Move any lasting result to its maintained location. The directory can be deleted without changing project functionality, although deleting generated audit and review files resets those workflows until audit runs again. Preserve existing inputs and artifacts unless the user asks to remove them.

## Organize by responsibility

1. Give each file and folder a clear responsibility. Its contents should fit the purpose implied by its name.
2. Name files and folders so a reader can predict their purpose without opening them. Follow the project's existing naming style.
3. Group related code by feature or domain when that makes a feature easier to find and change together. Keep genuinely shared code in a shared location only after it has more than one real consumer.
4. Avoid `misc/`, broad `helpers/` directories, and giant `utils` files that collect unrelated work. Name a focused module for the job it performs.
5. Keep tests beside the code they validate when the project's test runner and conventions permit it. If the project uses a central test directory, retain that pattern and make the test-to-code relationship clear through names and paths. Meowsky DevKit currently uses `tests/`.
6. Add directory levels only when they improve navigation or express a meaningful boundary. Do not bury a small feature under a deep chain of single-purpose folders.
7. Create abstractions and folders for current needs, not hypothetical future features.
8. Preserve existing naming conventions unless an explicit migration is approved. Use consistent names for new work rather than renaming unrelated files along the way.
9. Prefer a predictable structure over minimizing file count. A few focused files can be easier to maintain than one file with mixed responsibilities.
10. Never reorganize unrelated files while implementing a feature. Propose a separate, scoped migration when a broader layout change is warranted.

## When to split a file

Consider a split when the file owns multiple unrelated responsibilities, navigation has become difficult, conditional branches repeatedly grow around separate concerns, routing is mixed with business logic and presentation, or tests cannot isolate one behavior without pulling in unrelated code. Split at a meaningful responsibility boundary and keep callers easy to trace.

File size is a warning signal, not proof of poor design. There is no line-count limit; a long cohesive file may be clearer than several artificial fragments.

## Illustrative structures

### Simple C exercise

```text
temperature-exercise/
  README.md                 # Build and run instructions
  temperature.c             # Exercise implementation
  temperature_test.c        # Focused test, if the exercise needs one
```

A small exercise does not need `src/` and `include/` merely to look like a larger project. Add them when multiple source files or a public interface make that structure useful.

### Medium-sized TypeScript application

```text
src/
  routes/
    tasks.tsx               # Page and route composition
  features/
    tasks/
      task.ts               # Task data shape
      taskApi.ts            # Task data access
      TaskList.tsx          # Feature rendering
      TaskList.test.tsx     # Test beside the feature
  shared/
    ui/
      Button.tsx            # Used by multiple features
```

Use the framework's route convention where it supplies one. Put a component in `shared/` only when it is actually shared.

### Feature-oriented backend

```text
src/
  features/
    orders/
      order.model.ts        # Order data shape
      order.service.ts      # Order rules and operations
      order.routes.ts       # HTTP entry points
      order.service.test.ts # Service behavior
    customers/
      customer.model.ts
      customer.service.ts
      customer.routes.ts
```

Keep transport, domain rules, and persistence responsibilities distinct as they grow. Add a shared module only for code used across real features; adapt names and test placement to the repository's existing framework and tooling.
