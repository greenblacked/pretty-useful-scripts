from __future__ import annotations

import os
import time
from typing import Any, Iterator

import pytest
import routeros_api
from routeros_api import exceptions as ros_exc

# Test-owned scripts on the router. Anything matching this prefix is fair game to
# remove — the tests own the namespace.
TEST_SCRIPT_PREFIX = "pu_ut_"
# Names the production scripts expect to call by name. We put a stub here for the duration
# of the session so running scripts that depend on tg_send doesn't try real HTTP requests.
TG_SEND_NAME = "tg_send"
TG_SEND_STUB_SOURCE = (
    ":global pu_TG_LAST_MESSAGE;\n"
    ":set pu_TG_LAST_MESSAGE $MessageText;\n"
    ":log info (\"pu_ut tg_send STUB: \" . $MessageText);\n"
)


def _connect_pool() -> routeros_api.RouterOsApiPool:
    host = os.environ.get("ROUTEROS_HOST", "127.0.0.1")
    port = int(os.environ.get("ROUTEROS_PORT", "8728"))
    user = os.environ.get("ROUTEROS_USER", "admin")
    password = os.environ.get("ROUTEROS_PASSWORD", "")
    pool = routeros_api.RouterOsApiPool(
        host,
        username=user,
        password=password,
        port=port,
        plaintext_login=True,
        use_ssl=False,
    )
    pool.set_timeout(20)
    pool.get_api()
    return pool


@pytest.fixture(scope="session")
def ros_pool() -> Iterator[routeros_api.RouterOsApiPool]:
    last: BaseException | None = None
    pool: routeros_api.RouterOsApiPool | None = None
    for attempt in range(1, 6):
        try:
            pool = _connect_pool()
            break
        except (ros_exc.RouterOsApiError, ros_exc.RouterOsApiConnectionError, OSError) as e:
            last = e
            time.sleep(2 * attempt)
    if pool is None:
        raise RuntimeError(f"could not connect to RouterOS API: {last!r}")
    try:
        yield pool
    finally:
        try:
            pool.disconnect()
        except Exception:
            pass


@pytest.fixture(scope="session")
def api(ros_pool: routeros_api.RouterOsApiPool) -> Any:
    return ros_pool.get_api()


def _row_id(row: dict) -> str:
    for key in (".id", b".id"):
        if key in row:
            v = row[key]
            return v.decode() if isinstance(v, bytes) else str(v)
    raise KeyError(".id missing in row %r" % (row,))


def _row_str(row: dict, key: str) -> str:
    for k in (key, key.encode()):
        if k in row:
            v = row[k]
            return v.decode() if isinstance(v, bytes) else str(v)
    return ""


def _remove_named_scripts(api: Any, predicate) -> int:
    res = api.get_binary_resource("/system/script")
    rows = list(res.get())
    removed = 0
    for row in rows:
        name = _row_str(row, "name")
        if predicate(name):
            try:
                res.call("remove", {".id": _row_id(row)})
                removed += 1
            except ros_exc.RouterOsApiError:
                pass
    return removed


@pytest.fixture(scope="session", autouse=True)
def _clean_router_state(api: Any) -> Iterator[None]:
    """Wipe any leftover test scripts and install the tg_send stub for the session."""
    _remove_named_scripts(
        api, lambda n: n.startswith(TEST_SCRIPT_PREFIX) or n in {TG_SEND_NAME, "wan_failover_notify", "health_check"}
    )
    api.get_binary_resource("/system/script").call(
        "add", {"name": TG_SEND_NAME, "source": TG_SEND_STUB_SOURCE}
    )
    try:
        yield
    finally:
        _remove_named_scripts(
            api, lambda n: n.startswith(TEST_SCRIPT_PREFIX) or n in {TG_SEND_NAME, "wan_failover_notify", "health_check"}
        )


@pytest.fixture
def script_resource(api: Any) -> Any:
    return api.get_binary_resource("/system/script")
