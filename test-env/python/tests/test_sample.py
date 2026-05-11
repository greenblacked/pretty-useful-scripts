from sample import __version__, greet


def test_greet() -> None:
    assert greet() == "hello, world"
    assert greet("docker") == "hello, docker"


def test_version() -> None:
    assert __version__ == "0.1.0"
