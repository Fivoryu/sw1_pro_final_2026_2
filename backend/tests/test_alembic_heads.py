from __future__ import annotations

from pathlib import Path

from alembic.config import Config
from alembic.script import ScriptDirectory


def test_migration_history_has_one_head_containing_both_branches() -> None:
    backend = Path(__file__).resolve().parents[1]
    config = Config(str(backend / "alembic.ini"))
    config.set_main_option("script_location", str(backend / "alembic"))
    scripts = ScriptDirectory.from_config(config)

    heads = scripts.get_heads()
    assert len(heads) == 1, f"expected one Alembic head, got {heads}"
    history = {revision.revision for revision in scripts.walk_revisions(head=heads[0])}
    assert {"0028_extra_inclusion", "0034_listing_reviews"} <= history
