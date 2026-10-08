"""Synthetic regression tests for the CI helpers; no accounts or devices used."""

import contextlib
import importlib.util
import io
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch


HELPERS = Path(__file__).resolve().parents[1]


def load_helper(name):
    spec = importlib.util.spec_from_file_location(name, HELPERS / f"{name}.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


safety = load_helper("check_repository_safety")
runner = load_helper("run_tests")


class RepositorySafetyTests(unittest.TestCase):
    def test_ordinary_source_is_allowed(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "fixture.swift"
            path.write_text("let amount = 12.34\n")
            self.assertIsNone(safety.inspect_file(path))

    def test_credentials_and_recovery_files_are_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            for name in ["signing.p12", "auth.p8", ".env.production", "history.sqlite", "app.store-wal", "user-backup.json"]:
                with self.subTest(name=name):
                    path = Path(directory) / name
                    path.write_text("fictional fixture")
                    self.assertIsNotNone(safety.inspect_file(path))

    def test_secret_across_stream_boundary_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "fixture.txt"
            marker = "ghp_" + "A" * 36
            path.write_bytes(b" " * (1024 * 1024 - 8) + marker.encode())
            self.assertEqual(safety.inspect_file(path), "possible secret signature")

    def test_symlinks_are_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / "ordinary.txt"
            source.write_text("synthetic")
            link = Path(directory) / "external"
            link.symlink_to(source)
            self.assertIsNotNone(safety.inspect_file(link))

    def test_rejection_does_not_echo_secret(self):
        with tempfile.TemporaryDirectory() as directory:
            fixture = Path(directory)
            marker = "ghp_" + "A" * 36
            (fixture / "fixture.txt").write_text(marker)
            captured = io.StringIO()
            def git_output(command, **kwargs):
                if command[1] == "rev-parse":
                    return str(fixture) + "\n"
                return b"fixture.txt\0"
            with patch.object(safety.subprocess, "check_output", side_effect=git_output), contextlib.redirect_stderr(captured):
                self.assertEqual(safety.main(), 1)
            self.assertNotIn(marker, captured.getvalue())


class SimulatorRunnerTests(unittest.TestCase):
    owned_uuid = "01234567-89AB-CDEF-0123-456789ABCDEF"
    phone = {"name": "iPhone 17e", "identifier": "fictional-device", "productFamily": "iPhone"}
    runtime = {
        "isAvailable": True, "identifier": "com.apple.CoreSimulator.SimRuntime.iOS-26-5",
        "supportedDeviceTypes": [phone], "version": "26.5", "name": "iOS 26.5", "buildversion": "synthetic",
    }

    def arguments(self, directory):
        return ["run_tests", "--configuration", "Debug", "--xcode-version", "26.6", "--ios-major", "26", "--output-dir", directory]

    def test_selection_stays_in_requested_os_major(self):
        old = dict(self.runtime, version="26.3")
        future = dict(self.runtime, version="27.0")
        self.assertEqual(runner.simulator_profile([old, future, self.runtime], 26), (self.runtime, self.phone))

    def test_unavailable_runtime_fails(self):
        with self.assertRaises(RuntimeError):
            runner.simulator_profile([dict(self.runtime, isAvailable=False)], 26)

    def test_wrong_xcode_fails_before_device_creation(self):
        with patch.dict(os.environ, {"GITHUB_ACTIONS": "false"}), patch.object(runner, "output", return_value="Xcode 26.5\nBuild synthetic") as command, patch("sys.argv", self.arguments("/private/tmp/unused-ci-fixture")):
            with self.assertRaises(RuntimeError):
                runner.main()
            self.assertEqual(command.call_count, 1)

    def test_private_repository_fails_before_tool_execution(self):
        with tempfile.TemporaryDirectory() as directory:
            event = Path(directory) / "event.json"
            event.write_text(json.dumps({"repository": {"private": True}}))
            with patch.dict(os.environ, {"GITHUB_ACTIONS": "true", "GITHUB_EVENT_PATH": str(event)}), patch.object(runner, "output") as command, patch("sys.argv", self.arguments(directory)):
                with self.assertRaises(RuntimeError):
                    runner.main()
                command.assert_not_called()

    def test_failed_test_run_cleans_up_only_owned_device(self):
        with tempfile.TemporaryDirectory() as directory:
            def execute(command, **kwargs):
                if command[0] == "xcodebuild":
                    self.assertIn("CODE_SIGNING_ALLOWED=NO", command)
                    return subprocess.CompletedProcess(command, 65)
                return subprocess.CompletedProcess(command, 0)
            with patch.dict(os.environ, {"GITHUB_ACTIONS": "false"}), patch("sys.argv", self.arguments(directory)), patch.object(runner, "output", side_effect=["Xcode 26.6\nBuild synthetic", json.dumps({"runtimes": [self.runtime]}), self.owned_uuid]), patch.object(runner.subprocess, "run", side_effect=execute) as commands, contextlib.redirect_stdout(io.StringIO()):
                self.assertEqual(runner.main(), 65)
                cleanup = [call.args[0] for call in commands.call_args_list if "delete" in call.args[0]]
                self.assertEqual(cleanup, [["xcrun", "simctl", "delete", self.owned_uuid]])

    def test_zero_tests_cannot_pass(self):
        with tempfile.TemporaryDirectory() as directory:
            def execute(command, **kwargs):
                if command[0] == "xcodebuild":
                    Path(command[command.index("-resultBundlePath") + 1]).mkdir()
                return subprocess.CompletedProcess(command, 0)
            summary = {"totalTestCount": 0, "passedTests": 0, "failedTests": 0, "skippedTests": 0}
            with patch.dict(os.environ, {"GITHUB_ACTIONS": "false", "GITHUB_STEP_SUMMARY": ""}), patch("sys.argv", self.arguments(directory)), patch.object(runner, "output", side_effect=["Xcode 26.6\nBuild synthetic", json.dumps({"runtimes": [self.runtime]}), self.owned_uuid, json.dumps(summary)]), patch.object(runner.subprocess, "run", side_effect=execute), contextlib.redirect_stdout(io.StringIO()):
                self.assertEqual(runner.main(), 1)


if __name__ == "__main__":
    unittest.main()
