"""Real controlling-PTY enrollment probe. No credential arguments or logs."""
import json
import os
import pty
import secrets
import select
import subprocess
import sys
import termios
import time

operator, configuration, resource = sys.argv[1:]
master, slave = pty.openpty()
before = termios.tcgetattr(slave)
password = secrets.token_urlsafe(32).encode()
process = subprocess.Popen(["node", operator, "install", "--execute", "--config", configuration], stdin=slave, stdout=slave, stderr=slave, start_new_session=True)
output = bytearray()
sent = 0
deadline = time.monotonic() + 900
try:
    while time.monotonic() < deadline:
        if select.select([master], [], [], 0.2)[0]:
            try:
                block = os.read(master, 65536)
            except OSError:
                break
            if not block:
                break
            output.extend(block)
            if sent == 0 and b"Initial Drumee password: " in output:
                os.write(master, password + b"\n")
                sent = 1
            if sent == 1 and b"Confirm password: " in output:
                os.write(master, password + b"\n")
                sent = 2
        if process.poll() is not None:
            break
    assert process.wait(timeout=5) == 0, "PTY_INSTALL_FAILED"
    assert sent == 2, "CANONICAL_PROMPTS_NOT_OBSERVED"
    assert password not in output, "PASSWORD_ECHOED"
    assert termios.tcgetattr(slave)[3] & termios.ECHO == before[3] & termios.ECHO, "TERMINAL_NOT_RESTORED"
    with open(resource) as credential:
        assert json.load(credential)["password"].encode() == password, "INTERACTIVE_PASSWORD_NOT_PRESERVED"
    print(json.dumps({"pty_no_echo": True, "terminal_restored": True, "credential_matched": True}))
finally:
    if process.poll() is None:
        os.killpg(process.pid, 15)
        process.wait(timeout=10)
    os.close(master)
    os.close(slave)
    output[:] = b"\0" * len(output)
    password = b""
