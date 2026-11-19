"""Exercise the actual additive revision against a preserved historical row (SQLite)."""
import importlib.util
from pathlib import Path

from alembic.migration import MigrationContext
from alembic.operations import Operations
from sqlalchemy import create_engine, inspect, text


def test_capture_integrity_revision_roundtrip_preserves_existing_data() -> None:
    path = Path(__file__).resolve().parents[1] / "alembic/versions/0036_capture_integrity.py"
    spec = importlib.util.spec_from_file_location("capture_integrity_revision", path)
    assert spec is not None and spec.loader is not None
    revision = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(revision)
    engine = create_engine("sqlite://")
    with engine.begin() as connection:
        connection.execute(text("CREATE TABLE listing_capture (id TEXT PRIMARY KEY, status TEXT NOT NULL)"))
        connection.execute(text("INSERT INTO listing_capture VALUES ('historical', 'completed')"))
        with Operations.context(MigrationContext.configure(connection)):
            revision.upgrade()
            assert {"package_sha256", "package_manifest"} <= {
                c["name"] for c in inspect(connection).get_columns("listing_capture")
            }
            assert connection.execute(text("SELECT package_manifest FROM listing_capture")).scalar() is None
            revision.downgrade()
        assert connection.execute(text("SELECT id, status FROM listing_capture")).one() == ("historical", "completed")
    engine.dispose()
