"""Scanning, parsing, caching and confinement for one Claude Code config root.

The store opens ``<root>/projects`` and nothing else in the root, with one
exception the server asks for by name, the ``cleanupPeriodDays`` key of
``<root>/settings.json``. Every path it opens is resolved with
:func:`os.path.realpath` and skipped unless it is still inside
``realpath(<root>/projects)``, so a symlink planted under ``projects`` cannot
walk the store out of the root.

Records are parsed into a compact per record form. The raw JSON is never kept,
because a root can hold hundreds of megabytes of transcript and the server
lives as long as the session that started it.
"""

from __future__ import annotations

import json
import os
import re
from dataclasses import dataclass, field
from datetime import datetime, timezone
from typing import Iterable, Iterator

# A session file is <root>/projects/<enc>/<sessionId>.jsonl. Claude Code sets
# earlier transcripts aside under names carrying these markers, and those are
# not sessions anyone asked for.
SET_ASIDE_MARKERS = (".orphaned-", ".superseded-")

AGENT_ID_RE = re.compile(r"^[A-Za-z0-9._-]+$")
AGENT_FILE_RE = re.compile(r"^agent-(.+)\.jsonl$")
SPILL_RE = re.compile(r"[^\s\"'`]*/tool-results/[^\s\"'`,;)\]}]+")

DEFAULT_RETENTION_DAYS = 30
MAX_SPILL_BYTES = 200_000


@dataclass(slots=True)
class Record:
    """One user or assistant record, reduced to what the tools return."""

    index: int
    uuid: str | None
    timestamp: str | None
    role: str
    is_tool_result: bool
    text: str = ""
    thinking: str = ""
    tool_result_text: str = ""
    tool_names: tuple[str, ...] = ()
    spilled: tuple[str, ...] = ()


@dataclass(slots=True)
class Session:
    """One transcript, parsed."""

    session_id: str
    path: str
    dir_name: str
    size_bytes: int
    cwd: str | None = None
    git_branch: str | None = None
    version: str | None = None
    started_at: str | None = None
    last_at: str | None = None
    title: str | None = None
    first_prompt: str | None = None
    prompts: int = 0
    replies: int = 0
    tool_calls: int = 0
    records: int = 0
    has_subagents: bool = False
    last_reply: str | None = None
    messages: list[Record] = field(default_factory=list)
    tool_histogram: dict[str, int] = field(default_factory=dict)
    files_touched: list[str] = field(default_factory=list)
    agent_types: dict[str, str] = field(default_factory=dict)

    @property
    def last_dt(self) -> datetime | None:
        return parse_iso(self.last_at)


def parse_iso(value: str | None) -> datetime | None:
    """Parse an ISO-8601 date or datetime into an aware UTC datetime.

    Tolerates a trailing ``Z`` and fractional seconds of any length, both of
    which the standard library refuses on some supported versions. Returns
    ``None`` when the value is absent or unparsable.
    """
    if not value or not isinstance(value, str):
        return None
    text = value.strip()
    if text.endswith(("Z", "z")):
        text = text[:-1] + "+00:00"
    match = re.match(r"^(.*\.\d+)(\D.*)?$", text)
    if match:
        head, tail = match.group(1), match.group(2) or ""
        base, _, frac = head.rpartition(".")
        frac = (frac + "000000")[:6]
        text = f"{base}.{frac}{tail}"
    try:
        parsed = datetime.fromisoformat(text)
    except ValueError:
        return None
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=timezone.utc)
    return parsed.astimezone(timezone.utc)


def parse_bound(value: str | None, name: str, end_of_day: bool) -> datetime | None:
    """Parse a ``since`` or ``until`` argument, raising ValueError when it is bad."""
    if value is None or value == "":
        return None
    parsed = parse_iso(value)
    if parsed is None:
        raise ValueError(f"{name} is not an ISO-8601 date or datetime: {value!r}")
    if end_of_day and re.match(r"^\d{4}-\d{2}-\d{2}$", str(value).strip()):
        parsed = parsed.replace(hour=23, minute=59, second=59, microsecond=999999)
    return parsed


def _blocks(content: object) -> list[dict]:
    """Normalise a message content field into a list of block dictionaries."""
    if isinstance(content, str):
        return [{"type": "text", "text": content}]
    if isinstance(content, list):
        return [b for b in content if isinstance(b, dict)]
    return []


def _block_text(value: object) -> str:
    """Flatten the text of a tool_result content field."""
    if isinstance(value, str):
        return value
    if isinstance(value, list):
        parts = []
        for item in value:
            if isinstance(item, str):
                parts.append(item)
            elif isinstance(item, dict):
                text = item.get("text")
                if isinstance(text, str):
                    parts.append(text)
        return "\n".join(parts)
    if isinstance(value, dict):
        text = value.get("text")
        if isinstance(text, str):
            return text
    return ""


def _spill_refs(*chunks: str) -> tuple[str, ...]:
    """Collect candidate spilled tool result paths out of record text."""
    found: list[str] = []
    for chunk in chunks:
        if not chunk or "/tool-results/" not in chunk:
            continue
        for match in SPILL_RE.findall(chunk):
            if match not in found:
                found.append(match)
    return tuple(found)


def parse_transcript(path: str, size_bytes: int, session_id: str, dir_name: str) -> Session:
    """Read one transcript file and reduce it to a :class:`Session`.

    Unparsable lines and unknown record types are skipped in silence, which is
    what the note asks for: a format change is an empty listing, never a crash.
    """
    session = Session(session_id=session_id, path=path, dir_name=dir_name, size_bytes=size_bytes)
    index = 0
    files_seen: set[str] = set()
    try:
        handle = open(path, "r", encoding="utf-8", errors="replace")
    except OSError:
        return session
    with handle:
        for line in handle:
            line = line.strip()
            if not line:
                continue
            try:
                raw = json.loads(line)
            except ValueError:
                continue
            if not isinstance(raw, dict):
                continue
            kind = raw.get("type")
            if not isinstance(kind, str):
                continue
            session.records += 1
            if kind == "custom-title":
                title = raw.get("customTitle")
                if isinstance(title, str) and title:
                    session.title = title
                continue
            if kind not in ("user", "assistant"):
                continue

            if session.cwd is None and isinstance(raw.get("cwd"), str):
                session.cwd = raw["cwd"]
            if session.git_branch is None and isinstance(raw.get("gitBranch"), str):
                session.git_branch = raw["gitBranch"]
            if session.version is None and isinstance(raw.get("version"), str):
                session.version = raw["version"]

            timestamp = raw.get("timestamp") if isinstance(raw.get("timestamp"), str) else None
            if session.started_at is None:
                session.started_at = timestamp
            if timestamp:
                session.last_at = timestamp

            message = raw.get("message")
            content = message.get("content") if isinstance(message, dict) else None
            blocks = _blocks(content)

            texts: list[str] = []
            thinking: list[str] = []
            results: list[str] = []
            tool_names: list[str] = []
            has_result_block = False
            for block in blocks:
                btype = block.get("type")
                if btype == "text":
                    value = block.get("text")
                    if isinstance(value, str):
                        texts.append(value)
                elif btype == "thinking":
                    value = block.get("thinking") or block.get("text")
                    if isinstance(value, str):
                        thinking.append(value)
                elif btype == "tool_use":
                    name = block.get("name")
                    if isinstance(name, str):
                        tool_names.append(name)
                        session.tool_calls += 1
                        session.tool_histogram[name] = session.tool_histogram.get(name, 0) + 1
                    payload = block.get("input")
                    if isinstance(payload, dict):
                        target = payload.get("file_path")
                        if isinstance(target, str) and target:
                            files_seen.add(target)
                elif btype == "tool_result":
                    has_result_block = True
                    results.append(_block_text(block.get("content")))

            tool_result_payload = raw.get("toolUseResult")
            if isinstance(tool_result_payload, dict):
                agent_id = tool_result_payload.get("agentId")
                agent_type = tool_result_payload.get("agentType")
                if isinstance(agent_id, str) and isinstance(agent_type, str):
                    session.agent_types[agent_id] = agent_type

            role = raw.get("role")
            if not isinstance(role, str):
                role = message.get("role") if isinstance(message, dict) else None
            if not isinstance(role, str) or role not in ("user", "assistant"):
                role = kind

            # A user record that carries a tool result is the agent's own
            # machinery, not something a person typed.
            is_tool_result = role == "user" and (
                tool_result_payload is not None or (has_result_block and not texts)
            )

            text = "\n".join(t for t in texts if t)
            record = Record(
                index=index,
                uuid=raw.get("uuid") if isinstance(raw.get("uuid"), str) else None,
                timestamp=timestamp,
                role=role,
                is_tool_result=is_tool_result,
                text=text,
                thinking="\n".join(t for t in thinking if t),
                tool_result_text="\n".join(r for r in results if r),
                tool_names=tuple(tool_names),
                spilled=_spill_refs(*results, _block_text(tool_result_payload)),
            )
            session.messages.append(record)
            index += 1

            if role == "user" and not is_tool_result:
                session.prompts += 1
                if session.first_prompt is None and text.strip():
                    session.first_prompt = text.strip()[:200]
            elif role == "assistant":
                session.replies += 1
                if text.strip():
                    session.last_reply = text.strip()[:500]

    session.files_touched = sorted(files_seen)
    return session


class Store:
    """The one reader of ``<root>/projects``, with an in memory cache."""

    def __init__(self, root: str) -> None:
        self.root = os.path.realpath(root)
        self.projects = os.path.realpath(os.path.join(self.root, "projects"))
        self._cache: dict[str, tuple[tuple[int, int], Session]] = {}

    # Confinement -----------------------------------------------------------

    def confined(self, path: str) -> bool:
        """True when ``path`` still resolves to somewhere inside projects/."""
        try:
            real = os.path.realpath(path)
        except OSError:
            return False
        return real.startswith(self.projects + os.sep)

    # Scanning --------------------------------------------------------------

    def _iter_transcripts(self) -> Iterator[tuple[str, str, str, os.stat_result]]:
        """Yield (dir_name, session_id, path, stat) for every transcript file."""
        try:
            containers = list(os.scandir(self.projects))
        except OSError:
            return
        for container in sorted(containers, key=lambda e: e.name):
            try:
                if not container.is_dir():
                    continue
            except OSError:
                continue
            if not self.confined(container.path):
                continue
            try:
                entries = list(os.scandir(container.path))
            except OSError:
                continue
            for entry in sorted(entries, key=lambda e: e.name):
                name = entry.name
                if not name.endswith(".jsonl"):
                    continue
                if any(marker in name for marker in SET_ASIDE_MARKERS):
                    continue
                try:
                    if not entry.is_file():
                        continue
                    info = entry.stat()
                except OSError:
                    continue
                if not self.confined(entry.path):
                    continue
                yield container.name, name[: -len(".jsonl")], entry.path, info

    def _load(self, dir_name: str, session_id: str, path: str, info: os.stat_result) -> Session:
        """Return a parsed transcript, from the cache when the file is unchanged."""
        key = (info.st_size, info.st_mtime_ns)
        cached = self._cache.get(path)
        if cached is not None and cached[0] == key:
            return cached[1]
        session = parse_transcript(path, info.st_size, session_id, dir_name)
        session.has_subagents = bool(self.subagent_files(session))
        self._cache[path] = (key, session)
        return session

    def sessions(self) -> list[Session]:
        """Every transcript under projects/, parsed, newest last_at first."""
        found = [
            self._load(dir_name, session_id, path, info)
            for dir_name, session_id, path, info in self._iter_transcripts()
        ]
        epoch = datetime.fromtimestamp(0, tz=timezone.utc)
        found.sort(key=lambda s: (s.last_dt or epoch, s.session_id), reverse=True)
        return found

    def session(self, session_id: str) -> Session:
        """One session by id, or ValueError when there is no such transcript."""
        if not isinstance(session_id, str) or not session_id or "/" in session_id:
            raise ValueError(f"unknown session_id: {session_id!r}")
        for dir_name, found_id, path, info in self._iter_transcripts():
            if found_id == session_id:
                return self._load(dir_name, found_id, path, info)
        raise ValueError(f"unknown session_id: {session_id!r}")

    # Subagents -------------------------------------------------------------

    def session_dir(self, session: Session) -> str:
        return os.path.join(os.path.dirname(session.path), session.session_id)

    def subagent_files(self, session: Session) -> list[tuple[str, str]]:
        """List (agent_id, path) for the session's subagent transcripts."""
        directory = os.path.join(self.session_dir(session), "subagents")
        if not self.confined(directory):
            return []
        try:
            entries = list(os.scandir(directory))
        except OSError:
            return []
        found: list[tuple[str, str]] = []
        for entry in sorted(entries, key=lambda e: e.name):
            match = AGENT_FILE_RE.match(entry.name)
            if not match:
                continue
            if any(marker in entry.name for marker in SET_ASIDE_MARKERS):
                continue
            try:
                if not entry.is_file():
                    continue
            except OSError:
                continue
            if not self.confined(entry.path):
                continue
            found.append((match.group(1), entry.path))
        return found

    def subagent(self, session: Session, agent_id: str) -> Session:
        """Parse one subagent transcript of this session."""
        if not isinstance(agent_id, str) or not agent_id:
            raise ValueError("agent_id must be a non empty string")
        wanted = agent_id[len("agent-") :] if agent_id.startswith("agent-") else agent_id
        if wanted.endswith(".jsonl"):
            wanted = wanted[: -len(".jsonl")]
        if not AGENT_ID_RE.match(wanted) or wanted in (".", ".."):
            raise ValueError(f"unknown agent_id: {agent_id!r}")
        for found_id, path in self.subagent_files(session):
            if found_id == wanted:
                try:
                    info = os.stat(path)
                except OSError:
                    break
                key = (info.st_size, info.st_mtime_ns)
                cached = self._cache.get(path)
                if cached is not None and cached[0] == key:
                    return cached[1]
                parsed = parse_transcript(
                    path, info.st_size, session.session_id, session.dir_name
                )
                self._cache[path] = (key, parsed)
                return parsed
        raise ValueError(f"unknown agent_id: {agent_id!r} in session {session.session_id}")

    def transcript(self, session_id: str, agent_id: str | None) -> tuple[Session, Session]:
        """Return (session, transcript), where the transcript may be a subagent's."""
        session = self.session(session_id)
        if agent_id:
            return session, self.subagent(session, agent_id)
        return session, session

    # Spilled tool results --------------------------------------------------

    def read_spilled(self, session: Session, refs: Iterable[str], max_chars: int) -> list[dict]:
        """Read the spilled tool result files a record refers to, capped."""
        base = os.path.realpath(os.path.join(self.session_dir(session), "tool-results"))
        if not base.startswith(self.projects + os.sep):
            return []
        out: list[dict] = []
        for ref in refs:
            candidate = ref if os.path.isabs(ref) else os.path.join(base, os.path.basename(ref))
            real = os.path.realpath(candidate)
            if not real.startswith(base + os.sep):
                continue
            if not self.confined(real) or not os.path.isfile(real):
                continue
            try:
                with open(real, "r", encoding="utf-8", errors="replace") as handle:
                    body = handle.read(MAX_SPILL_BYTES + 1)
            except OSError:
                continue
            truncated = len(body) > max_chars or len(body) > MAX_SPILL_BYTES
            out.append(
                {
                    "path": real,
                    "text": body[:max_chars],
                    "truncated": truncated,
                    "source": "transcript",
                }
            )
        return out

    # The one read outside projects/ ----------------------------------------

    def retention_days(self) -> int | None:
        """``cleanupPeriodDays`` from <root>/settings.json, or None when unreadable.

        This is the only file outside projects/ the server ever opens, and only
        this one key is taken from it. A missing or malformed file is not an
        error, it means the caller gets the documented default instead.
        """
        path = os.path.join(self.root, "settings.json")
        try:
            with open(path, "r", encoding="utf-8", errors="replace") as handle:
                data = json.load(handle)
        except (OSError, ValueError):
            return None
        if not isinstance(data, dict):
            return None
        value = data.get("cleanupPeriodDays")
        if isinstance(value, bool):
            return None
        if isinstance(value, int):
            return value
        if isinstance(value, float) and value.is_integer():
            return int(value)
        return None
