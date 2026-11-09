"""Tests for asc.py's certificate selection: python3 -I -m unittest discover -s apps/ios/scripts/testflight"""

from __future__ import annotations

import os
import subprocess
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import asc  # noqa: E402


def cert(id: str, kind: str, serial: str) -> dict:
    return {"id": id, "attributes": {"certificateType": kind, "serialNumber": serial, "name": id}}


class SerialTests(unittest.TestCase):
    def test_serials_compare_without_case_separators_or_leading_zeros(self):
        self.assertEqual(asc.normalize_serial("0a:1B:2c"), "A1B2C")
        self.assertEqual(asc.normalize_serial(" 00ff\n"), "FF")
        self.assertEqual(asc.normalize_serial("000"), "0")

    def test_openssl_and_app_store_connect_serials_match(self):
        with tempfile.TemporaryDirectory() as tmp:
            key, pem = os.path.join(tmp, "k.pem"), os.path.join(tmp, "c.pem")
            subprocess.run(
                ["openssl", "req", "-x509", "-newkey", "ec", "-pkeyopt", "ec_paramgen_curve:P-256", "-nodes",
                 "-keyout", key, "-out", pem, "-subj", "/CN=test", "-days", "1", "-set_serial", "0x0ABCDEF0123"],
                check=True, capture_output=True,
            )
            text = open(pem).read()
        two = text + "\nnoise\n" + text
        self.assertEqual(len(asc.pem_blocks(two)), 2)
        self.assertEqual(asc.pem_serials(two), {"ABCDEF0123"})


class ToRevokeTests(unittest.TestCase):
    certificates = [
        cert("dev", "DEVELOPMENT", "0ABC"),
        cert("ios-dev", "IOS_DEVELOPMENT", "DEF"),
        cert("dist", "DISTRIBUTION", "ABC"),
        cert("ios-dist", "IOS_DISTRIBUTION", "DEF"),
        cert("other-dev", "DEVELOPMENT", "123"),
    ]

    def test_only_the_runs_development_certificates(self):
        ids = [c["id"] for c in asc.to_revoke(self.certificates, {"ABC", "DEF"})]
        self.assertEqual(ids, ["dev", "ios-dev"])

    def test_distribution_is_never_revoked(self):
        everything = {asc.normalize_serial(c["attributes"]["serialNumber"]) for c in self.certificates}
        kinds = {c["attributes"]["certificateType"] for c in asc.to_revoke(self.certificates, everything)}
        self.assertTrue(kinds <= asc.DEVELOPMENT)

    def test_an_empty_keychain_revokes_nothing(self):
        self.assertEqual(asc.to_revoke(self.certificates, set()), [])


class WhatToTestTests(unittest.TestCase):
    note = "Labs build: do not submit for review"

    def test_an_existing_english_note_is_replaced(self):
        localizations = [
            {"id": "de", "attributes": {"locale": "de-DE"}},
            {"id": "en", "attributes": {"locale": "en-US", "whatsNew": "old"}},
        ]
        method, path, body = asc.what_to_test_request("b1", localizations, self.note)
        self.assertEqual((method, path), ("PATCH", "betaBuildLocalizations/en"))
        self.assertEqual(body["data"]["attributes"], {"whatsNew": self.note})

    def test_a_build_without_a_note_gets_one(self):
        method, path, body = asc.what_to_test_request("b1", [], self.note)
        self.assertEqual((method, path), ("POST", "betaBuildLocalizations"))
        self.assertEqual(body["data"]["attributes"], {"locale": "en-US", "whatsNew": self.note})
        self.assertEqual(body["data"]["relationships"]["build"]["data"], {"type": "builds", "id": "b1"})


@unittest.skipUnless(sys.platform == "darwin", "PlistBuddy and codesign are macOS tools")
class CheckArchiveLabsTests(unittest.TestCase):
    """check-archive.sh's Labs line against a fake archive; the other checks fail there and are ignored."""

    script = os.path.join(os.path.dirname(os.path.abspath(__file__)), "check-archive.sh")

    def labs_errors(self, in_app: str, expect: str | None) -> list[str]:
        with tempfile.TemporaryDirectory() as tmp:
            app = os.path.join(tmp, "a.xcarchive", "Products", "Applications", "Billet.app")
            os.makedirs(app)
            plist = os.path.join(app, "Info.plist")
            subprocess.run(["plutil", "-create", "xml1", plist], check=True)
            subprocess.run(["plutil", "-insert", "BilletLabs", "-string", in_app, plist], check=True)
            env = {k: v for k, v in os.environ.items() if k not in ("EXPECT_LABS", "DEMO_HOST")}
            if expect is not None:
                env["EXPECT_LABS"] = expect
            out = subprocess.run(
                [self.script, os.path.join(tmp, "a.xcarchive"), "1"], env=env, capture_output=True, text=True
            ).stdout
        return [line for line in out.splitlines() if "Labs" in line and line.startswith("::error::")]

    def test_review_builds_must_have_no_labs(self):
        self.assertEqual(self.labs_errors("NO", None), [])
        self.assertEqual(len(self.labs_errors("YES", None)), 1)

    def test_labs_builds_must_have_labs(self):
        self.assertEqual(self.labs_errors("YES", "YES"), [])
        self.assertEqual(len(self.labs_errors("NO", "YES")), 1)

    def test_an_unknown_expectation_fails(self):
        self.assertEqual(len(self.labs_errors("NO", "maybe")), 1)


if __name__ == "__main__":
    unittest.main()
