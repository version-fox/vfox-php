#!/usr/bin/env python3
"""Generate the vfox-php version manifest from upstream PHP release indexes.

Outputs JSON with two top-level arrays:

    {
        "source":  [ {"version", "filename", "sha256", "md5"}, ... ],
        "windows": [ {"version", "filename", "arch", "current", "nts"}, ... ]
    }

Both arrays are sorted newest-first using a numeric version key.

Sources:
  - https://www.php.net/releases/index.php?json (canonical source releases)
  - https://windows.php.net/downloads/releases/{,archives/} (Windows binaries)
"""

from __future__ import annotations

import argparse
import json
import re
import sys
import time
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

USER_AGENT = "vfox-php-manifest-updater (+https://github.com/version-fox/vfox-php)"
SOURCE_MAJORS = (5, 7, 8)
MIN_SUPPORTED = (5, 3, 2)


def http_get(url: str, retries: int = 3, timeout: int = 60) -> str:
    last_err: Exception | None = None
    for attempt in range(retries):
        try:
            req = Request(url, headers={"User-Agent": USER_AGENT})
            with urlopen(req, timeout=timeout) as resp:
                return resp.read().decode("utf-8", errors="replace")
        except (HTTPError, URLError, TimeoutError) as exc:
            last_err = exc
            if attempt < retries - 1:
                time.sleep(2 ** attempt)
    raise RuntimeError(f"GET {url} failed: {last_err}")


def version_key(v: str) -> tuple[int, ...]:
    base = v.split("-", 1)[0]
    parts: list[int] = []
    for chunk in base.split("."):
        try:
            parts.append(int(chunk))
        except ValueError:
            parts.append(0)
    nts_penalty = 1 if "-nts" in v else 0
    return tuple(parts) + (-nts_penalty,)


def meets_minimum(v: str) -> bool:
    return version_key(v)[: len(MIN_SUPPORTED)] >= MIN_SUPPORTED


def fetch_source_versions() -> list[dict]:
    out: list[dict] = []
    for major in SOURCE_MAJORS:
        url = f"https://www.php.net/releases/index.php?json&max=500&version={major}"
        body = http_get(url)
        data = json.loads(body)
        for ver, meta in data.items():
            if not isinstance(meta, dict):
                continue
            sources = meta.get("source") or []
            tarball = next(
                (s for s in sources if str(s.get("filename", "")).endswith(".tar.gz")),
                None,
            )
            if not tarball:
                continue
            if not meets_minimum(ver):
                continue
            entry = {"version": ver, "filename": tarball["filename"]}
            if tarball.get("sha256"):
                entry["sha256"] = tarball["sha256"]
            if tarball.get("md5"):
                entry["md5"] = tarball["md5"]
            out.append(entry)
    out.sort(key=lambda e: version_key(e["version"]), reverse=True)
    # Deduplicate (the API can repeat entries across major queries).
    seen: set[str] = set()
    deduped: list[dict] = []
    for entry in out:
        if entry["version"] in seen:
            continue
        seen.add(entry["version"])
        deduped.append(entry)
    return deduped


WIN_FILE_RE = re.compile(
    r"^php-"
    r"(?P<version>\d+\.\d+\.\d+)"
    r"(?P<nts>-nts)?"
    r"-Win32-(?:vc|vs|VC|VS)\d+-"
    r"(?P<arch>x64|x86|arm64)"
    r"\.zip$"
)
WIN_SKIP_PREFIXES = ("php-debug-", "php-devel-", "php-test-")


def parse_windows_listing(html: str, current: bool) -> list[dict]:
    out: list[dict] = []
    for m in re.finditer(r'href="([^"]+\.zip)"', html):
        filename = m.group(1)
        # Skip diagnostic builds and source archives.
        if any(filename.startswith(p) for p in WIN_SKIP_PREFIXES):
            continue
        if filename.endswith("-src.zip") or filename.endswith("-source.zip"):
            continue
        if "-dev-" in filename or "-latest-" in filename:
            continue
        match = WIN_FILE_RE.match(filename)
        if not match:
            continue
        base = match.group("version")
        if not meets_minimum(base):
            continue
        is_nts = bool(match.group("nts"))
        version = f"{base}-nts" if is_nts else base
        out.append(
            {
                "version": version,
                "filename": filename,
                "arch": match.group("arch"),
                "current": current,
                "nts": is_nts,
            }
        )
    return out


def fetch_windows_versions() -> list[dict]:
    current_html = http_get("https://windows.php.net/downloads/releases/")
    archives_html = http_get("https://windows.php.net/downloads/releases/archives/")
    current = parse_windows_listing(current_html, True)
    archives = parse_windows_listing(archives_html, False)

    # Prefer the "current" listing when a filename appears in both.
    by_filename: dict[str, dict] = {e["filename"]: e for e in archives}
    for entry in current:
        by_filename[entry["filename"]] = entry

    merged = list(by_filename.values())
    merged.sort(
        key=lambda e: (version_key(e["version"]), e["arch"], e["nts"]),
        reverse=True,
    )
    return merged


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description="Generate the vfox-php version manifest.")
    parser.add_argument("-o", "--output", default="manifest.json", help="Output JSON path.")
    args = parser.parse_args(argv)

    manifest = {
        "source": fetch_source_versions(),
        "windows": fetch_windows_versions(),
    }
    payload = json.dumps(manifest, indent=2, ensure_ascii=False)
    with open(args.output, "w", encoding="utf-8", newline="\n") as f:
        f.write(payload)
        f.write("\n")
    print(
        f"Wrote {args.output}: "
        f"{len(manifest['source'])} source / {len(manifest['windows'])} windows entries",
        file=sys.stderr,
    )
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
