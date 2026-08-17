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
| `Hostkit.Fs` | Facts about a path the host answers differently — and that GNAT gets wrong on Windows; also where the host keeps the device that reads as nothing |
| `Hostkit.Signals` | Signals, and — separately — whether the host can report that one arrived |
| `Hostkit.Process` | Starting other programs, and ending this one without unwinding |
| `Hostkit.Native` | The parts of starting a program that only the host can answer (one body per OS) |
| `Hostkit.Shell` | Running a command line through the host's shell |
| `Hostkit.Local_Channel` | A byte channel to a local endpoint named by a path |
| `Hostkit.Spawn` | Starting a program the way a shell has to: descriptors the caller made, a process group, a terminal's foreground, a session of its own, and no wait |
| `Hostkit.Descriptors` | Pipes, duplication, inheritance, non-blocking mode, and reads that tell end-of-file from would-block |
| `Hostkit.Pty` | Terminals for a child that did not inherit one -- a pseudo-terminal, or a pseudo-console where that is what the host has |
| `Hostkit.Terminal_Control` | Terminal modes, window size, the foreground process group, and whether an interrupt reaches a program that is busy |
| `Hostkit.Locks` | Advisory file locks |

Three of those answers exist because a shell asked and the honest answer was
"that depends on the host":

- **Whether an interrupt reaches a busy program.** `Set_Interruptible` arranges
  for the host to notice Ctrl-C, and on POSIX that is the whole story: the
  signal arrives between two instructions of whatever the program was doing. On
  Windows a program spinning in a loop is never told — not late, not unnoticed;
  the control routine does not run for it. A consumer whose reason for asking is
  stopping a runaway loop has to know which host it is on, so it can watch the
  terminal itself where being told is not on offer.
- **The device that reads as nothing.** A caller that must give a program a
  stream and has none — a job put into the background on a host with no job
  control, which cannot share a keyboard with the shell that started it — needs
  the program to see end of input rather than race for keystrokes.
- **Ending without unwinding.** Ada's own way out runs finalization, and
  finalization closes the standard files: it flushes them, and for a program
  whose reader has gone that fails again, inside a finalizer, which is
  `PROGRAM_ERROR` and a stack trace on the stream that already refused
  everything. `End_Now` hands the status to the host and stops.

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
