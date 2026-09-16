# agent-profile-sessions

A small MCP server that gives one Claude Code session read-only, capped,
structured access to the transcripts in its own profile's config root. It is
the Python half of the sessions server described in
`docs/proposals/2026-09-15-sessions-mcp.md`.

It opens `<root>/projects` and nothing else in the root, with one exception:
the `cleanupPeriodDays` key of `<root>/settings.json`, so that a listing can
say how long transcripts survive. It never writes anything, anywhere, and it
has no network, no shell and no HTTP transport.

## How it is started

Never by hand. Claude Code starts the launcher as a stdio child of the session
it belongs to, and the launcher execs this server:

```
claude  ->  agpin mcp serve --root <root>  ->  python -m agent_profile_sessions --root <root>
```

Both halves make the same check: `CLAUDE_CONFIG_DIR` must be set and must
resolve to the same directory as `--root`. When it does not, the server prints
one line on stderr and exits 2, so a registration that was copied into another
root fails visibly in `/mcp` rather than serving one account's transcripts to
another. Transport is stdio only.

## The tools

| Tool | What it returns |
| --- | --- |
| `list_projects()` | One row per working directory, with session counts and the retention window |
| `list_sessions(cwd, since, until, branch, query, limit, cursor)` | Session identity columns, newest activity first, with a first prompt preview |
| `session_summary(session_id)` | The identity columns, the last reply, a tool histogram, the files touched and the subagents, the last two capped |
| `get_session(session_id, agent_id, start, limit, roles, include_tool_results, include_thinking, max_chars)` | A range of messages, by record index |
| `get_message(session_id, uuid, agent_id, max_chars, include_spilled)` | One message whole, optionally with the tool output it spilled to a file |
| `search(query, cwd, since, until, branch, roles, limit)` | Pointers into `get_session`, with a snippet |

Subagent transcripts are reached through their parent session, with
`agent_id`, and never listed as sessions of their own.

## The caps

| Cap | Value |
| --- | --- |
| Text in one `get_session` reply | 40,000 characters, then it stops and says where to continue |
| `get_session` messages per call | 50 by default, clamped to 1..100 |
| `get_session` characters per message | 2,000 by default, clamped to 1..20,000 |
| `get_message` characters | 20,000 by default, clamped to 1..100,000 |
| `list_sessions` rows per page | 20 by default, clamped to 1..100 |
| `search` hits | 20 by default, clamped to 1..50, snippets of 240 characters |
| `session_summary` files touched | 100, with `files_touched_total` and `files_touched_truncated` beside them |
| `session_summary` subagents | 20, with `subagents_total` and `subagents_truncated` beside them |
| `first_prompt` preview, `last_reply` | 200 and 500 characters |

Tool results and thinking are left out of `get_session` unless asked for by
name. Every text-bearing structure carries `"source": "transcript"`, because
transcript text is data written by earlier sessions and not instructions.

`search` has no regular expression mode. It had one, and a pattern of six
characters could take this server, which is single threaded and lives for the
session, out of service for the rest of it; the pattern is chosen by a model
reading a transcript, which is the threat the rest of this design takes
seriously. Substring with the `cwd`, date and branch filters covers what it
was used for.

## Tests

From this directory:

```sh
uv sync --frozen --group dev
uv run --frozen --group dev pytest -q
```

The fixtures write invented transcripts into pytest's `tmp_path`. No test
reads a real transcript.

## Files

`requirements.txt` is generated and carries hashes, for the installer path
that has no `uv`:

```sh
uv lock
uv export --frozen --no-dev --no-emit-project --format requirements-txt -o requirements.txt
```
