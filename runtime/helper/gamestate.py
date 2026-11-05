"""Game state: values read from the game's memory (see docs/STATE.md) and
the current screen, worked out from a few pixels of the latest frame."""
import ctypes
import json
import os
import struct
from ctypes import wintypes as _W

_K32 = ctypes.WinDLL("kernel32")
_K32.OpenProcess.restype = _W.HANDLE
_K32.ReadProcessMemory.argtypes = [_W.HANDLE, ctypes.c_void_p, ctypes.c_void_p, ctypes.c_size_t,
                                   ctypes.POINTER(ctypes.c_size_t)]
_GAME = {"pid": None, "handle": None}


def _handle():
    g = game_window()
    if not g:
        return None
    pid = _W.DWORD()
    u.GetWindowThreadProcessId(g, ctypes.byref(pid))
    if pid.value != _GAME["pid"]:
        _GAME["pid"] = pid.value
        _GAME["handle"] = _W.HANDLE(_K32.OpenProcess(0x0410, False, pid.value))
    return _GAME["handle"]


def _read(h, addr, n):
    buf = ctypes.create_string_buffer(n)
    got = ctypes.c_size_t()
    _K32.ReadProcessMemory(h, ctypes.c_void_p(addr), buf, n, ctypes.byref(got))
    return buf.raw[:got.value]


def _ints(h, addr, count):
    data = _read(h, addr, 4 * count)
    return struct.unpack("<%di" % count, data) if len(data) == 4 * count else (0,) * count


def _near(c, target, tol=24):
    return all(abs(a - b) <= tol for a, b in zip(c, target))


def screen():
    """menu | plan | day | dialog | unknown, from the latest frame."""
    path = os.path.join(globals().get("GAME_DIR", ""), "remix-frames.bin")
    try:
        with open(path, "rb") as f:
            head = f.read(64)
            if head[:4] != b"LRFT":
                return "unknown"
            latest = struct.unpack_from("<I", head, 20)[0] & 1
            base = 64 + latest * 640 * 480 * 4

            def px(x, y):
                f.seek(base + (y * 640 + x) * 4)
                b, g, r, _ = f.read(4)
                return (r, g, b)

            lemon = px(20, 15)
            if _near(lemon, (255, 255, 74)):
                if _near(px(266, 468), (115, 203, 33)):
                    return "plan"
                if _near(px(603, 352), (115, 203, 33)):
                    return "day"
                return "unknown"
            if _near(lemon, (123, 125, 33)):
                return "dialog"
            return "menu"
    except OSError:
        return "unknown"


def game_state():
    h = _handle()
    if not h:
        return {"screen": "stopped"}
    price, lemons_r, sugar_r, ice_r = _ints(h, 0x63D5A4, 4)
    lemons, sugar, ice, cups = _ints(h, 0x63D5E4, 4)
    cash = _ints(h, 0x63D5F8, 1)[0]
    wx = _ints(h, 0x53C7E4, 3)
    day = _ints(h, 0x53C7F0, 1)[0]
    temps = _ints(h, 0x53C7F4, 3)
    running = _ints(h, 0x53C804, 1)[0]
    location = _ints(h, 0x53C808, 1)[0]
    sold, profit = _ints(h, 0x63D580, 2)
    missed = _ints(h, 0x63D590, 1)[0]
    walk_price, walk_wait = _ints(h, 0x541988, 2)
    r_sold = _ints(h, 0x54199C, 1)[0]
    revenue, used, lost, rent_paid, marketing = _ints(h, 0x5419AC, 5)
    melted = _ints(h, 0x541B44, 1)[0]
    rents = [_ints(h, 0x5B9260 + 32 * k, 1)[0] for k in range(10)]
    return {
        "screen": screen(), "cash": cash, "price": price,
        "recipe": [lemons_r, sugar_r, ice_r], "stock": [lemons, sugar, ice, cups],
        "day": day, "weather": list(wx), "tempsC": list(temps), "running": running,
        "location": location, "rent": rents[location] if 0 <= location < 10 else 0,
        "today": {"sold": sold, "profit": profit, "missed": missed},
        "report": {"sold": r_sold, "revenue": revenue, "used": used, "lost": lost, "rent": rent_paid,
                   "marketing": marketing, "earnings": profit, "missed": walk_price + walk_wait,
                   "melted": melted},
    }


def game_state_json():
    return json.dumps(game_state(), separators=(",", ":"))
