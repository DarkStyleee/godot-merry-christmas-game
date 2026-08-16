# -*- coding: utf-8 -*-
"""
Локальный запуск игры с автосохранением рекордов в файл.

Страница, открытая двойным кликом (file://), писать на диск не может — это
запрет браузера. Поэтому здесь крошечный сервер: отдаёт папку игры и
принимает POST /records, записывая records.js рядом с index.html. Файл
переезжает вместе с папкой.

Запуск:  python server.py   (или двойной клик по start.bat)
"""
import http.server
import json
import os
import re
import sys
import threading
import webbrowser

# Консоль Windows живёт в OEM-кодировке. Python пишет в неё через Unicode API,
# но если вывод перенаправят в файл или конвейер, он свалится на локаль и может
# упасть на кириллице. Явно фиксируем UTF-8 и не падаем на неподдерживаемом.
for _s in (sys.stdout, sys.stderr):
    try:
        _s.reconfigure(encoding="utf-8", errors="replace")
    except (AttributeError, ValueError):
        pass

ROOT = os.path.dirname(os.path.abspath(__file__))
RECORDS = os.path.join(ROOT, "records.js")
PORTS = (8731, 8732, 8733, 8734)
MAX_BODY = 64 * 1024
KEY_RE = re.compile(r"^[a-z][a-z0-9_]{0,31}$")


def sanitize(data):
    """Сервер слушает пусть и локально, но данные всё равно приходят снаружи:
    пропускаем только известную форму и разумные диапазоны."""
    out = {}
    if not isinstance(data, dict):
        return out
    for key, val in list(data.items())[:32]:
        if not isinstance(key, str) or not KEY_RE.match(key):
            continue
        if not isinstance(val, dict):
            continue
        try:
            score = int(val.get("score", 0))
            streak = int(val.get("streak", 0))
            time_s = int(val.get("time", 0))
        except (TypeError, ValueError):
            continue
        if not (0 <= score <= 10 ** 12 and 0 <= streak <= 10 ** 9 and 0 <= time_s <= 10 ** 7):
            continue
        out[key] = {"score": score, "streak": streak, "time": time_s}
    return out


def write_records(rec):
    # Клиент всегда шлёт полное состояние, поэтому пустой набор означает либо
    # чистый старт, либо испорченный запрос. Затирать им уже накопленное нельзя.
    if not rec and os.path.exists(RECORDS) and os.path.getsize(RECORDS) > 0:
        return
    text = ("// Рекорды «Merry Christmas». Пишется автоматически при запуске\n"
            "// через start.bat. Переезжает вместе с папкой игры.\n"
            "window.RECORDS = " + json.dumps(rec, ensure_ascii=False, indent=2) + ";\n")
    tmp = RECORDS + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        f.write(text)
    os.replace(tmp, RECORDS)          # атомарно: не оставим обрезанный файл


class Handler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *a, **kw):
        super().__init__(*a, directory=ROOT, **kw)

    def end_headers(self):
        # без этого браузер отдаст закешированный records.js и рекорды
        # «откатятся» на предыдущий запуск
        self.send_header("Cache-Control", "no-store")
        super().end_headers()

    def do_POST(self):
        if self.path.rstrip("/").rsplit("/", 1)[-1] != "records":
            self.send_error(404)
            return
        try:
            length = int(self.headers.get("Content-Length") or 0)
        except ValueError:
            self.send_error(400)
            return
        if length <= 0 or length > MAX_BODY:
            self.send_error(413)
            return
        try:
            data = json.loads(self.rfile.read(length).decode("utf-8"))
        except (UnicodeDecodeError, ValueError):
            self.send_error(400)
            return
        try:
            write_records(sanitize(data))
        except OSError as e:
            self.send_error(500, str(e))
            return
        self.send_response(204)
        self.end_headers()

    def log_message(self, *args):
        pass                           # не засоряем консоль каждой картинкой


def main():
    for port in PORTS:
        try:
            srv = http.server.ThreadingHTTPServer(("127.0.0.1", port), Handler)
            break
        except OSError:
            continue
    else:
        print("Не удалось занять ни один порт из", PORTS)
        return 1

    url = "http://127.0.0.1:%d/index.html" % port
    print("\n  Merry Christmas запущена: " + url +
          "\n  Рекорды пишутся в " + RECORDS +
          "\n  Закройте это окно, чтобы остановить игру.\n", flush=True)
    if "--no-open" not in sys.argv:
        threading.Timer(0.5, lambda: webbrowser.open(url)).start()
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        pass
    return 0


if __name__ == "__main__":
    sys.exit(main())
