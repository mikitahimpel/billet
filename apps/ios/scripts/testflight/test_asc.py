"""Tests for asc.py's certificate selection: python3 -I -m unittest discover -s apps/ios/scripts/testflight"""

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


if __name__ == "__main__":
    unittest.main()
