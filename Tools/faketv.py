#!/usr/bin/env python3
"""Falešná televize Samsung pro testování aplikace bez skutečné TV.

Napodobuje WebSocket API Tizenu na portu 8002 (TLS, párování tokenem):
- po připojení pošle `ms.channel.connect` a vrátí token, který dostala (nebo vlastní),
- každou přijatou zprávu vypíše (klávesy, spouštění aplikací, text),
- po klávese Domů (KEY_HOME) pošle `ms.remote.imeStart`, jako by se na TV otevřela klávesnice.

Použití:
    python3 Tools/faketv.py
    xcrun simctl launch booted cz.jakublanger.SamsungTVRemote -tv.testHost 127.0.0.1

Spouštěcí argument `-tv.testHost` přesměruje aplikaci jen pro toto spuštění, uložené nastavení
zůstane beze změny (v aplikaci ale musí být uložená aspoň jedna televize). Hlasitost (UPnP, port 9197) falešná TV neumí.
"""

import base64
import hashlib
import json
import socket
import ssl
import struct
import subprocess
import tempfile
import threading
from pathlib import Path
from urllib.parse import parse_qs, urlparse

PORT = 8002
DEFAULT_TOKEN = "11223344"


def self_signed_certificate() -> tuple[Path, Path]:
    """Televize používá vlastní certifikát, tak si ho vyrobíme taky."""
    folder = Path(tempfile.mkdtemp(prefix="faketv-"))
    cert, key = folder / "cert.pem", folder / "key.pem"
    subprocess.run(
        ["openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes", "-days", "2",
         "-keyout", key, "-out", cert, "-subj", "/CN=SmartViewSDK"],
        check=True, capture_output=True,
    )
    return cert, key


def recv_frame(conn):
    header = conn.recv(2)
    if len(header) < 2:
        return None
    opcode, length = header[0] & 0x0F, header[1] & 0x7F
    if length == 126:
        length = struct.unpack(">H", conn.recv(2))[0]
    elif length == 127:
        length = struct.unpack(">Q", conn.recv(8))[0]
    mask, data = conn.recv(4), b""
    while len(data) < length:
        data += conn.recv(length - len(data))
    return opcode, bytes(b ^ mask[i % 4] for i, b in enumerate(data))


def send_text(conn, payload: dict):
    data = json.dumps(payload).encode()
    header = bytes([0x81])
    header += bytes([len(data)]) if len(data) < 126 else bytes([126]) + struct.pack(">H", len(data))
    conn.sendall(header + data)


def handle(conn):
    request = b""
    while b"\r\n\r\n" not in request:
        request += conn.recv(4096)
    lines = request.decode().split("\r\n")
    url = urlparse(lines[0].split()[1])
    headers = {k.lower(): v.strip() for k, v in (line.split(":", 1) for line in lines[1:] if ":" in line)}
    query = {k: v[0] for k, v in parse_qs(url.query).items()}
    print("CONNECT", url.path, query, flush=True)

    accept = base64.b64encode(hashlib.sha1(
        (headers["sec-websocket-key"] + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11").encode()).digest()).decode()
    conn.sendall(("HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n"
                  f"Sec-WebSocket-Accept: {accept}\r\n\r\n").encode())
    send_text(conn, {"event": "ms.channel.connect",
                     "data": {"id": "faketv", "clients": [], "token": query.get("token", DEFAULT_TOKEN)}})

    try:
        while frame := recv_frame(conn):
            opcode, data = frame
            if opcode == 8:
                break
            if opcode == 1:
                text = data.decode()
                print("RECV", text, flush=True)
                if "KEY_HOME" in text:
                    send_text(conn, {"event": "ms.remote.imeStart", "data": ""})
    except (ConnectionError, ssl.SSLError):
        pass  # aplikace spojení ukončila bez rozloučení (třeba při přechodu na pozadí)
    print("CLOSE", flush=True)


def main():
    cert, key = self_signed_certificate()
    context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    context.load_cert_chain(cert, key)

    server = socket.socket()
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server.bind(("127.0.0.1", PORT))
    server.listen()
    print(f"Falešná TV poslouchá na wss://127.0.0.1:{PORT}", flush=True)
    while True:
        client, _ = server.accept()
        try:
            threading.Thread(target=handle, args=(context.wrap_socket(client, server_side=True),), daemon=True).start()
        except ssl.SSLError as error:
            print("TLS chyba:", error, flush=True)


if __name__ == "__main__":
    main()
