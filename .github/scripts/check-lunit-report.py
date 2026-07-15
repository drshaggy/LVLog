#!/usr/bin/env python3

from __future__ import annotations

import os
import sys
import xml.etree.ElementTree as ET
from pathlib import Path


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: check-lunit-report.py <report.xml>", file=sys.stderr)
        return 2

    report_path = Path(sys.argv[1])
    if not report_path.is_file():
        print(f"LUnit report not found: {report_path}", file=sys.stderr)
        return 1

    try:
        root = ET.parse(report_path).getroot()
    except ET.ParseError as error:
        print(f"Invalid LUnit XML report: {error}", file=sys.stderr)
        return 1

    test_cases = root.findall(".//testcase")
    outcomes: list[str] = []
    for case in test_cases:
        status = case.attrib.get("status", "").strip().lower()
        if case.find("error") is not None or "error" in status:
            outcomes.append("error")
        elif case.find("failure") is not None or status == "failed":
            outcomes.append("failed")
        elif case.find("skipped") is not None or status == "skipped":
            outcomes.append("skipped")
        else:
            outcomes.append("passed")

    failures = outcomes.count("failed")
    errors = outcomes.count("error")
    skipped = outcomes.count("skipped")
    passed = len(test_cases) - failures - errors - skipped

    summary = (
        f"LUnit: {len(test_cases)} tests, {passed} passed, "
        f"{failures} failed, {errors} errors, {skipped} skipped"
    )
    print(summary)

    step_summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if step_summary:
        with Path(step_summary).open("a", encoding="utf-8") as summary_file:
            summary_file.write("## LUnit results\n\n")
            summary_file.write(f"{summary}\n")

    if not test_cases:
        print("LUnit report contains no test cases", file=sys.stderr)
        return 1

    return 1 if failures or errors else 0


if __name__ == "__main__":
    raise SystemExit(main())
