from test_f04_publications import (
    F04Context,
    _collection_url,
    _payload,
    _seed_confirmed_photo,
    _staff,
    _url,
    f04_context,  # noqa: F401
)


def test_coordinates_round_trip_on_staff_and_public_interfaces(f04_context: F04Context) -> None:  # noqa: F811
    context = f04_context
    _staff(context)
    created = context.client.post(
        _collection_url("agency-one"), json=_payload(latitude=-16.5, longitude=-68.15)
    )
    assert created.status_code == 201, created.text
    assert created.json()["latitude"] == -16.5
    assert created.json()["longitude"] == -68.15
    url = _url("agency-one", created.json()["listing_id"])
    edited = context.client.put(url, json=_payload(latitude=90, longitude=180))
    assert edited.status_code == 200, edited.text
    assert context.client.get(url).json()["latitude"] == 90
    _seed_confirmed_photo(context, created.json()["listing_id"])
    assert context.client.post(url + "/submit").status_code == 200
    assert context.client.post(url + "/approve").status_code == 200
    assert context.client.post(url + "/publish").status_code == 200
    item = context.client.get("/api/v1/listings").json()["items"][0]
    assert (item["latitude"], item["longitude"]) == (90, 180)
    detail = context.client.get("/api/v1/listings/" + created.json()["listing_id"])
    assert (detail.json()["latitude"], detail.json()["longitude"]) == (90, 180)
    review = context.client.get(_collection_url("agency-one")).json()["listings"][0]
    assert (review["latitude"], review["longitude"]) == (90, 180)


def test_coordinates_must_be_paired_and_in_range(f04_context: F04Context) -> None:  # noqa: F811
    context = f04_context
    _staff(context)
    for coordinates in (
        {"latitude": 0},
        {"longitude": 0},
        {"latitude": None},
        {"latitude": 91, "longitude": 0},
        {"latitude": -91, "longitude": 0},
        {"latitude": 0, "longitude": -181},
        {"latitude": 0, "longitude": 181},
    ):
        response = context.client.post(_collection_url("agency-one"), json=_payload(**coordinates))
        assert response.status_code == 422, response.text


def test_legacy_edits_preserve_coordinates_and_explicit_null_clears_them(
    f04_context: F04Context,  # noqa: F811
) -> None:
    context = f04_context
    _staff(context)
    created = context.client.post(_collection_url("agency-one"), json=_payload())
    assert created.status_code == 201
    assert created.json()["latitude"] is None and created.json()["longitude"] is None
    url = _url("agency-one", created.json()["listing_id"])
    assert context.client.put(url, json=_payload(latitude=-90, longitude=-180)).status_code == 200
    legacy_edit = context.client.put(url, json=_payload())
    assert (legacy_edit.json()["latitude"], legacy_edit.json()["longitude"]) == (-90, -180)
    cleared = context.client.put(url, json=_payload(latitude=None, longitude=None))
    assert cleared.json()["latitude"] is None and cleared.json()["longitude"] is None
