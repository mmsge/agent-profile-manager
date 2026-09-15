"""Command line entry point.

This is never started by hand. The launcher, ``agpin mcp serve --root PATH``,
execs it after making the same check main() makes below, and Claude Code
starts the launcher as a stdio child of the session it belongs to.
"""

from __future__ import annotations

import argparse
import os
import sys

PROGRAM = "agent-profile-sessions"


def _fail(message: str) -> int:
    print(f"{PROGRAM}: {message}", file=sys.stderr)
    return 2


def main(argv: list[str] | None = None) -> int:
    """Validate the root against the environment, then serve."""
    parser = argparse.ArgumentParser(
        prog=PROGRAM,
        description="A read-only MCP server over one Claude Code config root's transcripts.",
    )
    parser.add_argument("--root", required=True, help="the config root to serve, absolute")
    args = parser.parse_args(argv)

    root = args.root
    configured = os.environ.get("CLAUDE_CONFIG_DIR")
    # Defence in depth behind the launcher, which makes the same comparison.
    # A registration copied into another root must fail here, visibly, rather
    # than serve one account's transcripts to another.
    if not configured or os.path.realpath(configured) != os.path.realpath(root):
        shown = configured if configured else "unset"
        return _fail(
            f"refusing to start: CLAUDE_CONFIG_DIR is {shown}, --root is {root}"
        )
    if not os.path.isdir(root):
        return _fail(f"refusing to start: --root is not a directory: {root}")

    # The framework reads its log level from the environment at import time,
    # so this is set before the server module is imported.
    os.environ.setdefault("FASTMCP_LOG_LEVEL", "WARNING")
    from .server import run

    run(root)
    return 0


if __name__ == "__main__":
    sys.exit(main())
