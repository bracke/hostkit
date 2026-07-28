# hostkit

**The host's own way: spawning, shells, links, executability.**

hostkit is a small Ada 2022 library that owns the code which exists *only because
operating systems differ*. Its consumers (files, launcher, terminal, …) ask hostkit
and get the truth, instead of each re-learning which of GNAT's portable-looking
helpers can be trusted on which host.

## Why it exists

The danger this crate answers is not a helper that *fails* on the wrong host — it's
one that confidently answers **wrong** and lets the code go on looking correct:

- `GNAT.OS_Lib.Is_Symbolic_Link` is always `False` on Windows (it wants an `lstat`,
  and there is none). `Is_Executable_File` is `True` for every file that exists — and
  for directories. `Set_Executable` does nothing at all.
- `OSTYPE` is a shell variable, not part of a spawned process's environment, so a
  check for it calls every macOS a Linux — forever, never failing.
- `stat -c %a` is GNU syntax; BSD `stat` wants `-f %Lp`, and Windows has no `stat`.
  The command *is* there on macOS, so the call fails in a way the caller never notices.

Each of those cost a real bug before anyone noticed, and each was fixed separately in
more than one crate. hostkit gives every one of them a **body per OS** and a comment
saying what the host actually does.

## The contract

**"Cannot tell" is not "fine".** Several answers here are `False` on a host that cannot
express the question — e.g. `Accessible_By_Others` on Windows, where access is by ACL
and hostkit does not read it. That is a *refusal to guess*, not a clean bill of health.
A consumer that stores it as one has rebuilt, on its own side, the bug this crate exists
to prevent.

## What belongs here

Anything that exists only because the operating systems differ, and that therefore has a
per-OS body. **Not**: policy, formats, domain rules, or anything to do with a user
interface. The question to ask of a new subprogram is:

> *Does this differ **because the host differs**?* If no, it belongs to the consumer.

## The API

| Package | Answers |
|---|---|
| `Hostkit.Host` | Which host is this program running on? (from the body the build chose, which no environment can spoof) |
| `Hostkit.Fs` | Facts about a path the host answers differently — and that GNAT gets wrong on Windows |
| `Hostkit.Process` | Starting other programs |
| `Hostkit.Native` | The parts of starting a program that only the host can answer (one body per OS) |
| `Hostkit.Shell` | Running a command line through the host's shell |
| `Hostkit.Local_Channel` | A byte channel to a local endpoint named by a path |

The **specs (`src/hostkit*.ads`) are the reference documentation** — each subprogram is
commented with what the host actually does, per OS. Start with `src/hostkit.ads`.

## Build & test

Built with [Alire](https://alire.ada.dev/) and GNAT 15.2.1.

```sh
alr build                                   # build the library

cd tests && alr build && ./bin/hostkit_tests   # build & run the AUnit suite
```

## Platforms

Linux, macOS, and Windows are all first-class. CI runs the suite on a matrix of all
three — **this is not optional**: a green Linux build says nothing about whether the
per-host bodies are right, which is the entire point of the crate.

## License

MIT © Bent Bracke
