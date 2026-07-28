# CLAUDE.md

Guidance for AI agents (Claude Code and others) working in this repository.

## What this is

hostkit is an Ada 2022 library that owns the code which exists **only because operating
systems differ** — spawning, shells, links, executability, host identity. Consumers
(files, launcher, terminal, …) depend on it so they don't each re-derive which
portable-looking GNAT/POSIX helper answers wrong on which host. It has **no external
Ada dependencies**; it is a leaf of the workspace.

The authoritative rationale lives in `src/hostkit.ads` — read it first. It explains,
with concrete bug histories, why the crate exists and what its contract is.

## Build, test, verify

Built with [Alire](https://alire.ada.dev/) (`alr`), pinned to `gnat_native = "=15.2.1"`.

- `alr build` — compile the library. Full style and warning checks run at compile time
  (`-gnat2022`, `-gnatyM120` 120-col limit, `-gnaty3` 3-space indent, `-gnatwa` all
  warnings), so a clean build also passes style.
- Tests are a **separate crate** under `tests/` (`hostkit_tests`, depends on `aunit`):
  ```sh
  cd tests && alr build && ./bin/hostkit_tests   # ./bin/hostkit_tests.exe on Windows
  ```

## The two rules that govern every change

1. **"Does this differ *because the host differs*?"** — the inclusion test. If a
   subprogram would have the same body on every OS, it does **not** belong here; it
   belongs to the consumer. No policy, formats, domain rules, or UI. Adding a
   host-neutral helper here is the most common wrong change.

2. **"Cannot tell" is not "fine".** When a host cannot express a question, the answer
   is a deliberate `False`/refusal, **not** an optimistic default. Do not "fix" such an
   answer to return `True`, and do not let a consumer store it as a clean result — that
   re-creates the exact class of bug hostkit exists to prevent.

## Conventions

- Anything host-specific has **one body per OS**, selected by the build (see how the
  per-OS bodies are organized before adding a new one). Answer from the body the build
  chose — never from the environment (`OSTYPE` etc.), which a spawned process can spoof.
- Each host-specific subprogram carries a comment saying what the host *actually* does.
  Keep that up when you change behavior; the specs are the documentation.
- Conventional-commits style (`feat:`, `fix:`, `refactor:`, …).

## Tri-platform CI is mandatory

CI runs the suite on **ubuntu-latest, macos-15-intel, and windows-latest** — not as a
nicety but as the point of the crate. A change that only builds/passes on Linux has not
been validated at all. The macOS image must be x86_64 (`macos-15-intel`): the pinned
`gnat_native=15.2.1` ships no aarch64-darwin binary. Never reduce the matrix to make a
run green.
