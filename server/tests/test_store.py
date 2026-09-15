"""Tests for scanning, parsing, caching and confinement."""

from __future__ import annotations

import json
import os

import pytest

from agent_profile_sessions.store import Store, parse_bound, parse_iso

from conftest import lorem, prompt, write_jsonl


def test_identity_columns(root):
    session = Store(root).session("s-alpha-1")
    assert session.cwd == "/work/alpha"
    assert session.git_branch == "main"
    assert session.version == "2.1.272"
    assert session.started_at == "2026-09-10T09:00:00.000Z"
    assert session.last_at == "2026-09-10T09:02:10.000Z"
    assert session.first_prompt.startswith("fix the retry in the invoice fetcher")
    assert session.size_bytes > 0
    assert session.has_subagents is True


def test_title_comes_from_the_custom_title_record(root):
    store = Store(root)
    assert store.session("s-alpha-1").title == "Invoice retries"
    assert store.session("s-alpha-2").title is None


def test_tool_result_user_records_are_not_prompts(root):
    session = Store(root).session("s-alpha-1")
    # Two prompts were typed, three user records are tool output.
    assert session.prompts == 2
    assert session.replies == 2
    assert session.tool_calls == 2
    assert len(session.messages) == 7
    assert [r.is_tool_result for r in session.messages] == [
        False, False, True, False, True, False, True
    ]


def test_unparsable_lines_and_unknown_types_are_skipped(root):
    session = Store(root).session("s-alpha-1")
    # Ten valid records, the broken line is not one of them.
    assert session.records == 10
    assert session.tool_histogram == {"Read": 1, "Edit": 1}
    assert session.files_touched == ["/work/alpha/fetcher.py"]
    assert session.last_reply == "done, the backoff is in place"


def test_sessions_are_newest_first_and_set_aside_files_are_skipped(root):
    ids = [s.session_id for s in Store(root).sessions()]
    assert ids == ["s-beta-1", "s-alpha-2", "s-alpha-1"]
    assert not any("orphaned" in i or "superseded" in i for i in ids)


def test_unknown_session_id_raises(root):
    with pytest.raises(ValueError, match="unknown session_id"):
        Store(root).session("no-such-session")
    with pytest.raises(ValueError, match="unknown session_id"):
        Store(root).session("../escape")


def test_a_symlink_out_of_projects_is_skipped(root, tmp_path):
    outside = tmp_path / "outside"
    outside.mkdir()
    write_jsonl(
        str(outside / "s-outside-1.jsonl"),
        [prompt("secret from another root", ts="2026-09-15T10:00:00.000Z", uuid="x1",
                session_id="s-outside-1", cwd="/work/secret", branch="main")],
    )
    projects = os.path.join(root, "projects")
    os.symlink(str(outside), os.path.join(projects, "-work-secret"))
    os.symlink(str(outside / "s-outside-1.jsonl"),
               os.path.join(projects, "-work-alpha", "s-outside-1.jsonl"))

    store = Store(root)
    ids = [s.session_id for s in store.sessions()]
    assert "s-outside-1" not in ids
    assert ids == ["s-beta-1", "s-alpha-2", "s-alpha-1"]
    assert store.confined(os.path.join(projects, "-work-secret", "s-outside-1.jsonl")) is False


def test_subagents_are_read_through_the_parent(root):
    store = Store(root)
    session = store.session("s-alpha-1")
    assert [a for a, _ in store.subagent_files(session)] == ["aa11"]
    assert session.agent_types == {"aa11": "explorer"}
    transcript = store.subagent(session, "aa11")
    assert len(transcript.messages) == 12
    # The file name spelling is accepted as well as the bare id.
    assert store.subagent(session, "agent-aa11").records == 12
    with pytest.raises(ValueError, match="unknown agent_id"):
        store.subagent(session, "nope")
    with pytest.raises(ValueError, match="unknown agent_id"):
        store.subagent(session, "../../escape")


def test_the_cache_rereads_a_file_that_grew(root):
    store = Store(root)
    first = store.session("s-alpha-2")
    assert store.session("s-alpha-2") is first
    path = os.path.join(root, "projects", "-work-alpha", "s-alpha-2.jsonl")
    with open(path, "a", encoding="utf-8") as handle:
        handle.write(json.dumps(prompt("one more question", ts="2026-09-12T12:00:00.000Z",
                                       uuid="u9", session_id="s-alpha-2", cwd="/work/alpha",
                                       branch="feature")) + "\n")
    second = store.session("s-alpha-2")
    assert second is not first
    assert second.prompts == first.prompts + 1


def test_retention_days_reads_one_key_and_tolerates_rubbish(root):
    store = Store(root)
    assert store.retention_days() is None
    settings = os.path.join(root, "settings.json")
    with open(settings, "w", encoding="utf-8") as handle:
        handle.write(json.dumps({"cleanupPeriodDays": 45, "other": "ignored"}))
    assert Store(root).retention_days() == 45
    with open(settings, "w", encoding="utf-8") as handle:
        handle.write("{ not json at all")
    assert Store(root).retention_days() is None


def test_spilled_tool_results_are_read_only_from_the_session_directory(root):
    store = Store(root)
    session = store.session("s-alpha-1")
    record = next(r for r in session.messages if r.uuid == "r3")
    assert record.spilled
    spilled = store.read_spilled(session, record.spilled, 100)
    assert len(spilled) == 1
    assert spilled[0]["text"].startswith("spilled ")
    assert spilled[0]["truncated"] is True
    # A reference to somewhere else is not followed.
    assert store.read_spilled(session, ["/etc/hostname"], 100) == []


def test_iso_parsing(root):
    assert parse_iso("2026-09-10T09:00:00.000Z").year == 2026
    assert parse_iso("2026-09-10T09:00:00.123456789Z") is not None
    assert parse_iso("not a date") is None
    assert parse_bound(None, "since", end_of_day=False) is None
    assert parse_bound("2026-09-10", "until", end_of_day=True).hour == 23
    with pytest.raises(ValueError, match="ISO-8601"):
        parse_bound("last tuesday", "since", end_of_day=False)


def test_lorem_is_long_enough_for_the_fixtures():
    assert len(lorem(5000)) == 5000
