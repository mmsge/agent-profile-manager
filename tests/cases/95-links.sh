# shellcheck shell=bash
# SPDX-License-Identifier: GPL-3.0-or-later
# shellcheck disable=SC2317  # every case is invoked indirectly by run_case
# shellcheck disable=SC2016  # fixture Markdown carries literal backticks
#
# The links between the documents. README.md is a front door and the guides
# under docs/ carry everything else, so a reader is sent from one page to a
# heading on another dozens of times. A heading renamed on one page silently
# breaks the link on every other, and GitHub renders a broken anchor as a
# link that goes nowhere rather than as an error. This resolves every
# relative link and every anchor across README.md, docs/ and packaging/ the
# way GitHub does, and names the page, the link and what was missing.

# links_check <root>: every relative link, resolved. Prints one line per
# broken link and exits non-zero when there is one. Fenced code is skipped
# on both sides: a fence is not a heading, and a link inside one is an
# example rather than a reference.
#
# GitHub's anchor rules: the heading text with formatting stripped, lowered,
# with everything but letters, digits, spaces, hyphens and underscores
# dropped, spaces turned into hyphens, and -1, -2 appended to repeats.
links_check() {
    python3 - "$1" <<'PY'
import glob, os, re, sys

root = sys.argv[1]
files = ["README.md"]
files += sorted(glob.glob("docs/**/*.md", root_dir=root, recursive=True))
files += sorted(glob.glob("packaging/**/*.md", root_dir=root, recursive=True))

def unfenced(path):
    fence = False
    with open(os.path.join(root, path), encoding="utf-8") as fh:
        for line in fh:
            if line.startswith("```"):
                fence = not fence
                continue
            if not fence:
                yield line

def anchors(path):
    seen = {}
    out = set()
    for line in unfenced(path):
        m = re.match(r"^(#{1,6})\s+(.*?)\s*#*\s*$", line)
        if not m:
            continue
        text = m.group(2)
        text = re.sub(r"\[([^\]]*)\]\([^)]*\)", r"\1", text)
        text = re.sub(r"<[^>]+>", "", text)
        text = text.replace("`", "").replace("*", "")
        a = re.sub(r"[^\w\- ]", "", text.lower()).replace(" ", "-")
        n = seen.get(a, 0)
        seen[a] = n + 1
        out.add(a if n == 0 else "%s-%d" % (a, n))
    return out

cache = {}
def anchors_of(path):
    if path not in cache:
        cache[path] = anchors(path)
    return cache[path]

broken = 0
for path in files:
    text = "".join(unfenced(path))
    for m in re.finditer(r"\]\(([^)\s]+)\)", text):
        link = m.group(1)
        if re.match(r"^[a-z][a-z0-9+.-]*:", link):
            continue
        target, _, frag = link.partition("#")
        if target:
            dest = os.path.normpath(os.path.join(os.path.dirname(path), target))
        else:
            dest = path
        if not os.path.exists(os.path.join(root, dest)):
            print("%s: %s: no such file %s" % (path, link, dest))
            broken += 1
            continue
        if frag and dest.endswith(".md") and frag not in anchors_of(dest):
            print("%s: %s: no heading in %s makes the anchor #%s" % (path, link, dest, frag))
            broken += 1
sys.exit(1 if broken else 0)
PY
}

case_every_relative_link_resolves() {
    _out=$(links_check "$ROOT" 2>&1); _status=$?
    if [ "$_status" -ne 0 ]; then
        fail "a link in the documentation does not resolve" "$_out"
    fi
}

case_a_broken_anchor_is_named() {
    # The checker itself, against a fixture with one link to a heading that
    # exists and one to a heading that does not.
    _d=$(mktemp -d "${TMPDIR:-/tmp}/agent-profile-links.XXXXXX")
    mkdir -p "$_d/docs"
    printf '# Front\n\nSee [the guide](docs/GUIDE.md#what-doctor-reads) and [nowhere](docs/GUIDE.md#what-doctor-writes).\n' > "$_d/README.md"
    printf '# Guide\n\n## What `doctor` reads\n\n```\n## Not a heading\n```\n\n[back](../README.md#front)\n' > "$_d/docs/GUIDE.md"
    _out=$(links_check "$_d" 2>&1); _status=$?
    assert_status 1 "$_status" "$_out" || return
    assert_contains "$_out" "README.md: docs/GUIDE.md#what-doctor-writes: no heading in docs/GUIDE.md makes the anchor #what-doctor-writes" || return
    assert_not_contains "$_out" "what-doctor-reads" || return
    assert_not_contains "$_out" "not-a-heading"
    rm -rf "$_d"
}

case_a_missing_file_is_named() {
    _d=$(mktemp -d "${TMPDIR:-/tmp}/agent-profile-links.XXXXXX")
    mkdir -p "$_d/docs"
    printf '# Front\n\nSee [gone](docs/GONE.md).\n' > "$_d/README.md"
    _out=$(links_check "$_d" 2>&1); _status=$?
    assert_status 1 "$_status" "$_out" || return
    assert_contains "$_out" "README.md: docs/GONE.md: no such file docs/GONE.md"
    rm -rf "$_d"
}

case_repeated_headings_get_numbered_anchors() {
    _d=$(mktemp -d "${TMPDIR:-/tmp}/agent-profile-links.XXXXXX")
    mkdir -p "$_d/docs"
    printf '# Front\n\n## Options\n\n## Options\n\n[first](#options) [second](#options-1) [third](#options-2)\n' > "$_d/README.md"
    _out=$(links_check "$_d" 2>&1); _status=$?
    assert_status 1 "$_status" "$_out" || return
    assert_contains "$_out" "#options-2" || return
    assert_not_contains "$_out" "#options-1"
    rm -rf "$_d"
}

run_case "every relative link resolves"            case_every_relative_link_resolves
run_case "a broken anchor is named"                case_a_broken_anchor_is_named
run_case "a missing file is named"                 case_a_missing_file_is_named
run_case "repeated headings get numbered anchors"  case_repeated_headings_get_numbered_anchors
