#!/usr/bin/env python3
"""App Store Connect lookups for the TestFlight workflow, with the standard library only.

    asc.py next-build --floor N        prints the build number to use: the larger of N and one
                                       above the highest build App Store Connect has for the app
    asc.py state --build N [--wait S]  prints "build N: <processing state>", waiting up to S
                                       seconds for the build to appear and leave PROCESSING
    asc.py revoke-run-certificates --keychain PATH
                                       revokes the development certificates in the run's own
                                       keychain, the ones Xcode made through the key this run
    asc.py certificates                lists the team's certificates: type, serial, expiry, name
    asc.py what-to-test --build N --text T
                                       sets build N's TestFlight "What to test" note (en-US) to T

The API key comes from ASC_KEY_ID, ASC_ISSUER_ID and ASC_KEY_PATH (the .p8 file). The app is
found by BUNDLE_ID (default com.ourio.app). Nothing secret is printed.
"""

from __future__ import annotations

import argparse
import base64
import re
import json
import os
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

API = "https://api.appstoreconnect.apple.com/v1"

# Certificate types a CI run may revoke. Distribution certificates sign what testers and the App
# Store install and are never touched here.
DEVELOPMENT = {"DEVELOPMENT", "IOS_DEVELOPMENT", "MAC_APP_DEVELOPMENT"}


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
        return self.call("GET", f"{path}?{urllib.parse.urlencode(query)}")

    def delete(self, path: str) -> None:
        self.call("DELETE", path)

    def send(self, method: str, path: str, body: dict) -> dict:
        return self.call(method, path, body)

    def call(self, method: str, path: str, body: dict | None = None) -> dict:
        headers = {"Authorization": f"Bearer {token(*self.key)}"}
        data = None
        if body is not None:
            headers["Content-Type"] = "application/json"
            data = json.dumps(body).encode()
        request = urllib.request.Request(f"{API}/{path}", data=data, method=method, headers=headers)
        try:
            with urllib.request.urlopen(request, timeout=60) as response:
                body = response.read()
                return json.loads(body) if body else {}
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


def normalize_serial(serial: str) -> str:
    """A serial as App Store Connect and openssl both write it: upper-case hex, no separators or
    leading zeros."""
    return re.sub(r"[^0-9A-F]", "", serial.upper()).lstrip("0") or "0"


def pem_blocks(text: str) -> list[str]:
    return re.findall(r"-----BEGIN CERTIFICATE-----.+?-----END CERTIFICATE-----", text, re.S)


def keychain_serials(keychain: str) -> set[str]:
    pems = subprocess.run(
        ["security", "find-certificate", "-a", "-p", keychain], capture_output=True, text=True
    ).stdout
    return pem_serials(pems)


def pem_serials(pems: str) -> set[str]:
    serials = set()
    for pem in pem_blocks(pems):
        line = subprocess.run(
            ["openssl", "x509", "-noout", "-serial"], input=pem, capture_output=True, text=True, check=True
        ).stdout
        serials.add(normalize_serial(line.split("=", 1)[1]))
    return serials


def to_revoke(certificates: list[dict], serials: set[str]) -> list[dict]:
    """The development certificates among `certificates` whose serial is one of `serials`."""
    return [
        c
        for c in certificates
        if c["attributes"].get("certificateType") in DEVELOPMENT
        and normalize_serial(c["attributes"].get("serialNumber", "")) in serials
    ]


def certificates(client: Client, **filters: str) -> list[dict]:
    query = {"fields[certificates]": "certificateType,serialNumber,name,displayName,expirationDate", "limit": "200"}
    query.update({f"filter[{k}]": v for k, v in filters.items()})
    return client.get("certificates", query)["data"]


def revoke_run_certificates(client: Client, keychain: str) -> list[str]:
    serials = keychain_serials(keychain)
    found = [c for serial in sorted(serials) for c in certificates(client, serialNumber=serial)]
    revoked = []
    for cert in to_revoke(found, serials):
        client.delete(f"certificates/{cert['id']}")
        attributes = cert["attributes"]
        revoked.append(f"{attributes['certificateType']} {attributes.get('name', '')} {attributes['serialNumber']}")
    return revoked


def what_to_test_request(build_id: str, localizations: list[dict], text: str, locale: str = "en-US") -> tuple[str, str, dict]:
    """The call that sets the note: a PATCH of the build's localization for `locale`, or a POST of a new one."""
    for localization in localizations:
        if localization["attributes"].get("locale") == locale:
            body = {"data": {"type": "betaBuildLocalizations", "id": localization["id"], "attributes": {"whatsNew": text}}}
            return "PATCH", f"betaBuildLocalizations/{localization['id']}", body
    body = {
        "data": {
            "type": "betaBuildLocalizations",
            "attributes": {"locale": locale, "whatsNew": text},
            "relationships": {"build": {"data": {"type": "builds", "id": build_id}}},
        }
    }
    return "POST", "betaBuildLocalizations", body


def what_to_test(client: Client, app: str, build: int, text: str) -> None:
    found = client.builds(app, str(build))
    if not found:
        sys.exit(f"asc.py: no build {build} in App Store Connect")
    build_id = found[0]["id"]
    localizations = client.get(f"builds/{build_id}/betaBuildLocalizations", {"limit": "50"})["data"]
    method, path, body = what_to_test_request(build_id, localizations, text)
    client.send(method, path, body)


def main() -> None:
    parser = argparse.ArgumentParser()
    commands = parser.add_subparsers(dest="command", required=True)
    nb = commands.add_parser("next-build")
    nb.add_argument("--floor", type=int, required=True)
    st = commands.add_parser("state")
    st.add_argument("--build", type=int, required=True)
    st.add_argument("--wait", type=int, default=0)
    rv = commands.add_parser("revoke-run-certificates")
    rv.add_argument("--keychain", required=True)
    commands.add_parser("certificates")
    wt = commands.add_parser("what-to-test")
    wt.add_argument("--build", type=int, required=True)
    wt.add_argument("--text", required=True)
    args = parser.parse_args()

    client = Client()
    if args.command == "revoke-run-certificates":
        revoked = revoke_run_certificates(client, args.keychain)
        print("\n".join(f"revoked {line}" for line in revoked) or "no development certificate in the run's keychain")
        return
    if args.command == "certificates":
        for c in certificates(client):
            a = c["attributes"]
            print(a["certificateType"], a["serialNumber"], a.get("expirationDate", "")[:10], a.get("name", ""))
        return
    app = client.app_id(os.environ.get("BUNDLE_ID", "com.ourio.app"))
    if args.command == "what-to-test":
        what_to_test(client, app, args.build, args.text)
        print(f"build {args.build}: What to test set")
    elif args.command == "next-build":
        print(next_build(client, app, args.floor))
    else:
        print(f"build {args.build}: {state(client, app, args.build, args.wait)}")


if __name__ == "__main__":
    main()
