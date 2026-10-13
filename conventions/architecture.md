# Architecture conventions

Use these principles when a change affects responsibilities or module boundaries. They guide decisions across different kinds of projects; they do not prescribe a universal layer structure. For Meowsky DevKit's current runtime and feature ownership, see [the existing architecture](../docs/architecture.md). For file and folder placement, see [filesystem conventions](filesystem.md).

## Principles

1. Prefer simple, explicit code over clever abstractions. A reader should be able to follow the main behavior without decoding a framework built around it.
2. Separate responsibilities when the separation makes behavior easier to understand, change, or test. Keep cohesive behavior together.
3. Avoid monolithic files that combine unrelated logic. Split at a responsibility boundary, not an arbitrary line count.
4. Group implementation by feature or domain when related behavior benefits from living together.
5. Put code in a shared module only when it serves real consumers across features. Keep feature-specific behavior with its feature.
6. Avoid generic frameworks built ahead of a concrete need. Prefer a small function or module that solves the current problem.
7. Refactor incrementally. Make the smallest coherent change, verify it, and treat broader restructuring as a separate scope.
8. Follow the existing codebase's naming, module boundaries, and integration style unless a change has a clear reason to depart from them.
9. Add an architectural layer only when it has a practical responsibility and reduces complexity for the current application.
10. Design for a solo developer to understand and maintain: make ownership and execution paths easy to locate, with few hidden dependencies.

## Boundaries by application type

For a web application, consider distinct places for routing, validation, business logic, persistence, presentation, and components genuinely shared across features. Separate a concern when it has enough behavior or reuse to justify its boundary. A small application does not need every layer.

For a C application, put declarations that other translation units need in headers and implementations in source files. Keep `main` focused on entry-point composition. Introduce modules when separate responsibilities or reuse justify them; a small exercise can remain one source file.

## Lightweight review before significant changes

Before a significant feature, cross-module refactor, or new architectural boundary, briefly establish:

1. What behavior and data are changing, and which existing files own them?
2. Which responsibilities need separation now, and what concrete problem would each new boundary solve?
3. What is the smallest coherent edit that fits the current architecture and avoids unrelated moves?
4. Which meaningful tests or manual checks will show that the behavior still works?

Keep the review proportional to the change. A routine local edit does not need an architecture exercise. If the change grows beyond its agreed scope, revisit the plan and the edit gate before modifying additional files.
