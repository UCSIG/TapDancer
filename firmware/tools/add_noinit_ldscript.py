"""Swap the framework's bare device linker script for our wrapper, which
INCLUDEs it and adds a .noinit RAM section (see ldscript_noinit.ld).

We must replace (not just append) the device script: GNU ld's INSERT AFTER .bss
only resolves within a single script, so the device script has to be INCLUDEd by
ours rather than passed as a separate -T. Done from a script (not build_flags)
to normalize the path with forward slashes — ${PROJECT_DIR} mangles backslashes
on Windows.
"""
import os

Import("env")  # noqa: F821  (provided by PlatformIO)

# Drop the framework's "-T <device>.ld"; our wrapper INCLUDEs it instead.
linkflags = env["LINKFLAGS"]  # noqa: F821
cleaned = []
skip_next = False
for flag in linkflags:
    if skip_next:
        skip_next = False
        continue
    if flag == "-T":
        skip_next = True  # also drop the following script filename
        continue
    if flag.endswith(".ld"):
        continue
    cleaned.append(flag)

ld_path = os.path.join(env["PROJECT_DIR"], "ldscript_noinit.ld").replace("\\", "/")  # noqa: F821
cleaned += ["-T", ld_path]
env.Replace(LINKFLAGS=cleaned)  # noqa: F821
