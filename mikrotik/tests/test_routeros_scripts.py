from __future__ import annotations

import os
import pathlib
import re
from typing import Any

import pytest
from routeros_api import exceptions as ros_exc

MIKROTIK_DIR = pathlib.Path(__file__).resolve().parent.parent
EXPECT_VER = os.environ.get("EXPECT_ROUTEROS_VERSION", "7.22")
SCRIPT_FILES = sorted(p for p in MIKROTIK_DIR.glob("*.lua") if p.is_file())

# Scripts safe to load+run during tests (no reboot, no upstream calls).
RUNNABLE_SCRIPTS = ("wan_failover_notify", "health_check", "detect_internet")


def _row_id(row: dict) -> str:
    for k in (".id", b".id"):
        if k in row:
            v = row[k]
            return v.decode() if isinstance(v, bytes) else str(v)
    raise KeyError(".id missing in %r" % (row,))


def _row_str(row: dict, key: str) -> str:
    for k in (key, key.encode()):
        if k in row:
            v = row[k]
            return v.decode() if isinstance(v, bytes) else str(v)
    return ""


def _find_id(resource: Any, name: str) -> str | None:
    for row in resource.get():
        if _row_str(row, "name") == name:
            return _row_id(row)
    return None


def _remove_by_name(resource: Any, name: str) -> None:
    rid = _find_id(resource, name)
    if rid is not None:
        resource.call("remove", {".id": rid})


def _add_script(resource: Any, name: str, source: str) -> None:
    _remove_by_name(resource, name)
    resource.call("add", {"name": name, "source": source})


def _run_named(api: Any, name: str) -> None:
    res = api.get_binary_resource("/system/script")
    rid = _find_id(res, name)
    assert rid is not None, f"script {name!r} not found"
    res.call("run", {".id": rid})


@pytest.mark.skipif(not SCRIPT_FILES, reason="no .lua files under mikrotik/")
def test_script_files_are_non_empty() -> None:
    for p in SCRIPT_FILES:
        assert p.read_text(encoding="utf-8", errors="strict").strip(), f"empty: {p.name}"


def test_routeros_version_matches(api: Any) -> None:
    rows = list(api.get_binary_resource("/system/resource").get())
    assert rows, "/system resource returned empty"
    ver = _row_str(rows[0], "version")
    assert ver, f"version missing in /system resource row: {rows[0]!r}"
    pattern = rf"^{re.escape(EXPECT_VER)}(\.|\b)"
    assert re.match(pattern, ver), (
        f"expected version starting with {EXPECT_VER!r}, got {ver!r}"
    )


@pytest.mark.parametrize("path", SCRIPT_FILES, ids=[p.stem for p in SCRIPT_FILES])
def test_script_add_remove_roundtrip(
    path: pathlib.Path,
    script_resource: Any,
) -> None:
    """Each repo .lua is added as /system/script (parses on real RouterOS) and removed."""
    name = "pu_ut_" + re.sub(r"[^0-9a-zA-Z_]", "_", path.stem)
    source = path.read_text(encoding="utf-8", errors="replace")
    try:
        _add_script(script_resource, name, source)
        rid = _find_id(script_resource, name)
        assert rid is not None, f"script {name!r} not visible after add"
    finally:
        _remove_by_name(script_resource, name)


@pytest.mark.parametrize("script_name", RUNNABLE_SCRIPTS)
def test_run_safe_scripts(api: Any, script_resource: Any, script_name: str) -> None:
    """
    Install each runnable script under its real name (so :parse [/system script get …] works)
    and execute it once. tg_send is already a stub from the session fixture.
    detect_internet writes to /interface detect-internet which exists on CHR.
    """
    src = (MIKROTIK_DIR / f"{script_name}.lua").read_text(encoding="utf-8", errors="replace")
    try:
        _add_script(script_resource, script_name, src)
        try:
            _run_named(api, script_name)
        except ros_exc.RouterOsApiError as e:
            pytest.fail(f"running {script_name!r} on RouterOS failed: {e}")
    finally:
        _remove_by_name(script_resource, script_name)
