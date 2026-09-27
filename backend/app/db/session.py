from __future__ import annotations

from collections.abc import Iterator

from sqlalchemy import create_engine
from sqlalchemy.engine import Engine, make_url
from sqlalchemy.orm import Session, sessionmaker


def create_session_factory(
    database_url: str,
    *,
    connect_timeout_seconds: int = 5,
    pool_timeout_seconds: int = 5,
    statement_timeout_seconds: int = 10,
) -> tuple[Engine, sessionmaker[Session]]:
    engine_options: dict[str, object] = {"pool_pre_ping": True}
    if make_url(database_url).drivername == "postgresql+psycopg":
        engine_options.update(
            pool_timeout=pool_timeout_seconds,
            connect_args={
                "connect_timeout": connect_timeout_seconds,
                "options": f"-c statement_timeout={statement_timeout_seconds * 1000}",
            },
        )
    engine = create_engine(database_url, **engine_options)
    return engine, sessionmaker(bind=engine, autoflush=False, expire_on_commit=False)


def session_scope(factory: sessionmaker[Session]) -> Iterator[Session]:
    session = factory()
    try:
        yield session
    finally:
        session.close()
