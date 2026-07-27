import importlib.util
import json
import os
import pathlib
import tempfile
import time
import unittest
from unittest import mock


BRIDGE_PATH = pathlib.Path(__file__).parents[1] / "1337x-flaresolverr-bridge.py"
TEST_STATE = tempfile.TemporaryDirectory()
os.environ["STATE_DIRECTORY"] = TEST_STATE.name
SPEC = importlib.util.spec_from_file_location("bridge_under_test", BRIDGE_PATH)
bridge = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(bridge)


class BridgeTest(unittest.TestCase):
    def setUp(self):
        with bridge.CACHE_LOCK:
            bridge.CACHE.clear()
        with bridge.FLIGHTS_LOCK:
            bridge.FLIGHTS.clear()
        with bridge.CIRCUIT_LOCK:
            for circuit in bridge.CIRCUITS.values():
                circuit["consecutive_failures"] = 0
                circuit["open_until"] = 0
        with bridge.database() as connection:
            connection.execute("DELETE FROM provider_usage")

    def test_classifier_distinguishes_results_empty_and_challenge(self):
        self.assertEqual(
            bridge.classify_1337x_html(
                '<html><a href="/torrent/123/example">result</a></html>'
            ),
            "results",
        )
        self.assertEqual(
            bridge.classify_1337x_html(
                "<html><title>1337x torrent search</title>"
                "No results were returned</html>"
            ),
            "empty",
        )
        self.assertEqual(
            bridge.classify_1337x_html(
                "<html><title>Error something went wrong.</title>"
                "<h1>1337x</h1><p>No results were returned.</p>"
                '<script src="https://static.cloudflareinsights.com/beacon.js">'
                "</script></html>"
            ),
            "empty",
        )
        self.assertEqual(
            bridge.classify_1337x_html(
                "<html><title>Error something went wrong.</title>"
                "Cloudflare Ray ID: example</html>"
            ),
            "challenge",
        )
        self.assertEqual(bridge.classify_1337x_html("<html>unrelated</html>"), "malformed")

    def test_cache_expires(self):
        response = bridge.UpstreamResponse("body", 200, "results")
        with mock.patch.object(bridge.time, "monotonic", return_value=100):
            bridge.cache_put("/search/a/1/", response)
        with mock.patch.object(bridge.time, "monotonic", return_value=129.9):
            self.assertEqual(bridge.cache_get("/search/a/1/"), response)
        with mock.patch.object(bridge.time, "monotonic", return_value=130.1):
            self.assertIsNone(bridge.cache_get("/search/a/1/"))

    def test_single_flight_coalesces_same_path_only(self):
        leader, first = bridge.begin_flight("/search/a/1/")
        follower, second = bridge.begin_flight("/search/a/1/")
        other_leader, other = bridge.begin_flight("/search/b/1/")
        self.assertTrue(leader)
        self.assertFalse(follower)
        self.assertIs(first, second)
        self.assertTrue(other_leader)
        self.assertIsNot(first, other)
        bridge.end_flight("/search/a/1/")
        bridge.end_flight("/search/b/1/")
        self.assertTrue(first.is_set())
        self.assertTrue(other.is_set())

    def test_local_circuit_opens_after_three_failures(self):
        for _ in range(3):
            bridge.update_circuit("flaresolverr", False, "challenge")
        self.assertFalse(bridge.circuit_available("flaresolverr"))
        bridge.update_circuit("flaresolverr", True)
        self.assertTrue(bridge.circuit_available("flaresolverr"))

    def test_metered_kernel_circuit_opens_after_two_failures(self):
        for _ in range(2):
            bridge.update_circuit("kernel", False, "challenge")
        self.assertFalse(bridge.circuit_available("kernel"))

    def test_valid_empty_does_not_open_circuit(self):
        response = bridge.validated_response(
            "<html><title>1337x search torrents</title>No torrents found</html>"
        )
        self.assertEqual(response.outcome, "empty")
        bridge.update_circuit("flaresolverr", True)
        self.assertTrue(bridge.circuit_available("flaresolverr"))

    def test_kernel_fails_closed_when_billing_is_stale(self):
        with bridge.database() as connection:
            connection.execute(
                "INSERT INTO provider_usage(provider, fetched_at, payload) VALUES (?, ?, ?)",
                (
                    "kernel_billing",
                    time.time() - bridge.KERNEL_BILLING_MAX_AGE_SECONDS - 1,
                    json.dumps({"spent_usd": 0}),
                ),
            )
        with self.assertRaisesRegex(bridge.ProviderError, "stale"):
            bridge.enforce_kernel_cap()

    def test_kernel_hard_cap(self):
        bridge.store_usage(
            "kernel_billing", {"spent_usd": bridge.KERNEL_SPEND_LIMIT_USD}
        )
        with self.assertRaisesRegex(bridge.ProviderError, "limit"):
            bridge.enforce_kernel_cap()

    def test_kernel_create_timeout_cleans_new_session(self):
        active = [
            {"old"},
            {"old", "orphan"},
        ]
        deleted = []
        with (
            mock.patch.object(
                bridge, "kernel_active_session_ids", side_effect=active
            ),
            mock.patch.object(
                bridge, "delete_kernel_session", side_effect=deleted.append
            ),
        ):
            removed = bridge.cleanup_new_kernel_sessions({"old"})
        self.assertEqual(removed, ["orphan"])
        self.assertEqual(deleted, ["orphan"])


if __name__ == "__main__":
    unittest.main()
