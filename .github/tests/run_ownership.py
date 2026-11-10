"""Compile actual first-party sources and the full SDK; never open Mail or build a bundle."""

import argparse
import os
from pathlib import Path
import subprocess
import sys
import tempfile


ROOT = Path(__file__).resolve().parents[2]
SCENARIOS = ("path", "folder", "setters", "getters", "draft", "contracts", "failures", "command")
BASELINE_DIAGNOSTICS = {
    "path": "double disposal of shallow string alias",
    "folder": "double disposal of shallow string alias",
    "setters": "outstanding strings=",
    "getters": "outstanding strings=5 refs=2 handles=0",
    "draft": "outstanding strings=4 refs=3 handles=0",
    "failures": "not a valid value for type 'PA_VariableKind'",
    "command": "string getter on failed/wrong-kind result",
}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-root", type=Path, default=ROOT)
    parser.add_argument("--expect-baseline-failure", action="store_true")
    args = parser.parse_args()
    root = args.source_root.resolve()
    with tempfile.TemporaryDirectory(prefix="mail-ownership-") as directory:
        binary = Path(directory) / "ownership"
        sources = [
            ROOT / ".github/tests/native/ownership.mm",
            root / "support/4DPlugin-JSON.cpp",
            root / "4D Plugin API/Classes/C_TEXT.cpp",
            root / "4D Plugin API/Classes/ARRAY_TEXT.cpp",
            root / "4D Plugin API/Classes/C_BLOB.cpp",
            root / "4D Plugin API/Classes/C_LONGINT.cpp",
            root / "4D Plugin API/Classes/C_REAL.cpp",
            root / "4D Plugin API/4DPluginAPI.c",
        ]
        subprocess.run(
            ["clang++", "-std=c++17", "-x", "objective-c++", "-g", "-O1",
             "-fsanitize=address,undefined", "-fno-omit-frame-pointer",
             "-Wno-deprecated-declarations", "-Wno-multichar",
             "-I", str(root), "-I", str(root / "support"),
             "-I", str(root / "4D Plugin API"),
             "-I", str(root / "4D Plugin API/Classes"),
             *map(str, sources), "-framework", "Cocoa", "-o", str(binary)],
            check=True,
        )
        failed = set()
        env = dict(os.environ, ASAN_OPTIONS="detect_leaks=0:halt_on_error=1",
                   UBSAN_OPTIONS="halt_on_error=1:print_stacktrace=1")
        for scenario in SCENARIOS:
            for empty in ("allocated", "null"):
                result = subprocess.run([str(binary), scenario, empty], env=env,
                                        capture_output=True, text=True)
                print(result.stdout, end="")
                print(result.stderr, end="", file=sys.stderr)
                if args.expect_baseline_failure and scenario in BASELINE_DIAGNOSTICS:
                    diagnostic = BASELINE_DIAGNOSTICS[scenario]
                    if not result.returncode or diagnostic not in result.stderr:
                        raise SystemExit(f"Missing named baseline defect: {scenario} ({empty})")
                if result.returncode:
                    failed.add(scenario)
                    if not args.expect_baseline_failure:
                        raise SystemExit(result.returncode)
        if args.expect_baseline_failure:
            expected = set(SCENARIOS) - {"contracts"}
            if failed != expected:
                raise SystemExit(f"Wrong baseline failures: {failed}; expected {expected}")
            print("Immutable baseline failed all seven named defect scenarios; contracts passed.")


if __name__ == "__main__":
    main()
