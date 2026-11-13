from __future__ import annotations

from pydantic import BaseModel, ConfigDict, Field


class ListingAgentsUpdate(BaseModel):
    model_config = ConfigDict(extra="forbid")

    agent_ids: list[str] = Field(max_length=50)


class AssignedAgent(BaseModel):
    id: str
    email: str
    active: bool


class ListingAgentsResponse(BaseModel):
    agents: list[AssignedAgent]
