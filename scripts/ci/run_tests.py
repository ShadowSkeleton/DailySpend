#!/usr/bin/env python3
"""Run DailySpend tests on a newly created simulator, never an existing one."""

import argparse
import json
from pathlib import Path
import re
import subprocess
import sys
import uuid
import os


def output(*command: str) -> str:
    return subprocess.check_output(command, text=True).strip()


def simulator_profile(runtimes: list[dict], major: int) -> tuple[dict, dict]:
    available = [
        runtime for runtime in runtimes
        if runtime.get("isAvailable")
        and runtime["identifier"].startswith("com.apple.CoreSimulator.SimRuntime.iOS-")
        and int(runtime["version"].split(".")[0]) == major
    ]
    if not available:
        raise RuntimeError(f"No installed, available iOS {major} runtime; no runtime is downloaded automatically.")
    runtime = max(available, key=lambda value: tuple(int(part) for part in value["version"].split(".")))
    phones = [device for device in runtime.get("supportedDeviceTypes", []) if device.get("productFamily") == "iPhone"]
    if not phones:
        raise RuntimeError("Runtime has no supported iPhone device type.")
    device = next((phone for phone in phones if phone["name"] == "iPhone 17e"), phones[0])
    return runtime, device


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--configuration", choices=["Debug", "Release"], required=True)
    parser.add_argument("--xcode-version", required=True, help="Expected exact Xcode version, e.g. 26.6")
    parser.add_argument("--ios-major", required=True, type=int)
    parser.add_argument("--output-dir", required=True, type=Path)
    arguments = parser.parse_args()
    root = Path(__file__).resolve().parents[2]

    # Defense in depth against consuming private-repository hosted minutes.
    if os.environ.get("GITHUB_ACTIONS") == "true":
        event = json.loads(Path(os.environ["GITHUB_EVENT_PATH"]).read_text())
        if event.get("repository", {}).get("private") is not False:
            raise RuntimeError("Hosted CI is allowed only for a verified public repository.")

    version = output("xcodebuild", "-version")
    if version.splitlines()[0] != f"Xcode {arguments.xcode_version}":
        raise RuntimeError(f"Expected Xcode {arguments.xcode_version}; got {version.splitlines()[0]}.")
    runtime, device = simulator_profile(json.loads(output("xcrun", "simctl", "list", "runtimes", "-j"))["runtimes"], arguments.ios_major)
    destination = arguments.output_dir.resolve() / f"{arguments.configuration}-{uuid.uuid4().hex}"
    destination.mkdir(parents=True, exist_ok=False)
    result_bundle = destination / "Tests.xcresult"
    print(f"{version}\nRuntime: {runtime['name']} ({runtime['version']}, {runtime['buildversion']})\nDevice: {device['name']}", flush=True)
    print(f"Local result bundle: {result_bundle}", flush=True)

    # The only device ever deleted is the UUID returned by this create call.
    simulator = output("xcrun", "simctl", "create", f"DailySpend-CI-{uuid.uuid4().hex}", device["identifier"], runtime["identifier"])
    if not re.fullmatch(r"[0-9A-Fa-f-]{36}", simulator):
        raise RuntimeError("Unexpected simulator identifier; refusing simulator operations.")
    cleanup_ok = True
    status = 1
    try:
        subprocess.run(["xcrun", "simctl", "boot", simulator], check=True)
        subprocess.run(["xcrun", "simctl", "bootstatus", simulator, "-b"], check=True)
        command = [
            "xcodebuild", "test", "-quiet",
            "-project", str(root / "DailySpend.xcodeproj"), "-scheme", "DailySpend",
            "-configuration", arguments.configuration,
            "-destination", f"platform=iOS Simulator,id={simulator}",
            "-derivedDataPath", str(destination / "DerivedData"),
            "-resultBundlePath", str(result_bundle),
            "-parallel-testing-enabled", "NO",
            "-disableAutomaticPackageResolution", "-skipPackageUpdates",
            "CODE_SIGNING_ALLOWED=NO", "CODE_SIGNING_REQUIRED=NO", "DEVELOPMENT_TEAM=",
            "ENABLE_TESTABILITY=YES",
        ]
        if arguments.configuration == "Release":
            # This test exclusively exercises the #if DEBUG demo-data feature.
            command.append("-skip-testing:DailySpendUITests/DailySpendUITests/testDebugDemoDataMakesDashboardAndInsightsTestable")
        status = subprocess.run(command, cwd=root).returncode
        if result_bundle.exists():
            summary = json.loads(output("xcrun", "xcresulttool", "get", "test-results", "summary", "--path", str(result_bundle)))
            safe_summary = {
                key: summary.get(key) for key in
                ("totalTestCount", "passedTests", "failedTests", "skippedTests")
            }
            (destination / "summary.json").write_text(json.dumps(safe_summary, indent=2) + "\n")
            print(f"Test counts: {json.dumps(safe_summary)}", flush=True)
            # Successful command with zero/missing tests must never give green CI.
            if status == 0 and (not safe_summary["totalTestCount"] or safe_summary["failedTests"] != 0):
                status = 1
            summary_path = os.environ.get("GITHUB_STEP_SUMMARY")
            if summary_path:
                with open(summary_path, "a") as stream:
                    stream.write(f"### {arguments.configuration} simulator tests\n\n")
                    stream.write(f"{version.replace(chr(10), '; ')}; iOS {runtime['version']}; {device['name']}\n\n")
                    stream.write(f"Counts: `{json.dumps(safe_summary)}`\n\n")
                    if arguments.configuration == "Release":
                        stream.write("Debug-only demo-data test excluded; it runs in the Debug job.\n\n")
                    stream.write("Synthetic data only. Signed device, historical migration, and release gates remain separate.\n")
        elif status == 0:
            status = 1
    finally:
        subprocess.run(["xcrun", "simctl", "shutdown", simulator], capture_output=True)
        cleanup_ok = subprocess.run(["xcrun", "simctl", "delete", simulator], capture_output=True).returncode == 0
        if not cleanup_ok:
            print(f"Could not delete disposable simulator {simulator}; delete this UUID manually.", file=sys.stderr)
    return status if status else (0 if cleanup_ok else 1)


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (RuntimeError, subprocess.CalledProcessError, OSError, ValueError) as error:
        print(f"CI test runner failed: {error}", file=sys.stderr)
        sys.exit(1)
