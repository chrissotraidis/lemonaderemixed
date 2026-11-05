"""Drive the original game's windows from inside Wine.

  python winctl.py serve [GAME_DIR]           launch the game and serve the
                                              bridge (see bridge.py)
  python winctl.py list                       top-level windows
  python winctl.py tree <hwnd>                child controls of a window
  python winctl.py click <hwnd>               BM_CLICK a button
  python winctl.py settext <hwnd> <text>      WM_SETTEXT an edit control
  python winctl.py tap <hwnd> <x> <y>         left click at client x,y
  python winctl.py key <hwnd> <vk>            press a virtual key
"""
import ctypes
import sys
import time
from ctypes import wintypes as W

u = ctypes.WinDLL("user32", use_last_error=True)
u.SendMessageW.argtypes = [W.HWND, W.UINT, W.WPARAM, W.LPARAM]
u.SendMessageW.restype = W.LPARAM
u.PostMessageW.argtypes = [W.HWND, W.UINT, W.WPARAM, W.LPARAM]
ENUM = ctypes.WINFUNCTYPE(W.BOOL, W.HWND, W.LPARAM)


def text(h):
    buf = ctypes.create_unicode_buffer(512)
    u.GetWindowTextW(h, buf, 512)
    return buf.value


def cls(h):
    buf = ctypes.create_unicode_buffer(256)
    u.GetClassNameW(h, buf, 256)
    return buf.value


def rect(h):
    r = W.RECT()
    u.GetWindowRect(h, ctypes.byref(r))
    return r.left, r.top, r.right - r.left, r.bottom - r.top


def describe(h):
    pid = W.DWORD()
    u.GetWindowThreadProcessId(h, ctypes.byref(pid))
    vis = "vis" if u.IsWindowVisible(h) else "hid"
    return f"{h:#x} pid={pid.value} {vis} {cls(h)!r} {text(h)!r} {rect(h)}"


def windows():
    out = []
    u.EnumWindows(ENUM(lambda h, _: out.append(h) or True), 0)
    return out


def children(h):
    out = []
    u.EnumChildWindows(h, ENUM(lambda c, _: out.append(c) or True), 0)
    return out


def main(a):
    cmd = a[0]
    if cmd == "list":
        for h in windows():
            if u.IsWindowVisible(h):
                print(describe(h))
    elif cmd == "tree":
        for c in children(int(a[1], 0)):
            print(describe(c), "id=", u.GetDlgCtrlID(c))
    elif cmd == "click":
        u.SendMessageW(int(a[1], 0), 0x00F5, 0, 0)  # BM_CLICK
    elif cmd == "settext":
        u.SendMessageW(int(a[1], 0), 0x000C, 0, ctypes.c_wchar_p(a[2]))
    elif cmd == "tap":
        h, x, y = int(a[1], 0), int(a[2]), int(a[3])
        lp = (y << 16) | (x & 0xFFFF)
        u.PostMessageW(h, 0x0200, 0, lp)  # WM_MOUSEMOVE
        time.sleep(0.05)
        u.PostMessageW(h, 0x0201, 1, lp)  # WM_LBUTTONDOWN
        time.sleep(0.08)
        u.PostMessageW(h, 0x0202, 0, lp)  # WM_LBUTTONUP
    elif cmd == "serve":
        # Launch the game and serve the bridge, then run q\<n>.py files as they
        # appear (a research channel), writing their output to <n>.out. This
        # process must start the game and outlive it: Armadillo closes the
        # game when any other Windows process starts beside it.
        import contextlib, glob, io, os, subprocess
        global GAME_PROC, GAME_DIR
        game = a[1] if len(a) > 1 else r"C:\Program Files (x86)\Lemonade Tycoon Deluxe"
        GAME_DIR = game
        here = os.path.dirname(os.path.abspath(__file__))
        GAME_PROC = subprocess.Popen([os.path.join(game, "Lemonade.exe")], cwd=game)
        exec(open(os.path.join(here, "bridge.py")).read(), globals())
        exec(open(os.path.join(here, "gamestate.py")).read(), globals())
        exec(open(os.path.join(here, "actions.py")).read(), globals())
        q = os.path.join(here, "q")
        os.makedirs(q, exist_ok=True)
        while True:
            for f in sorted(glob.glob(q + r"\*.py")):
                buf = io.StringIO()
                with contextlib.redirect_stdout(buf):
                    try:
                        exec(open(f).read(), globals())
                    except Exception as e:
                        print("ERROR", repr(e))
                os.replace(f, f[:-3] + ".done")
                with open(f[:-3] + ".out", "w") as o:
                    o.write(buf.getvalue())
            time.sleep(0.1)
    elif cmd == "run":
        exec(open(a[1]).read(), globals())
    elif cmd == "key":
        h, vk = int(a[1], 0), int(a[2], 0)
        u.PostMessageW(h, 0x0100, vk, 0)
        time.sleep(0.05)
        u.PostMessageW(h, 0x0101, vk, 0)
    else:
        print(__doc__)


if __name__ == "__main__":
    main(sys.argv[1:] or ["help"])
