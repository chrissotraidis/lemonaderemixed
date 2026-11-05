"""The bridge: a localhost TCP server inside Wine through which the app drives
the original game. One command per line, one reply line each:

  ping                          pong
  state                         stopped | starting | needs-key | game
  info                          game state as one line of JSON (gamestate.py)
  buy N*12                      buy packs: lemons S M L, sugar S M L, ice S M L,
                                cups S M L (actions.py)
  recipe L S I | price CENTS | startday | fast on|off | skip
  move X Y | down X Y | up X Y | tap X Y
                                mouse input at game coordinates (640x480)
  char TEXT                     type characters
  register NAME<TAB>KEY         fill in Armadillo's registration dialog:
                                ok | invalid | no-dialog | timeout
  quit                          ask the game to close
"""
import os
import socket
import threading

GAME_TITLE = "Lemonade Tycoon Deluxe"
KEY_DIALOGS = ("Reminder", "Enter Key", "Error!")
PORT = int(os.environ.get("REMIX_PORT", "47123"))
BM_CLICK = 0x00F5


def visible(title):
    for h in windows():
        if u.IsWindowVisible(h) and text(h) == title:
            return h


def wait_for(titles, timeout):
    end = time.time() + timeout
    while time.time() < end:
        for t in titles:
            h = visible(t)
            if h:
                return t, h
        time.sleep(0.1)
    return None, None


def button(dialog, label):
    for c in children(dialog):
        if text(c).replace("&", "") == label:
            return c


def game_window():
    return visible(GAME_TITLE)


def state():
    if any(visible(t) for t in KEY_DIALOGS):
        return "needs-key"
    if game_window():
        return "game"
    proc = globals().get("GAME_PROC")
    return "starting" if proc is not None and proc.poll() is None else "stopped"


def register(name, key):
    if visible("Error!"):
        u.PostMessageW(button(visible("Error!"), "OK"), BM_CLICK, 0, 0)
        time.sleep(0.3)
    if not visible("Enter Key"):
        reminder = visible("Reminder")
        if not reminder:
            return "no-dialog"
        u.PostMessageW(button(reminder, "Enter Key"), BM_CLICK, 0, 0)
    _, dialog = wait_for(["Enter Key"], 5)
    if not dialog:
        return "no-dialog"
    fields = {u.GetDlgCtrlID(c): c for c in children(dialog)}
    for field, value in ((1031, name), (1045, key)):
        u.SendMessageW(fields[field], 0x00B1, 0, -1)   # select all
        u.SendMessageW(fields[field], 0x0303, 0, 0)    # clear
        for ch in value:
            u.PostMessageW(fields[field], 0x0102, ord(ch), 1)
    time.sleep(0.4)
    u.PostMessageW(fields[1], BM_CLICK, 0, 0)
    title, result = wait_for(["Key Valid", "Error!"], 8)
    if title == "Key Valid":
        u.PostMessageW(button(result, "OK"), BM_CLICK, 0, 0)
        return "ok"
    if title == "Error!":
        u.PostMessageW(button(result, "OK"), BM_CLICK, 0, 0)
        return "invalid"
    return "timeout"


def handle(line):
    parts = line.split(" ", 1)
    cmd, arg = parts[0], parts[1] if len(parts) > 1 else ""
    if cmd == "ping":
        return "pong"
    if cmd == "state":
        return state()
    if cmd == "info":
        return game_state_json()
    if cmd == "buy":
        return buy([int(v) for v in arg.split()])
    if cmd == "recipe":
        return set_recipe(*[int(v) for v in arg.split()])
    if cmd == "price":
        return set_price(int(arg))
    if cmd == "fast":
        return set_fast(arg.strip() == "on")
    if cmd == "startday":
        return start_day()
    if cmd == "skip":
        return skip_day()
    if cmd == "register":
        name, _, key = arg.partition("\t")
        return register(name, key)
    g = game_window()
    if not g:
        return "no-game"
    if cmd in ("move", "down", "up", "tap"):
        x, y = (int(float(v)) for v in arg.split())
        lp = (max(0, y) << 16) | (max(0, x) & 0xFFFF)
        if cmd in ("move", "down", "tap"):
            u.PostMessageW(g, 0x0200, 0, lp)
        if cmd in ("down", "tap"):
            u.PostMessageW(g, 0x0201, 1, lp)
        if cmd == "tap":
            time.sleep(0.05)
        if cmd in ("up", "tap"):
            u.PostMessageW(g, 0x0202, 0, lp)
    elif cmd == "char":
        for ch in arg:
            u.PostMessageW(g, 0x0102, ord(ch), 1)
    elif cmd == "quit":
        u.PostMessageW(g, 0x0010, 0, 0)   # WM_CLOSE
    else:
        return "unknown"
    return "ok"


def client(conn):
    with conn, conn.makefile("rw", newline="\n") as f:
        for line in f:
            try:
                f.write(handle(line.rstrip("\n")) + "\n")
            except Exception as e:
                f.write("error " + repr(e) + "\n")
            f.flush()


def serve_bridge():
    s = socket.socket()
    s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    s.bind(("127.0.0.1", PORT))
    s.listen(4)
    while True:
        conn, _ = s.accept()
        threading.Thread(target=client, args=(conn,), daemon=True).start()


threading.Thread(target=serve_bridge, daemon=True).start()
