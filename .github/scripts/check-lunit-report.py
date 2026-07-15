#!/usr/bin/env python3

from __future__ import annotations

import os
import sys
import xml.etree.ElementTree as ET
from pathlib import Path


def append_step_summary(markdown: str) -> None:
    step_summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if step_summary:
        with Path(step_summary).open("a", encoding="utf-8") as summary_file:
            summary_file.write(markdown)


def classify(case: ET.Element) -> str:
    status = case.attrib.get("status", "").strip().lower()
    if case.find("error") is not None or "error" in status:
        return "error"
    if case.find("failure") is not None or status == "failed":
        return "failed"
    if case.find("skipped") is not None or status == "skipped":
        return "skipped"
    return "passed"


def diagnostic(case: ET.Element) -> str:
    for element_name in ("error", "failure", "skipped"):
        element = case.find(element_name)
        if element is not None:
            message = element.attrib.get("message") or element.text or ""
            message = message.split("-" * 40, maxsplit=1)[0]
            return " ".join(message.split())
    return ""


def escape_table_cell(value: str) -> str:
    return value.replace("|", "\\|").replace("\n", " ")


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: check-lunit-report.py <report.xml>", file=sys.stderr)
        return 2

    report_path = Path(sys.argv[1])
    if not report_path.is_file():
        message = f"LUnit report not found: {report_path}"
        print(message, file=sys.stderr)
        append_step_summary(f"## LUnit results\n\n❌ {message}\n")
        return 1

    try:
        root = ET.parse(report_path).getroot()
    except ET.ParseError as error:
        message = f"Invalid LUnit XML report: {error}"
        print(message, file=sys.stderr)
        append_step_summary(f"## LUnit results\n\n❌ {message}\n")
        return 1

    test_cases = root.findall(".//testcase")
    results = [(case, classify(case), diagnostic(case)) for case in test_cases]
    outcomes = [outcome for _, outcome, _ in results]

    failures = outcomes.count("failed")
    errors = outcomes.count("error")
    skipped = outcomes.count("skipped")
    passed = len(test_cases) - failures - errors - skipped

    summary = (
        f"LUnit: {len(test_cases)} tests, {passed} passed, "
        f"{failures} failed, {errors} errors, {skipped} skipped"
    )
    print(summary)
    for case, outcome, reason in results:
        suite = case.attrib.get("classname", "(unknown suite)")
        name = case.attrib.get("name", "(unnamed test)")
        suffix = f" — {reason}" if reason else ""
        print(f"- {outcome.upper()}: {suite} / {name}{suffix}")

    icons = {"passed": "✅", "failed": "❌", "error": "⚠️", "skipped": "⏭️"}
    markdown = [
        "## LUnit results\n",
        f"**{summary}**\n",
        "| Result | Suite | Test | Duration |",
        "|:--|:--|:--|--:|",
    ]
    for case, outcome, _ in results:
        suite = escape_table_cell(case.attrib.get("classname", "(unknown suite)"))
        name = escape_table_cell(case.attrib.get("name", "(unnamed test)"))
        duration = escape_table_cell(case.attrib.get("time", ""))
        markdown.append(f"| {icons[outcome]} {outcome} | {suite} | {name} | {duration}s |")

    diagnostics = [result for result in results if result[2]]
    if diagnostics:
        markdown.extend(["", "### Diagnostics", ""])
        for case, outcome, reason in diagnostics:
            suite = case.attrib.get("classname", "(unknown suite)")
            name = case.attrib.get("name", "(unnamed test)")
            markdown.append(
                f"- **{outcome}:** `{suite} / {name}` — {escape_table_cell(reason)}"
            )

    append_step_summary("\n".join(markdown) + "\n")

    if not test_cases:
        print("LUnit report contains no test cases", file=sys.stderr)
        return 1

    return 1 if failures or errors else 0


if __name__ == "__main__":
    raise SystemExit(main())
