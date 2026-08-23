from collections.abc import Generator

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


def get_db() -> Generator[Session, None, None]:
    db = _get_session_factory()()
    try:
        yield db
    finally:
        db.close()
