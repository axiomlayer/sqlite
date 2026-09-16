#!/bin/sh
set -eu

if [ "$#" -ne 2 ]; then
  printf 'usage: %s SQLITE_PREFIX EXPECTED_VERSION\n' "$0" >&2
  exit 64
fi

sqlite_prefix=$1
expected_version=$2

if [ ! -x "$sqlite_prefix/bin/sqlite3" ]; then
  printf 'missing SQLite CLI: %s/bin/sqlite3\n' "$sqlite_prefix" >&2
  exit 1
fi

case $(uname -s) in
  Linux)
    LD_LIBRARY_PATH="$sqlite_prefix/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
    export LD_LIBRARY_PATH
    sqlite_extension=$(python3 -c 'import _sqlite3; print(_sqlite3.__file__)')
    resolved=$(ldd "$sqlite_extension")
    printf '%s\n' "$resolved" | grep -F "$sqlite_prefix/lib/libsqlite3" >/dev/null || {
      printf '%s\n' "$resolved" >&2
      printf 'Python did not resolve SQLite from %s/lib\n' "$sqlite_prefix" >&2
      exit 1
    }
    ;;
  Darwin)
    DYLD_LIBRARY_PATH="$sqlite_prefix/lib${DYLD_LIBRARY_PATH:+:$DYLD_LIBRARY_PATH}"
    export DYLD_LIBRARY_PATH
    ;;
  *)
    printf 'unsupported Python integration host: %s\n' "$(uname -s)" >&2
    exit 1
    ;;
esac

python3 - "$expected_version" <<'PY'
import sqlite3
import sys

expected_version = sys.argv[1]
if sqlite3.sqlite_version != expected_version:
    raise SystemExit(
        f"Python loaded SQLite {sqlite3.sqlite_version}, expected {expected_version}"
    )

connection = sqlite3.connect(":memory:")
enabled = connection.execute(
    "SELECT sqlite_compileoption_used('ENABLE_FTS5')"
).fetchone()[0]
if enabled != 1:
    raise SystemExit("Python's loaded SQLite lacks ENABLE_FTS5")

connection.execute("CREATE VIRTUAL TABLE docs USING fts5(body)")
connection.execute("INSERT INTO docs(body) VALUES (?)", ("axiom layer",))
matches = connection.execute(
    "SELECT count(*) FROM docs WHERE docs MATCH 'axiom'"
).fetchone()[0]
if matches != 1:
    raise SystemExit(f"Python FTS5 search returned {matches}, expected 1")

print(f"python_sqlite_version={sqlite3.sqlite_version}")
print("python_fts5=verified")
PY
