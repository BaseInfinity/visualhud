#!/usr/bin/env python3
"""Run a command inside a real PTY and capture raw output (including ANSI escape sequences).

Usage:
    pty-run.py [--input-file FILE] [--input STR] [--timeout SEC] [--cols N] [--rows N]
               --out OUTPUT_FILE -- COMMAND [ARGS...]

Exits with the wrapped command's exit code. Output (raw bytes, ANSI included) is written
to OUTPUT_FILE so downstream bash assertions can grep / diff it.

Why a PTY: many TUI programs (visualhud engine, white-rabbit, anything using tput / readline /
ncurses) detect non-TTY stdout and switch to a degraded mode. Running them inside a PTY
forces the real rendering path so we can assert on what users actually see.
"""

import argparse
import errno
import os
import pty
import select
import sys
import time


def run(command, out_path, input_bytes, timeout, cols, rows):
    pid, fd = pty.fork()
    if pid == 0:
        # Child — replace with target command. PTY is already wired to our stdio.
        os.environ.setdefault("TERM", "xterm-256color")
        os.environ["COLUMNS"] = str(cols)
        os.environ["LINES"] = str(rows)
        try:
            os.execvp(command[0], command)
        except OSError as e:
            sys.stderr.write(f"pty-run: exec {command[0]}: {e}\n")
            os._exit(127)

    # Try to set window size so curses-style apps lay out correctly.
    try:
        import fcntl
        import struct
        import termios
        fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", rows, cols, 0, 0))
    except Exception:
        pass

    if input_bytes:
        try:
            os.write(fd, input_bytes)
        except OSError:
            pass

    deadline = time.monotonic() + timeout if timeout > 0 else None
    captured = bytearray()

    while True:
        if deadline is not None:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                _kill(pid)
                _drain(fd, captured)
                _write_out(out_path, captured)
                sys.stderr.write(f"pty-run: timeout after {timeout}s\n")
                return 124
            ready, _, _ = select.select([fd], [], [], remaining)
        else:
            ready, _, _ = select.select([fd], [], [], 0.5)

        if fd in ready:
            try:
                chunk = os.read(fd, 4096)
            except OSError as e:
                if e.errno == errno.EIO:
                    chunk = b""  # PTY closed = child exited
                else:
                    raise
            if not chunk:
                break
            captured.extend(chunk)

        wpid, status = os.waitpid(pid, os.WNOHANG)
        if wpid == pid:
            _drain(fd, captured)
            _write_out(out_path, captured)
            return os.waitstatus_to_exitcode(status)

    _, status = os.waitpid(pid, 0)
    _write_out(out_path, captured)
    return os.waitstatus_to_exitcode(status)


def _drain(fd, buf):
    while True:
        ready, _, _ = select.select([fd], [], [], 0)
        if fd not in ready:
            return
        try:
            chunk = os.read(fd, 4096)
        except OSError:
            return
        if not chunk:
            return
        buf.extend(chunk)


def _kill(pid):
    import signal
    try:
        os.kill(pid, signal.SIGTERM)
        time.sleep(0.1)
        os.kill(pid, signal.SIGKILL)
    except ProcessLookupError:
        pass


def _write_out(path, buf):
    with open(path, "wb") as f:
        f.write(bytes(buf))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", required=True, help="path to write captured raw output")
    parser.add_argument("--input", default=None, help="literal keystrokes to send (use \\n, \\t, \\x1b)")
    parser.add_argument("--input-file", default=None, help="file whose contents are sent as keystrokes")
    parser.add_argument("--timeout", type=float, default=10.0, help="seconds before killing the child (0 = no timeout)")
    parser.add_argument("--cols", type=int, default=120)
    parser.add_argument("--rows", type=int, default=30)
    parser.add_argument("command", nargs=argparse.REMAINDER)
    args = parser.parse_args()

    if not args.command or args.command[0] == "--":
        cmd = args.command[1:] if args.command and args.command[0] == "--" else []
    else:
        cmd = args.command
    if not cmd:
        parser.error("missing command after --")

    input_bytes = b""
    if args.input_file:
        with open(args.input_file, "rb") as f:
            input_bytes = f.read()
    elif args.input is not None:
        input_bytes = args.input.encode("utf-8").decode("unicode_escape").encode("latin-1")

    sys.exit(run(cmd, args.out, input_bytes, args.timeout, args.cols, args.rows))


if __name__ == "__main__":
    main()
