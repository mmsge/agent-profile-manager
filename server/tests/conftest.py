"""Fixtures that write invented transcripts into tmp_path.

Nothing here reads a real transcript, and no text here came from one. The
records have the shapes section 1 of the proposal describes, filled with
lorem.
"""

from __future__ import annotations

import asyncio
import json
import os
from typing import Any

import pytest

LOREM = (
    "lorem ipsum dolor sit amet consectetur adipiscing elit sed do eiusmod "
    "tempor incididunt ut labore et dolore magna aliqua "
)

VERSION = "2.1.272"


def lorem(n: int) -> str:
    """A deterministic block of at least n characters of nonsense."""
    return (LOREM * (n // len(LOREM) + 1))[:n]


def base(kind: str, *, session_id: str, ts: str, cwd: str, branch: str, uuid: str) -> dict[str, Any]:
    return {
        "type": kind,
        "sessionId": session_id,
        "timestamp": ts,
        "cwd": cwd,
        "gitBranch": branch,
        "version": VERSION,
        "uuid": uuid,
        "parentUuid": None,
        "isSidechain": False,
    }


def prompt(text: str, **kw: Any) -> dict[str, Any]:
    """A human prompt, content as a plain string."""
    record = base("user", **kw)
    record["message"] = {"role": "user", "content": text}
    return record


def tool_result(text: str, *, tool_use_id: str = "tu1", **kw: Any) -> dict[str, Any]:
    """A user record that is a tool's output, not something a person typed."""
    record = base("user", **kw)
    record["message"] = {
        "role": "user",
        "content": [
            {"type": "tool_result", "tool_use_id": tool_use_id, "content": text, "is_error": False}
        ],
    }
    record["toolUseResult"] = {"stdout": text}
    return record


def subagent_result(agent_id: str, agent_type: str, **kw: Any) -> dict[str, Any]:
    """The parent record that carries a subagent's result."""
    record = tool_result(f"{agent_type} finished", tool_use_id="tu-agent", **kw)
    record["toolUseResult"] = {"agentId": agent_id, "agentType": agent_type}
    return record


def reply(
    text: str,
    *,
    thinking: str | None = None,
    tools: list[tuple[str, str]] | None = None,
    **kw: Any,
) -> dict[str, Any]:
    """An assistant record, optionally with thinking and tool_use blocks."""
    blocks: list[dict[str, Any]] = []
    if thinking:
        blocks.append({"type": "thinking", "thinking": thinking})
    blocks.append({"type": "text", "text": text})
    for index, (name, path) in enumerate(tools or []):
        blocks.append(
            {"type": "tool_use", "id": f"tu{index}", "name": name, "input": {"file_path": path}}
        )
    record = base("assistant", **kw)
    record["message"] = {"role": "assistant", "content": blocks}
    return record


def title(text: str, **kw: Any) -> dict[str, Any]:
    record = base("custom-title", **kw)
    record["customTitle"] = text
    return record


def write_jsonl(path: str, records: list[Any]) -> str:
    """Write records one per line. A plain string is written verbatim, so a
    test can plant a line that is not JSON at all."""
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as handle:
        for record in records:
            if isinstance(record, str):
                handle.write(record + "\n")
            else:
                handle.write(json.dumps(record) + "\n")
    return path


@pytest.fixture
def make_root(tmp_path):
    """Return a factory that creates an empty config root with a projects dir."""

    def factory(name: str = "root") -> str:
        root = tmp_path / name
        (root / "projects").mkdir(parents=True, exist_ok=True)
        return str(root)

    return factory


@pytest.fixture
def root(make_root):
    """A root with three sessions across two projects, plus the awkward cases."""
    root = make_root()
    projects = os.path.join(root, "projects")

    alpha_dir = os.path.join(projects, "-work-alpha")
    beta_dir = os.path.join(projects, "-work-beta")

    alpha_one = {"session_id": "s-alpha-1", "cwd": "/work/alpha", "branch": "main"}
    spill_dir = os.path.join(alpha_dir, "s-alpha-1", "tool-results")
    spill_path = os.path.join(spill_dir, "tu-spill.txt")
    write_jsonl(
        os.path.join(alpha_dir, "s-alpha-1.jsonl"),
        [
            prompt("fix the retry in the invoice fetcher", ts="2026-09-10T09:00:00.000Z",
                   uuid="u1", **alpha_one),
            "{ this line is not json",
            reply("I will read the fetcher first", thinking="lorem thinking about retries",
                  tools=[("Read", "/work/alpha/fetcher.py")], ts="2026-09-10T09:00:05.000Z",
                  uuid="a1", **alpha_one),
            tool_result("the file holds " + lorem(40), tool_use_id="tu0",
                        ts="2026-09-10T09:00:06.000Z", uuid="r1", **alpha_one),
            {"type": "system", "subtype": "hook", "sessionId": "s-alpha-1"},
            {"type": "made-up-record-type", "sessionId": "s-alpha-1"},
            prompt("now add a backoff of five seconds", ts="2026-09-10T09:01:00.000Z",
                   uuid="u2", **alpha_one),
            subagent_result("aa11", "explorer", ts="2026-09-10T09:01:30.000Z",
                            uuid="r2", **alpha_one),
            reply("done, the backoff is in place", tools=[("Edit", "/work/alpha/fetcher.py")],
                  ts="2026-09-10T09:02:00.000Z", uuid="a2", **alpha_one),
            tool_result(f"output spilled to {spill_path}", tool_use_id="tu-spill",
                        ts="2026-09-10T09:02:10.000Z", uuid="r3", **alpha_one),
            title("Invoice retries", ts="2026-09-10T09:03:00.000Z", uuid="t1", **alpha_one),
        ],
    )

    # The subagent transcript and its spilled tool result live beside the file.
    agent = {"session_id": "s-alpha-1", "cwd": "/work/alpha", "branch": "main"}
    agent_records: list[Any] = []
    for index in range(6):
        agent_records.append(
            prompt(f"subagent step {index} " + lorem(20),
                   ts=f"2026-09-10T09:01:{index:02d}.000Z", uuid=f"sa-u{index}", **agent)
        )
        agent_records.append(
            reply(f"subagent answer {index} " + lorem(20),
                  ts=f"2026-09-10T09:01:{index:02d}.500Z", uuid=f"sa-a{index}", **agent)
        )
    for record in agent_records:
        record["agentId"] = "aa11"
        record["isSidechain"] = True
    write_jsonl(os.path.join(alpha_dir, "s-alpha-1", "subagents", "agent-aa11.jsonl"),
                agent_records)
    os.makedirs(spill_dir, exist_ok=True)
    with open(spill_path, "w", encoding="utf-8") as handle:
        handle.write("spilled " + lorem(500))

    alpha_two = {"session_id": "s-alpha-2", "cwd": "/work/alpha", "branch": "feature"}
    write_jsonl(
        os.path.join(alpha_dir, "s-alpha-2.jsonl"),
        [
            prompt("write the changelog entry", ts="2026-09-12T11:00:00.000Z",
                   uuid="u3", **alpha_two),
            reply("here is a draft changelog", ts="2026-09-12T11:00:04.000Z",
                  uuid="a3", **alpha_two),
        ],
    )

    beta = {"session_id": "s-beta-1", "cwd": "/work/beta", "branch": "main"}
    write_jsonl(
        os.path.join(beta_dir, "s-beta-1.jsonl"),
        [
            prompt("port the parser to the new schema", ts="2026-09-14T08:00:00.000Z",
                   uuid="u4", **beta),
            reply("the parser needs two changes", tools=[("Grep", "/work/beta/parse.py")],
                  ts="2026-09-14T08:00:03.000Z", uuid="a4", **beta),
        ],
    )

    # Transcripts Claude Code set aside. Neither is a session anyone asked for.
    write_jsonl(os.path.join(beta_dir, "s-beta-1.orphaned-1757000000.jsonl"),
                [prompt("orphaned text", ts="2026-09-13T08:00:00.000Z", uuid="o1", **beta)])
    write_jsonl(os.path.join(beta_dir, "s-beta-1.superseded-1757000001.jsonl"),
                [prompt("superseded text", ts="2026-09-13T09:00:00.000Z", uuid="o2", **beta)])
    # Not a transcript at that depth.
    with open(os.path.join(beta_dir, "notes.txt"), "w", encoding="utf-8") as handle:
        handle.write("not a transcript")

    return root


@pytest.fixture
def call(root):
    """Call one tool in process, through the in memory transport."""
    from fastmcp import Client

    from agent_profile_sessions import server

    def caller(name: str, arguments: dict[str, Any] | None = None, *, use_root: str | None = None):
        server.configure(use_root or root)

        async def go():
            async with Client(server.mcp) as client:
                result = await client.call_tool(name, arguments or {})
                return result.data

        return asyncio.run(go())

    return caller
