from collections.abc import Callable, Generator
from typing import Any, cast

from sqlalchemy import Engine, create_engine
from sqlalchemy.orm import Session, sessionmaker

from app.core.config import get_settings

engine: Engine | None = None
SessionLocal: sessionmaker[Session] | None = None


def _get_session_factory() -> sessionmaker[Session]:
    global SessionLocal, engine

    if SessionLocal is None:
        settings = get_settings()
        if not settings.database_url:
            raise RuntimeError("DATABASE_URL must be configured before opening a database session")
        engine = create_engine(settings.database_url, pool_pre_ping=True)
        SessionLocal = sessionmaker(
            bind=engine,
            autoflush=False,
            expire_on_commit=False,
        )
    return SessionLocal


class _LazySession:
    def __init__(self, factory: Callable[[], Session]):
        self._factory = factory
        self._session: Session | None = None

    def _get_session(self) -> Session:
        if self._session is None:
            self._session = self._factory()
        return self._session

    def __getattr__(self, name: str) -> Any:
        return getattr(self._get_session(), name)

    def close(self) -> None:
        if self._session is not None:
            self._session.close()


def get_db() -> Generator[Session, None, None]:
    db = _LazySession(lambda: _get_session_factory()())
    try:
        yield cast(Session, db)
    finally:
        db.close()
