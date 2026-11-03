#!/usr/bin/env python3
"""Turn a RiffMemo "Send Diagnostics" file into readable crash stacks (WAS-114).

MetricKit names app code only as a binary plus an offset, for example
`RiffMemo +635872`. This script asks `atos` to map each RiffMemo offset to a
function, file and line, using the dSYM from the same build.

Usage:
    scripts/symbolicate-diagnostics.py RiffMemo-diagnostics.json RiffMemo.app.dSYM

Get the dSYM from the TestFlight run's "RiffMemo-<build>-dSYM" artifact.
App Store Connect does not offer a dSYM download, and a local rebuild gives a
different binary, so builds made before that artifact existed (1 to 5) cannot
be read this way. The script checks the binary UUID and stops on a mismatch.
"""

import json
import subprocess
import sys
from pathlib import Path

APP_BINARY = "RiffMemo"
# Default __TEXT load address for a 64-bit iOS executable. MetricKit reports
# offsets into __TEXT, so offset + this address is what atos expects.
TEXT_BASE = 0x100000000


def flatten(frames):
    """MetricKit nests each caller under `subFrames`; return them in call order."""
    out = []
    for frame in frames:
        out.append(frame)
        out.extend(flatten(frame.get("subFrames", [])))
    return out


def dsym_uuids(dwarf: Path):
    """The binary UUIDs this dSYM describes (one per architecture)."""
    result = subprocess.run(["xcrun", "dwarfdump", "--uuid", str(dwarf)],
                            capture_output=True, text=True, check=True)
    return {line.split()[1].upper() for line in result.stdout.splitlines() if line.startswith("UUID:")}


def check_uuid(frames, uuids):
    """A dSYM from any other build maps offsets to the wrong functions, with no
    error from atos. MetricKit records the exact binary UUID, so compare first."""
    for frame in frames:
        reported = (frame.get("binaryUUID") or "").upper()
        if frame.get("binaryName") == APP_BINARY and reported and reported not in uuids:
            sys.exit(f"dSYM does not match this report: report binary {reported}, "
                     f"dSYM {', '.join(sorted(uuids))}. Use the dSYM from the same build.")


def symbolicate(dwarf: Path, offsets):
    addresses = [hex(TEXT_BASE + o) for o in offsets]
    result = subprocess.run(
        ["xcrun", "atos", "-o", str(dwarf), "-arch", "arm64", "-l", hex(TEXT_BASE), *addresses],
        capture_output=True, text=True, check=True,
    )
    return result.stdout.splitlines()


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    export = json.loads(Path(sys.argv[1]).read_text())
    dsym = Path(sys.argv[2])
    dwarf = dsym / "Contents" / "Resources" / "DWARF" / APP_BINARY
    if not dwarf.exists():
        sys.exit(f"No DWARF file at {dwarf}. Pass the RiffMemo.app.dSYM folder.")
    uuids = dsym_uuids(dwarf)

    print(f"{export.get('app')} {export.get('version')} ({export.get('build')})")
    for number, report in enumerate(export.get("reports", []), start=1):
        for kind in ("crashDiagnostics", "hangDiagnostics"):
            for diagnostic in report.get(kind) or []:
                meta = diagnostic.get("diagnosticMetaData", {})
                print(f"\n=== Report {number}: {kind[:-11]} at {report.get('timeStampEnd')}")
                print(f"    build {meta.get('appBuildVersion')}, {meta.get('osVersion')}, {meta.get('deviceType')}")
                print(f"    exception type {meta.get('exceptionType')}, signal {meta.get('signal')}")
                for stack in diagnostic.get("callStackTree", {}).get("callStacks", []):
                    if not stack.get("threadAttributed"):
                        continue  # Only the thread that crashed or hung.
                    frames = flatten(stack.get("callStackRootFrames", []))
                    check_uuid(frames, uuids)
                    app_offsets = [f["offsetIntoBinaryTextSegment"] for f in frames
                                   if f.get("binaryName") == APP_BINARY]
                    names = iter(symbolicate(dwarf, app_offsets)) if app_offsets else iter(())
                    for frame in frames:
                        binary = frame.get("binaryName", "?")
                        if binary == APP_BINARY:
                            print(f"    {binary:<20} {next(names)}")
                        else:
                            print(f"    {binary:<20} +{frame.get('offsetIntoBinaryTextSegment')}")


if __name__ == "__main__":
    main()
