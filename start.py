"""RecSortの静的Web版をlocalhostに配信する起動補助。"""
import argparse
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

def main():
    parser = argparse.ArgumentParser(description="RecSort Web版を起動")
    parser.add_argument("--port", type=int, default=8765)
    args = parser.parse_args()
    directory = Path(__file__).resolve().parent / "dist"
    handler = partial(SimpleHTTPRequestHandler, directory=str(directory))
    SimpleHTTPRequestHandler.extensions_map.update({".mjs": "text/javascript", ".js": "text/javascript"})
    try:
        server = ThreadingHTTPServer(("127.0.0.1", args.port), handler)
    except OSError as error:
        parser.exit(1, f"起動できません: {error}\n別の番号で --port 8766 を試してください。\n")
    print(f"RecSort: http://127.0.0.1:{args.port} (停止: Ctrl+C)", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()

if __name__ == "__main__":
    main()
