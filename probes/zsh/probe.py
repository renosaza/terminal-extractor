#!/usr/bin/env python3
"""Run a disposable zsh startup and hook probe; never read the user's rc files."""

import json
import os
import pty
import select
import secrets
import subprocess
import tempfile
import time
from pathlib import Path


ZSH = "/bin/zsh"
PROMPT = b"TE_PROBE_PROMPT> \x1b[?2004h"


def put(path, contents):
    path.write_text(contents, encoding="utf-8")


def read_until(fd, marker, timeout=4):
    seen = b""
    deadline = time.monotonic() + timeout
    while marker not in seen and time.monotonic() < deadline:
        ready, _, _ = select.select([fd], [], [], max(0, deadline - time.monotonic()))
        if not ready:
            break
        try:
            seen += os.read(fd, 65536)
        except OSError:
            break
    if marker not in seen:
        raise AssertionError(f"missing {marker!r} in {seen[-500:]!r}")
    return seen


def run_shell(env, commands, login=False, final_command="exit", expected_status=0):
    master, slave = pty.openpty()
    args = ["-zsh" if login else "zsh", "-i"]
    proc = subprocess.Popen(args, executable=ZSH, stdin=slave, stdout=slave,
                            stderr=slave, env=env, close_fds=True)
    os.close(slave)
    output = b""
    try:
        output += read_until(master, PROMPT)
        for command in commands:
            os.write(master, command.encode() + b"\n")
            output += read_until(master, PROMPT)
        os.write(master, final_command.encode() + b"\n")
        deadline = time.monotonic() + 4
        while proc.poll() is None and time.monotonic() < deadline:
            if select.select([master], [], [], 0.1)[0]:
                try:
                    output += os.read(master, 65536)
                except OSError:
                    break
        if proc.poll() is None:
            raise AssertionError(f"zsh did not exit; output tail: {output[-1200:]!r}")
        assert proc.returncode == expected_status, (proc.returncode, expected_status)
    finally:
        if proc.poll() is None:
            proc.terminate()
            try:
                proc.wait(timeout=4)
            except subprocess.TimeoutExpired:
                proc.kill()
                proc.wait(timeout=4)
        os.close(master)
    return output, proc.returncode


def main():
    with tempfile.TemporaryDirectory(prefix="te-zsh-") as temporary:
        root = Path(temporary)
        original, shim = root / "original", root / "shim"
        original.mkdir()
        shim.mkdir()
        startup = root / "startup.log"
        events = root / "events.log"
        nonce = secrets.token_hex(12)
        env = dict(os.environ, HOME=str(root), HISTFILE=str(root / "history"),
                   TE_ORIGINAL_ZDOTDIR=str(original), TE_SHIM_ZDOTDIR=str(shim),
                   TE_STARTUP_LOG=str(startup), TE_EVENTS=str(events),
                   TE_NONCE=nonce, TERM="dumb")
        for name in (".zshenv", ".zprofile", ".zlogin", ".zlogout"):
            put(original / name, f'print -r -- "{name}:$ZDOTDIR" >> "$TE_STARTUP_LOG"\n')
        put(original / ".zshrc", '''
print -r -- ".zshrc:$ZDOTDIR" >> "$TE_STARTUP_LOG"
PROMPT='TE_PROBE_PROMPT> '
RPROMPT=''
alias tealias='print -r -- ALIAS_OK'
tefunction() { print -r -- FUNCTION_OK; }
te_user_preexec() { print -r -- "user_preexec:$3" >> "$TE_EVENTS"; }
te_user_precmd() { print -r -- "user_precmd:$?" >> "$TE_EVENTS"; return 17; }
preexec_functions+=(te_user_preexec)
precmd_functions+=(te_user_precmd)
''')
        for name in (".zshenv", ".zprofile"):
            put(shim / name, f'''ZDOTDIR=$TE_ORIGINAL_ZDOTDIR
source "$TE_ORIGINAL_ZDOTDIR/{name}"
ZDOTDIR=$TE_SHIM_ZDOTDIR
''')
        put(shim / ".zshrc", '''
ZDOTDIR=$TE_ORIGINAL_ZDOTDIR
source "$TE_ORIGINAL_ZDOTDIR/.zshrc"
te_probe_preexec() {
  (( ++TE_EVENT_SEQ ))
  print -r -- "start|$TE_EVENT_SEQ|$TE_SHELL_EPOCH|${(qqq)1}" >> "$TE_EVENTS"
  print -rn -- $'\\036'"TEF|start|$TE_EVENT_SEQ|$TE_NONCE"$'\\037'
}
te_probe_precmd() {
  local code=$?
  print -r -- "end|$TE_EVENT_SEQ|$TE_SHELL_EPOCH|$code" >> "$TE_EVENTS"
  print -rn -- $'\\036'"TEF|end|$TE_EVENT_SEQ|$TE_NONCE"$'\\037'
}
TE_EVENT_SEQ=0
TE_SHELL_EPOCH="$$:$TE_NONCE"
# Preserve the user's entries and their relative order; capture status first.
precmd_functions=(te_probe_precmd $precmd_functions)
preexec_functions+=(te_probe_preexec)
ZDOTDIR=$TE_ORIGINAL_ZDOTDIR
''')
        commands = ["tealias", "tefunction", "cd / && print -r -- CWD:$PWD",
                    "export TE_EXPORT=ok", "print -r -- EXPORT:$TE_EXPORT",
                    "false", "true | false", "print -r -- $'a\\nb'"]
        env["ZDOTDIR"] = str(shim)
        output, _ = run_shell(env, commands)
        lines = events.read_text(encoding="utf-8").splitlines()
        starts = [line for line in lines if line.startswith("start|")]
        ends = [line for line in lines if line.startswith("end|")]
        assert len(starts) == len(commands) + 1, starts  # exit also fires preexec
        assert len(ends) == len(commands) + 1, ends  # initial prompt
        assert [int(line.rsplit("|", 1)[1]) for line in ends[1:]] == [0, 0, 0, 0, 0, 1, 1, 0]
        assert b"ALIAS_OK" in output and b"FUNCTION_OK" in output
        assert b"CWD:/" in output and b"EXPORT:ok" in output
        assert "tealias" in starts[0]
        assert all(line.count("|te_probe") == 0 for line in starts)
        assert sum(line.startswith("user_preexec:") for line in lines) == len(commands) + 1
        assert output.count(b"TEF|start|") == len(commands) + 1
        assert output.count(b"TEF|end|") == len(commands) + 1
        startup_lines = startup.read_text(encoding="utf-8").splitlines()
        assert [line.split(":", 1)[0] for line in startup_lines] == [".zshenv", ".zshrc"]
        assert all(line.endswith(str(original)) for line in startup_lines)
        print(json.dumps({"zsh": subprocess.check_output([ZSH, "--version"], text=True).strip(),
                          "case": "interactive_nonlogin", "starts": len(starts),
                          "ends": len(ends), "startup": startup_lines,
                          "end_codes": [int(line.rsplit("|", 1)[1]) for line in ends[1:]],
                          "user_hooks_retained": sum(line.startswith("user_preexec:") for line in lines) == len(commands) + 1,
                          "fence_count": output.count(b"TEF|")}, ensure_ascii=False))
        startup.write_text("", encoding="utf-8")
        events.write_text("", encoding="utf-8")
        run_shell(env, ["print -r -- LOGIN:$ZDOTDIR"], login=True)
        login_lines = startup.read_text(encoding="utf-8").splitlines()
        assert [line.split(":", 1)[0] for line in login_lines] == [".zshenv", ".zprofile", ".zshrc", ".zlogin", ".zlogout"]
        assert all(line.endswith(str(original)) for line in login_lines)
        print(json.dumps({"case": "interactive_login", "startup": login_lines}, ensure_ascii=False))
        events.write_text("", encoding="utf-8")
        _, exec_status = run_shell(env, [], final_command="exec /usr/bin/false", expected_status=1)
        exec_lines = events.read_text(encoding="utf-8").splitlines()
        exec_starts = [line for line in exec_lines if line.startswith("start|")]
        exec_ends = [line for line in exec_lines if line.startswith("end|")]
        assert len(exec_starts) == 1 and exec_starts[0].split("|")[1] == "1"
        assert "exec /usr/bin/false" in exec_starts[0]
        assert len(exec_ends) == 1 and exec_ends[0].split("|")[1] == "0"
        print(json.dumps({"case": "exec_replaces_shell", "starts": len(exec_starts),
                          "ends": len(exec_ends), "hook_end_for_exec": False,
                          "fixture_process_status": exec_status}))
        events.write_text("", encoding="utf-8")
        _, exit_status = run_shell(env, [], final_command="exit 7", expected_status=7)
        exit_lines = events.read_text(encoding="utf-8").splitlines()
        exit_starts = [line for line in exit_lines if line.startswith("start|")]
        exit_ends = [line for line in exit_lines if line.startswith("end|")]
        assert len(exit_starts) == 1 and exit_starts[0].split("|")[1] == "1"
        assert "exit 7" in exit_starts[0]
        assert len(exit_ends) == 1 and exit_ends[0].split("|")[1] == "0"
        print(json.dumps({"case": "exit_without_hook_end", "starts": len(exit_starts),
                          "ends": len(exit_ends), "hook_end_for_exit": False,
                          "fixture_process_status": exit_status}))
        events.write_text("", encoding="utf-8")
        env["TE_BG_RELEASE"] = str(root / "bg-release")
        env["TE_BG_MARK"] = f"TE_BG_{nonce}"
        env["TE_FG_MARK"] = f"TE_FG_{nonce}"
        background_output, _ = run_shell(env, [
            '(for i in {1..400}; do [[ -e "$TE_BG_RELEASE" ]] && break; sleep 0.01; done; '
            '[[ -e "$TE_BG_RELEASE" ]] && print -r -- "$TE_BG_MARK") &',
            ': > "$TE_BG_RELEASE"; wait; print -r -- "$TE_FG_MARK"',
        ])
        bg = env["TE_BG_MARK"].encode()
        fg = env["TE_FG_MARK"].encode()
        assert background_output.count(bg) == background_output.count(fg) == 1
        assert (background_output.index(b"TEF|start|2|") < background_output.index(bg)
                < background_output.index(fg) < background_output.index(b"TEF|end|2|"))
        print(json.dumps({"case": "background_output_in_next_interval",
                          "background_within_second_fence": True}))


if __name__ == "__main__":
    main()
