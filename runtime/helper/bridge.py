"""Input bridge: a localhost TCP server inside Wine that forwards mouse and
keyboard input to the game window. One command per line:

  move X Y | down X Y | up X Y | tap X Y      client coordinates (640x480)
  char TEXT                                    type characters
  ping                                         replies "pong"
"""
import socket
import threading

GAME_TITLE = "Lemonade Tycoon Deluxe"
PORT = 47123


def game_window():
    for h in windows():
        if u.IsWindowVisible(h) and text(h) == GAME_TITLE:
            return h


def handle(line):
    parts = line.split(" ", 1)
    cmd, arg = parts[0], parts[1] if len(parts) > 1 else ""
    if cmd == "ping":
        return "pong"
    g = game_window()
    if not g:
        return "no-game"
    if cmd in ("move", "down", "up", "tap"):
        x, y = (int(float(v)) for v in arg.split())
        lp = (max(0, y) << 16) | (max(0, x) & 0xFFFF)
        if cmd == "move":
            u.PostMessageW(g, 0x0200, 0, lp)
        elif cmd == "down":
            u.PostMessageW(g, 0x0200, 0, lp)
            u.PostMessageW(g, 0x0201, 1, lp)
        elif cmd == "up":
            u.PostMessageW(g, 0x0202, 0, lp)
        else:
            u.PostMessageW(g, 0x0200, 0, lp)
            u.PostMessageW(g, 0x0201, 1, lp)
            time.sleep(0.05)
            u.PostMessageW(g, 0x0202, 0, lp)
    elif cmd == "char":
        for ch in arg:
            u.PostMessageW(g, 0x0102, ord(ch), 1)
    return "ok"


def client(conn):
    with conn, conn.makefile("rw", newline="\n") as f:
        for line in f:
            try:
                f.write(handle(line.strip()) + "\n")
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
