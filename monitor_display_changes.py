from __future__ import annotations

import ctypes
from ctypes import wintypes
from pathlib import Path
import subprocess
import sys
import time


ROOT = Path(__file__).resolve().parent
UPDATER = ROOT / "update_moon_from_nasa.py"
CREATE_NO_WINDOW = getattr(subprocess, "CREATE_NO_WINDOW", 0)


class RECT(ctypes.Structure):
    _fields_ = [
        ("left", ctypes.c_long),
        ("top", ctypes.c_long),
        ("right", ctypes.c_long),
        ("bottom", ctypes.c_long),
    ]


def display_signature() -> tuple[tuple[int, int, int, int], ...]:
    """Return the physical rectangles of all currently active monitors."""
    user32 = ctypes.windll.user32
    user32.SetProcessDPIAware()
    rectangles: list[tuple[int, int, int, int]] = []
    callback_type = ctypes.WINFUNCTYPE(
        ctypes.c_bool,
        wintypes.HMONITOR,
        wintypes.HDC,
        ctypes.POINTER(RECT),
        wintypes.LPARAM,
    )

    def collect(_monitor, _device_context, rect_pointer, _data):
        rect = rect_pointer.contents
        rectangles.append((rect.left, rect.top, rect.right, rect.bottom))
        return True

    callback = callback_type(collect)
    if not user32.EnumDisplayMonitors(None, None, callback, 0):
        raise ctypes.WinError()
    return tuple(sorted(rectangles))


def run_update() -> None:
    subprocess.run(
        [sys.executable, str(UPDATER)],
        cwd=ROOT,
        creationflags=CREATE_NO_WINDOW,
        check=False,
    )


def main() -> int:
    # Apply the correct layout immediately when the watcher starts at logon.
    run_update()
    signature = display_signature()
    while True:
        time.sleep(5)
        candidate = display_signature()
        if candidate == signature:
            continue
        # Display topology briefly passes through intermediate states while a
        # dock or cable is connecting. Wait for a stable second observation.
        time.sleep(2)
        confirmed = display_signature()
        if confirmed != candidate:
            signature = confirmed
            continue
        signature = confirmed
        run_update()


if __name__ == "__main__":
    raise SystemExit(main())
