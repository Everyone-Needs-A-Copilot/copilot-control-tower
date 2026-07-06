# copilot-control-tower Soul

Use this file to decide whether product-facing work belongs in the product before implementation begins.

## Purpose

Project using codex-copilot

## Product Promise

- What should this product help people do better?
- What should using it feel like?
- What should it never become?

## Quality Bar

- Useful before impressive.
- Clear before clever.
- Calm under pressure.
- Every feature earns its place.

## Taste Constraints

- Prefer workflows that reduce user effort instead of exposing system complexity.
- Prefer interfaces that make the next action obvious without flattening expert control.
- Prefer durable, coherent product language over novelty.
- Reject decorative features, vague automation, and UI that hides important state.

## Anti-Patterns

- Shipping implementation because it is easy rather than because it serves the product promise.
- Adding settings, modes, or panels before the core workflow is resolved.
- Treating empty, loading, error, permission, and recovery states as afterthoughts.
- Letting technical architecture define the user experience.

## Decision Questions

Before substantial product-facing work, answer:

1. Does this direction strengthen the product promise?
2. What user effort, uncertainty, or risk does it remove?
3. What simpler version would preserve the essential value?
4. Which state or failure path would make this feel unfinished?
5. Should this be built, reshaped, deferred, or rejected?
