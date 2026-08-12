# Contributing

Copilot Control Tower is deliberately small and safety-constrained. Read
[`SOUL.md`](SOUL.md) and the
[architecture principles](docs/01-architecture/12-architecture-guiding-principles.md)
before proposing behavior.

The core boundaries are:

- The app parses versioned CLI results; it does not compute ecosystem state.
- Missing or unreadable evidence stays unknown.
- The app never overwrites a person’s dirty working tree.
- Secrets never travel through inherited Git content.
- There are no force, skip-verification, or lower-trust modes.

For a change:

1. Keep it to one coherent behavior.
2. Add focused coverage under `scripts/tests/`.
3. Run the native invariant gate and both native builds.
4. Update the relevant public documentation.
5. Use a pull request; do not push release tags as part of normal development.

Useful commands:

```sh
./scripts/tests/test_native_invariants.sh
./scripts/build-user.command --build-only
./scripts/build-admin.command --build-only
```

By participating, you agree to the [Code of Conduct](CODE_OF_CONDUCT.md).
