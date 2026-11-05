"""Player actions done through the original interface, each checked against
the game's memory. Coordinates are game pixels (640x480)."""

TABS = {"results": 27, "rent": 70, "upgrades": 117, "staff": 160, "marketing": 207, "recipe": 255, "supplies": 296}
ITEMS = ["lemons", "sugar", "ice", "cups"]
ITEM_TAB_X = [50, 112, 170, 230]
PACK_ROW_Y = [282, 321, 360]            # small, medium, large: the "+" buttons at x=244
RECIPE_ROW_Y = [243, 283, 348]          # lemons, sugar, ice: "-" at x=59, "+" at x=169


def _click(x, y, pause=0.12):
    g = game_window()
    lp = (y << 16) | x
    u.PostMessageW(g, 0x0200, 0, lp)
    u.PostMessageW(g, 0x0201, 1, lp)
    time.sleep(0.03)
    u.PostMessageW(g, 0x0202, 0, lp)
    time.sleep(pause)


def _wait_screen(want, timeout=2.0):
    end = time.time() + timeout
    while time.time() < end:
        if screen() == want:
            return True
        time.sleep(0.05)
    return False


def _ready():
    if screen() == "dialog":
        return "busy: a dialog is open"
    if screen() != "plan":
        return "busy: not on the planning screen"
    return None


def buy(counts):
    """counts: 12 numbers, packs to buy (lemons S M L, sugar S M L, ice S M L,
    cups S M L). One basket, one purchase; the confirmation is ticked
    'don't ask again' the first time."""
    err = _ready()
    if err:
        return err
    before = game_state()
    _click(TABS["supplies"], 87, 0.3)
    for item in range(4):
        n = counts[item * 3:item * 3 + 3]
        if not any(n):
            continue
        _click(ITEM_TAB_X[item], 237, 0.25)
        for row, k in enumerate(n):
            for _ in range(k):
                _click(244, PACK_ROW_Y[row], 0.06)
    _click(276, 412, 0.4)
    if _wait_screen("dialog", 0.8):
        _click(185, 272, 0.15)   # don't ask again
        _click(440, 268, 0.4)    # OK
        _wait_screen("plan", 2)
    after = game_state()
    got = [a - b for a, b in zip(after["stock"], before["stock"])]
    spent = before["cash"] - after["cash"]
    return "bought %s spent %d" % (",".join(map(str, got)), spent)


def _adjust(read, minus, plus, target, limit=60):
    for _ in range(limit):
        v = read()
        if v == target:
            return True
        _click(*(plus if v < target else minus), pause=0.08)
    return read() == target


def set_recipe(lemons, sugar, ice):
    err = _ready()
    if err:
        return err
    _click(TABS["recipe"], 87, 0.3)
    ok = True
    for i, target in enumerate((lemons, sugar, ice)):
        y = RECIPE_ROW_Y[i]
        ok &= _adjust(lambda: game_state()["recipe"][i], (59, y), (169, y), target)
    return "ok %s" % game_state()["recipe"] if ok else "partial %s" % game_state()["recipe"]


def set_price(cents):
    err = _ready()
    if err:
        return err
    _click(TABS["marketing"], 87, 0.3)
    ok = _adjust(lambda: game_state()["price"], (42, 222), (162, 222), cents, limit=200)
    return ("ok %d" if ok else "partial %d") % game_state()["price"]


def set_fast(on):
    """Fast-forward during the day: the game's own >> button, toggled only if needed."""
    if screen() != "day":
        return "busy: no day running"
    if (game_state().get("fast") == 1) != on:
        _click(557, 352, 0.3)
    return "ok %d" % game_state().get("fast", 0)


def start_day():
    err = _ready()
    if err:
        return err
    _click(266, 468, 0.3)
    return "ok" if _wait_screen("day", 3) else "no: " + screen()
