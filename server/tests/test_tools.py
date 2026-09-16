"""Tests that drive the six tools in process, over the in memory transport."""

from __future__ import annotations

import json
import os

import pytest
from fastmcp.exceptions import ToolError

from conftest import lorem, prompt, reply, subagent_result, write_jsonl


def test_list_projects_groups_by_cwd_and_reports_retention(call, root):
    out = call("list_projects")
    assert [p["cwd"] for p in out["projects"]] == ["/work/alpha", "/work/beta"]
    assert out["projects"][0]["dir"] == "-work-alpha"
    assert out["projects"][0]["sessions"] == 2
    assert out["projects"][1]["last_at"] == "2026-09-14T08:00:03.000Z"
    # No settings.json in the fixture root, so the documented default applies.
    assert out["retention_days"] == 30
    assert "deleted by Claude Code" in out["root_note"]
    assert "default of 30 days" in out["root_note"]


def test_list_projects_reads_cleanup_period_days(call, root):
    with open(os.path.join(root, "settings.json"), "w", encoding="utf-8") as handle:
        handle.write(json.dumps({"cleanupPeriodDays": 90}))
    out = call("list_projects")
    assert out["retention_days"] == 90
    assert "default of 30 days" not in out["root_note"]


def test_list_sessions_returns_identity_columns_newest_first(call):
    out = call("list_sessions")
    assert out["next_cursor"] is None
    assert [s["session_id"] for s in out["sessions"]] == ["s-beta-1", "s-alpha-2", "s-alpha-1"]
    row = out["sessions"][2]
    assert row["cwd"] == "/work/alpha"
    assert row["git_branch"] == "main"
    assert row["version"] == "2.1.272"
    assert row["title"] == "Invoice retries"
    assert row["prompts"] == 2 and row["replies"] == 2 and row["tool_calls"] == 2
    assert row["has_subagents"] is True
    assert row["size_bytes"] > 0
    assert row["source"] == "transcript"
    assert len(row["first_prompt"]) <= 200


def test_list_sessions_filters(call):
    assert len(call("list_sessions", {"cwd": "/work/alpha"})["sessions"]) == 2
    assert len(call("list_sessions", {"cwd": "/work/nowhere"})["sessions"]) == 0
    assert len(call("list_sessions", {"branch": "feature"})["sessions"]) == 1
    since = call("list_sessions", {"since": "2026-09-12"})["sessions"]
    assert [s["session_id"] for s in since] == ["s-beta-1", "s-alpha-2"]
    until = call("list_sessions", {"until": "2026-09-12"})["sessions"]
    assert [s["session_id"] for s in until] == ["s-alpha-2", "s-alpha-1"]
    window = call("list_sessions", {"since": "2026-09-11", "until": "2026-09-13"})["sessions"]
    assert [s["session_id"] for s in window] == ["s-alpha-2"]
    # The query is a substring over the first prompt and the title only.
    assert [s["session_id"] for s in call("list_sessions", {"query": "INVOICE"})["sessions"]] == [
        "s-alpha-1"
    ]
    assert [s["session_id"] for s in call("list_sessions", {"query": "changelog"})["sessions"]] == [
        "s-alpha-2"
    ]
    # "backoff" is in the conversation but not in the preview or the title.
    assert call("list_sessions", {"query": "backoff"})["sessions"] == []


def test_list_sessions_pages_with_a_cursor(call):
    seen = []
    cursor = None
    for _ in range(4):
        out = call("list_sessions", {"limit": 1, "cursor": cursor})
        assert len(out["sessions"]) == 1
        seen.append(out["sessions"][0]["session_id"])
        cursor = out["next_cursor"]
        if cursor is None:
            break
    assert seen == ["s-beta-1", "s-alpha-2", "s-alpha-1"]
    assert cursor is None


def test_list_sessions_clamps_the_limit_and_refuses_a_foreign_cursor(call):
    assert len(call("list_sessions", {"limit": 0})["sessions"]) == 1
    assert len(call("list_sessions", {"limit": 5000})["sessions"]) == 3
    with pytest.raises(ToolError, match="cursor"):
        call("list_sessions", {"cursor": "../../etc"})


def test_list_sessions_rejects_a_bad_date(call):
    with pytest.raises(ToolError, match="ISO-8601"):
        call("list_sessions", {"since": "last tuesday"})


def test_session_summary(call):
    out = call("session_summary", {"session_id": "s-alpha-1"})
    assert out["records"] == 10
    assert out["tool_histogram"] == {"Edit": 1, "Read": 1}
    assert out["files_touched"] == ["/work/alpha/fetcher.py"]
    assert out["last_reply"] == "done, the backoff is in place"
    assert out["subagents"] == [{"agent_id": "aa11", "agent_type": "explorer", "records": 12}]
    assert out["source"] == "transcript"


def test_unknown_session_id_is_a_tool_error(call):
    with pytest.raises(ToolError, match="unknown session_id"):
        call("session_summary", {"session_id": "s-nope"})


def test_get_session_defaults_leave_out_tool_results_and_thinking(call):
    out = call("get_session", {"session_id": "s-alpha-1"})
    assert out["total"] == 7
    assert out["next_start"] is None
    assert [m["index"] for m in out["messages"]] == [0, 1, 3, 5]
    assert [m["role"] for m in out["messages"]] == ["user", "assistant", "user", "assistant"]
    assert all(m["source"] == "transcript" for m in out["messages"])
    assert all("lorem thinking" not in m["text"] for m in out["messages"])
    assert out["messages"][1]["tool_uses"] == ["Read"]
    assert out["messages"][1]["truncated"] is False


def test_get_session_can_be_asked_for_tool_results_and_thinking(call):
    with_results = call("get_session", {"session_id": "s-alpha-1", "include_tool_results": True})
    assert [m["index"] for m in with_results["messages"]] == [0, 1, 2, 3, 4, 5, 6]
    assert "the file holds lorem" in with_results["messages"][2]["text"]
    with_thinking = call("get_session", {"session_id": "s-alpha-1", "include_thinking": True})
    assert "lorem thinking about retries" in with_thinking["messages"][1]["text"]


def test_get_session_pages_and_truncates(call):
    first = call("get_session", {"session_id": "s-alpha-1", "limit": 2})
    assert [m["index"] for m in first["messages"]] == [0, 1]
    assert first["next_start"] == 3
    second = call("get_session", {"session_id": "s-alpha-1", "start": first["next_start"],
                                  "limit": 2})
    assert [m["index"] for m in second["messages"]] == [3, 5]
    assert second["next_start"] is None
    short = call("get_session", {"session_id": "s-alpha-1", "max_chars": 4})
    assert short["messages"][0]["text"] == "fix "
    assert short["messages"][0]["truncated"] is True


def test_get_session_stops_at_the_forty_thousand_character_cap(call, make_root):
    big = make_root("big")
    common = {"session_id": "s-big", "cwd": "/work/big", "branch": "main"}
    records = []
    for index in range(40):
        records.append(prompt(lorem(3000), ts=f"2026-09-01T10:{index:02d}:00.000Z",
                              uuid=f"b{index}", **common))
    write_jsonl(os.path.join(big, "projects", "-work-big", "s-big.jsonl"), records)

    out = call("get_session", {"session_id": "s-big", "limit": 100}, use_root=big)
    # Each message is cut at the default 2,000 characters, so twenty of them
    # fill the 40,000 character reply cap.
    assert len(out["messages"]) == 20
    assert sum(len(m["text"]) for m in out["messages"]) == 40000
    assert out["next_start"] == 20
    assert all(m["truncated"] for m in out["messages"])
    rest = call("get_session", {"session_id": "s-big", "start": out["next_start"], "limit": 100},
                use_root=big)
    assert len(rest["messages"]) == 20
    assert rest["next_start"] is None


def test_get_session_pages_a_subagent_through_the_parent(call):
    out = call("get_session", {"session_id": "s-alpha-1", "agent_id": "aa11", "limit": 5})
    assert out["total"] == 12
    assert len(out["messages"]) == 5
    assert out["next_start"] == 5
    assert "subagent step 0" in out["messages"][0]["text"]
    with pytest.raises(ToolError, match="unknown agent_id"):
        call("get_session", {"session_id": "s-alpha-1", "agent_id": "aa12"})
    # A subagent is not a session of its own.
    assert "aa11" not in [s["session_id"] for s in call("list_sessions")["sessions"]]


def test_get_message_clamps_and_can_read_a_spilled_file(call, make_root):
    out = call("get_message", {"session_id": "s-alpha-1", "uuid": "a2"})
    assert out["text"] == "done, the backoff is in place"
    assert out["truncated"] is False
    tiny = call("get_message", {"session_id": "s-alpha-1", "uuid": "a2", "max_chars": 0})
    assert len(tiny["text"]) == 1 and tiny["truncated"] is True

    spilled = call("get_message", {"session_id": "s-alpha-1", "uuid": "r3",
                                   "include_spilled": True})
    assert len(spilled["spilled"]) == 1
    assert spilled["spilled"][0]["text"].startswith("spilled ")
    assert spilled["spilled"][0]["source"] == "transcript"
    assert "spilled" not in call("get_message", {"session_id": "s-alpha-1", "uuid": "r3"})

    with pytest.raises(ToolError, match="unknown uuid"):
        call("get_message", {"session_id": "s-alpha-1", "uuid": "no-such-uuid"})

    # The upper clamp is 100,000 characters, whatever is asked for.
    huge = make_root("huge")
    common = {"session_id": "s-huge", "cwd": "/work/huge", "branch": "main"}
    write_jsonl(
        os.path.join(huge, "projects", "-work-huge", "s-huge.jsonl"),
        [reply(lorem(120000), ts="2026-09-01T10:00:00.000Z", uuid="h1", **common)],
    )
    long_one = call("get_message", {"session_id": "s-huge", "uuid": "h1", "max_chars": 999999},
                    use_root=huge)
    assert len(long_one["text"]) == 100000
    assert long_one["truncated"] is True


def test_search_substring_and_filters(call):
    out = call("search", {"query": "BACKOFF"})
    assert len(out["hits"]) == 2
    first = out["hits"][0]
    assert first["session_id"] == "s-alpha-1"
    assert first["role"] == "user"
    assert first["index"] == 3
    assert "backoff" in first["snippet"]
    assert len(first["snippet"]) <= 240
    assert first["source"] == "transcript"
    assert call("search", {"query": "backoff", "cwd": "/work/beta"})["hits"] == []
    assert len(call("search", {"query": "backoff", "limit": 1})["hits"]) == 1
    assert len(call("search", {"query": "parser", "roles": ["user"]})["hits"]) == 1
    # Tool results are not searched.
    assert call("search", {"query": "the file holds"})["hits"] == []


def test_search_does_not_take_a_regex_argument(call):
    """The parameter is gone, not merely discouraged.

    A pattern of six characters could hang the one thread this server has for
    the rest of the session, chosen by a model reading a transcript, and
    substring plus the cwd, date and branch filters covers what it was for.
    """
    with pytest.raises(ToolError):
        call("search", {"query": "back.?off", "regex": True})
    # And the query is a substring now, whatever it looks like.
    assert call("search", {"query": "back.?off"})["hits"] == []
    assert len(call("search", {"query": "backoff"})["hits"]) == 2
    # A long query is a long substring, not a refused pattern.
    assert call("search", {"query": "a" * 201})["hits"] == []


def test_session_summary_caps_its_two_lists(call, make_root):
    """The two lists that had no cap in a design that caps everything else."""
    from agent_profile_sessions import server

    root = make_root("wide")
    common = {"session_id": "s-wide", "cwd": "/work/wide", "branch": "main"}
    records = []
    for index in range(server.SUMMARY_FILES_CAP + 20):
        records.append(
            reply(
                f"touching file {index}",
                tools=[("Edit", f"/work/wide/pkg/module_{index:04d}.py")],
                ts="2026-09-10T09:00:00.000Z",
                uuid=f"w{index}",
                **common,
            )
        )
    write_jsonl(os.path.join(root, "projects", "-work-wide", "s-wide.jsonl"), records)

    out = call("session_summary", {"session_id": "s-wide"}, use_root=root)
    assert len(out["files_touched"]) == server.SUMMARY_FILES_CAP
    assert out["files_touched_total"] == server.SUMMARY_FILES_CAP + 20
    assert out["files_touched_truncated"] is True
    # The kept ones are the first of the same sorted order, so paging by hand
    # is possible and the answer is stable between calls.
    assert out["files_touched"][0].endswith("module_0000.py")


def test_session_summary_says_nothing_was_cut_when_nothing_was(call):
    out = call("session_summary", {"session_id": "s-alpha-1"})
    assert out["files_touched"] == ["/work/alpha/fetcher.py"]
    assert out["files_touched_total"] == 1
    assert out["files_touched_truncated"] is False
    assert out["subagents_total"] == 1
    assert out["subagents_truncated"] is False


def test_session_summary_caps_the_subagents(call, make_root, monkeypatch):
    from agent_profile_sessions import server

    monkeypatch.setattr(server, "SUMMARY_SUBAGENTS_CAP", 2)
    root = make_root("agents")
    common = {"session_id": "s-agents", "cwd": "/work/agents", "branch": "main"}
    parent = [prompt("go", ts="2026-09-10T09:00:00.000Z", uuid="p0", **common)]
    for index in range(4):
        parent.append(
            subagent_result(
                f"ag{index}", "explorer",
                ts=f"2026-09-10T09:0{index}:30.000Z", uuid=f"r{index}", **common,
            )
        )
    write_jsonl(os.path.join(root, "projects", "-work-agents", "s-agents.jsonl"), parent)
    for index in range(4):
        child = [
            prompt(f"step {index}", ts="2026-09-10T09:01:00.000Z",
                   uuid=f"c{index}", **common)
        ]
        for record in child:
            record["agentId"] = f"ag{index}"
            record["isSidechain"] = True
        write_jsonl(
            os.path.join(root, "projects", "-work-agents", "s-agents", "subagents",
                         f"agent-ag{index}.jsonl"),
            child,
        )

    out = call("session_summary", {"session_id": "s-agents"}, use_root=root)
    assert len(out["subagents"]) == 2
    assert out["subagents_total"] == 4
    assert out["subagents_truncated"] is True


def _run_main(root_arg: str, config_dir: str | None) -> tuple[int, str]:
    """Start the module as Claude Code would, and report how it refused."""
    import subprocess
    import sys

    import agent_profile_sessions

    package_parent = os.path.dirname(os.path.dirname(os.path.abspath(
        agent_profile_sessions.__file__)))
    env = dict(os.environ)
    env.pop("CLAUDE_CONFIG_DIR", None)
    if config_dir is not None:
        env["CLAUDE_CONFIG_DIR"] = config_dir
    env["PYTHONPATH"] = os.pathsep.join(
        [package_parent] + ([env["PYTHONPATH"]] if env.get("PYTHONPATH") else [])
    )
    done = subprocess.run(
        [sys.executable, "-m", "agent_profile_sessions", "--root", root_arg],
        capture_output=True, text=True, env=env, timeout=60, stdin=subprocess.DEVNULL,
    )
    return done.returncode, done.stderr.strip()


def test_it_refuses_to_start_without_claude_config_dir(root):
    code, message = _run_main(root, None)
    assert code == 2
    assert message == (
        f"agent-profile-sessions: refusing to start: CLAUDE_CONFIG_DIR is unset, "
        f"--root is {root}"
    )


def test_it_refuses_to_start_on_a_mismatched_root(root, tmp_path):
    other = tmp_path / "other-root"
    other.mkdir()
    code, message = _run_main(root, str(other))
    assert code == 2
    assert message == (
        f"agent-profile-sessions: refusing to start: CLAUDE_CONFIG_DIR is {other}, "
        f"--root is {root}"
    )


def test_it_refuses_a_root_that_is_not_a_directory(tmp_path):
    missing = str(tmp_path / "gone")
    code, message = _run_main(missing, missing)
    assert code == 2
    assert message.endswith(f"refusing to start: --root is not a directory: {missing}")
