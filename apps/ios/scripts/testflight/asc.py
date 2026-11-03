#!/usr/bin/env python3
"""App Store Connect lookups for the TestFlight workflow, with the standard library only.

    asc.py next-build --floor N        prints the build number to use: the larger of N and one
                                       above the highest build App Store Connect has for the app
    asc.py state --build N [--wait S]  prints "build N: <processing state>", waiting up to S
                                       seconds for the build to appear and leave PROCESSING

The API key comes from ASC_KEY_ID, ASC_ISSUER_ID and ASC_KEY_PATH (the .p8 file). The app is
found by BUNDLE_ID (default com.mikitahimpel.billet). Nothing secret is printed.
"""

from __future__ import annotations

import argparse
import base64
import json
import os
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

API = "https://api.appstoreconnect.apple.com/v1"


def b64url(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode()


def der_to_raw(der: bytes) -> bytes:
    """An ECDSA signature as DER (what openssl writes) to the 64-byte r||s that ES256 wants."""

    def read_int(at: int) -> tuple[bytes, int]:
        if der[at] != 0x02:
            raise ValueError("not a DER integer")
        length = der[at + 1]
        value = der[at + 2 : at + 2 + length]
        return value.lstrip(b"\x00").rjust(32, b"\x00"), at + 2 + length

    if der[0] != 0x30:
        raise ValueError("not a DER sequence")
    at = 3 if der[1] & 0x80 else 2
    r, at = read_int(at)
    s, _ = read_int(at)
    return r + s


def token(key_id: str, issuer: str, key_path: str, now: int | None = None) -> str:
    now = int(time.time()) if now is None else now
    header = {"alg": "ES256", "kid": key_id, "typ": "JWT"}
    claims = {"iss": issuer, "iat": now, "exp": now + 15 * 60, "aud": "appstoreconnect-v1"}
    signing_input = f"{b64url(json.dumps(header).encode())}.{b64url(json.dumps(claims).encode())}"
    der = subprocess.run(
        ["openssl", "dgst", "-sha256", "-sign", key_path],
        input=signing_input.encode(),
        capture_output=True,
        check=True,
    ).stdout
    return f"{signing_input}.{b64url(der_to_raw(der))}"


class Client:
    def __init__(self) -> None:
        missing = [n for n in ("ASC_KEY_ID", "ASC_ISSUER_ID", "ASC_KEY_PATH") if not os.environ.get(n)]
        if missing:
            sys.exit(f"asc.py: {', '.join(missing)} not set")
        self.key = (os.environ["ASC_KEY_ID"], os.environ["ASC_ISSUER_ID"], os.environ["ASC_KEY_PATH"])

    def get(self, path: str, query: dict[str, str]) -> dict:
        url = f"{API}/{path}?{urllib.parse.urlencode(query)}"
        request = urllib.request.Request(url, headers={"Authorization": f"Bearer {token(*self.key)}"})
        try:
            with urllib.request.urlopen(request, timeout=60) as response:
                return json.load(response)
        except urllib.error.HTTPError as error:
            try:
                detail = json.load(error)["errors"][0]
                reason = f"{detail.get('title', '')}: {detail.get('detail', '')}"
            except Exception:
                reason = error.reason
            sys.exit(f"asc.py: App Store Connect said {error.code} for /{path}: {reason}")

    def app_id(self, bundle_id: str) -> str:
        apps = self.get("apps", {"filter[bundleId]": bundle_id, "fields[apps]": "bundleId"})["data"]
        if not apps:
            sys.exit(f"asc.py: no app with bundle ID {bundle_id} in App Store Connect")
        return apps[0]["id"]

    def builds(self, app: str, version: str | None = None) -> list[dict]:
        query = {"filter[app]": app, "fields[builds]": "version,processingState", "limit": "200"}
        if version is not None:
            query["filter[version]"] = version
        else:
            query["sort"] = "-uploadedDate"
        return self.get("builds", query)["data"]


def next_build(client: Client, app: str, floor: int) -> int:
    numbers = [int(b["attributes"]["version"]) for b in client.builds(app) if b["attributes"]["version"].isdigit()]
    return max([floor] + [n + 1 for n in numbers])


def state(client: Client, app: str, build: int, wait: int) -> str:
    deadline = time.time() + wait
    last = "NOT_FOUND"
    while True:
        found = client.builds(app, str(build))
        if found:
            last = found[0]["attributes"]["processingState"]
            if last != "PROCESSING":
                return last
        if time.time() >= deadline:
            return last
        time.sleep(30)


def main() -> None:
    parser = argparse.ArgumentParser()
    commands = parser.add_subparsers(dest="command", required=True)
    nb = commands.add_parser("next-build")
    nb.add_argument("--floor", type=int, required=True)
    st = commands.add_parser("state")
    st.add_argument("--build", type=int, required=True)
    st.add_argument("--wait", type=int, default=0)
    args = parser.parse_args()

    client = Client()
    app = client.app_id(os.environ.get("BUNDLE_ID", "com.mikitahimpel.billet"))
    if args.command == "next-build":
        print(next_build(client, app, args.floor))
    else:
        print(f"build {args.build}: {state(client, app, args.build, args.wait)}")


if __name__ == "__main__":
    main()
