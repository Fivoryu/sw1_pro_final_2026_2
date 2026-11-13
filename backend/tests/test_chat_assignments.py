from __future__ import annotations

from chat_support import AGENCY, AgencyApiContext, seed_listing, seed_staff

URL = f"/api/v1/staff/agencies/{AGENCY}/listings/listing-chat/agents"


def test_agency_admin_assigns_and_replaces_agents(agency_api_context: AgencyApiContext) -> None:
    context = agency_api_context
    seed_listing(context)
    admin = seed_staff(context, "admin-1", role="agency_admin")
    seed_staff(context, "agent-a")
    seed_staff(context, "agent-b")

    assert context.client.get(URL, headers=admin).json() == {"agents": []}

    first = context.client.put(URL, json={"agent_ids": ["agent-a", "agent-b"]}, headers=admin)
    assert first.status_code == 200
    assert [a["id"] for a in first.json()["agents"]] == ["agent-a", "agent-b"]

    second = context.client.put(URL, json={"agent_ids": ["agent-b", "agent-b"]}, headers=admin)
    assert second.status_code == 200
    assert [a["id"] for a in second.json()["agents"]] == ["agent-b"]
    assert context.client.get(URL, headers=admin).json() == second.json()


def test_assignment_rejects_inactive_foreign_and_unknown_agents(
    agency_api_context: AgencyApiContext,
) -> None:
    context = agency_api_context
    seed_listing(context)
    admin = seed_staff(context, "admin-1", role="agency_admin")
    seed_staff(context, "agent-off", active=False)
    seed_staff(context, "agent-other", agency_id="other-agency")
    seed_staff(context, "admin-2", role="agency_admin")

    for agent_id in ("agent-off", "agent-other", "ghost", "admin-2"):
        response = context.client.put(URL, json={"agent_ids": [agent_id]}, headers=admin)
        assert response.status_code == 422, agent_id
    assert context.client.get(URL, headers=admin).json() == {"agents": []}


def test_assignment_is_limited_to_the_agency_admin_of_that_agency(
    agency_api_context: AgencyApiContext,
) -> None:
    context = agency_api_context
    seed_listing(context)
    seed_staff(context, "agent-a")
    agent = seed_staff(context, "agent-x")
    other_admin = seed_staff(context, "admin-other", role="agency_admin", agency_id="other-agency")
    platform = seed_staff(context, "root", role="platform_admin", agency_id=None)

    for headers in (agent, other_admin, platform):
        assert context.client.get(URL, headers=headers).status_code == 403
        assert (
            context.client.put(URL, json={"agent_ids": ["agent-a"]}, headers=headers).status_code
            == 403
        )
    assert context.client.get(URL).status_code == 401


def test_assignment_of_a_listing_from_another_agency_is_not_found(
    agency_api_context: AgencyApiContext,
) -> None:
    context = agency_api_context
    seed_listing(context)
    seed_listing(context, "listing-foreign", agency_id="other-agency")
    admin = seed_staff(context, "admin-1", role="agency_admin")

    url = f"/api/v1/staff/agencies/{AGENCY}/listings/listing-foreign/agents"
    assert context.client.get(url, headers=admin).status_code == 404
    assert context.client.put(url, json={"agent_ids": []}, headers=admin).status_code == 404
