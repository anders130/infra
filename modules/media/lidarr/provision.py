import json
import os
import sys
import time

import requests

FORCE_SAVE = {"forceSave": "true"}


class Api:
    def __init__(self, session, base_url):
        self.session = session
        self.base_url = base_url.rstrip("/")
        self.changes = 0

    def call(self, method, path, **kwargs):
        response = self.session.request(method, f"{self.base_url}/api/v1/{path}", timeout=30, **kwargs)
        if not response.ok:
            raise requests.HTTPError(f"{method} {path}: HTTP {response.status_code}: {response.text}", response=response)
        return response.json()

    def get(self, path):
        return self.call("GET", path)

    def write(self, method, path, body, description, params=None):
        result = self.call(method, path, json=body, params=params)
        self.changes += 1
        print(description, flush=True)
        return result


def by_name(items, name):
    return next((i for i in items if i["name"] == name), None)


def set_fields(fields, values):
    known = {f["name"] for f in fields}
    updated = [{**f, "value": values[f["name"]]} if f["name"] in values else f for f in fields]
    return updated + [{"name": n, "value": v} for n, v in values.items() if n not in known]


def sync_config(api, name, overrides):
    current = api.get(f"config/{name}")
    merged = {**current, **overrides}
    if merged != current:
        api.write("PUT", f"config/{name}/{current['id']}", merged, f"updated config/{name}")


def sync_quality_profile(api, spec):
    items = api.get("qualityprofile/schema")["items"]

    def mark(item):
        label = item.get("name") or item["quality"]["name"]
        nested = [mark(i) for i in item.get("items", [])]
        return {**item, "items": nested, "allowed": label in spec["allowed"]} if nested or "quality" in item else item

    marked = [mark(i) for i in items]
    first = next((i for i in marked if i["allowed"]), None)
    if first is None:
        raise SystemExit(f"quality profile '{spec['name']}' allows none of the schema's qualities: {spec['allowed']}")
    cutoff = first["id"] if "id" in first else first["quality"]["id"]
    desired = {
        "name": spec["name"],
        "upgradeAllowed": False,
        "cutoff": cutoff,
        "items": marked,
    }
    existing = by_name(api.get("qualityprofile"), spec["name"])
    if existing is None:
        profile = {**api.get("qualityprofile/schema"), **desired}
        return api.write("POST", "qualityprofile", profile, f"created quality profile {spec['name']}")["id"]
    merged = {**existing, **desired}
    if merged != existing:
        api.write("PUT", f"qualityprofile/{existing['id']}", merged, f"updated quality profile {spec['name']}")
    return existing["id"]


METADATA_TYPES = ["primaryAlbumTypes", "secondaryAlbumTypes", "releaseStatuses"]


def sync_metadata_profile(api, name):
    def open_up(profile):
        return {**profile, **{key: [{**entry, "allowed": True} for entry in profile[key]] for key in METADATA_TYPES}}

    existing = by_name(api.get("metadataprofile"), name)
    if existing is None:
        profile = open_up({**api.get("metadataprofile/schema"), "name": name})
        return api.write("POST", "metadataprofile", profile, f"created metadata profile {name}")["id"]
    merged = open_up(existing)
    if merged != existing:
        api.write("PUT", f"metadataprofile/{existing['id']}", merged, f"updated metadata profile {name}")
    return existing["id"]


def sync_root_folder(api, spec, quality_id, metadata_id):
    wanted = spec["path"].rstrip("/")
    desired = {
        "name": spec["name"],
        "defaultQualityProfileId": quality_id,
        "defaultMetadataProfileId": metadata_id,
        "defaultMonitorOption": "none",
        "defaultNewItemMonitorOption": "none",
    }
    existing = next((r for r in api.get("rootfolder") if r["path"].rstrip("/") == wanted), None)
    if existing is None:
        body = {**desired, "path": spec["path"], "defaultTags": []}
        api.write("POST", "rootfolder", body, f"created root folder {spec['path']}")
        return
    merged = {**existing, **desired}
    if merged != existing:
        api.write("PUT", f"rootfolder/{existing['id']}", merged, f"updated root folder {spec['path']}")


def sync_provider(api, endpoint, spec):
    schema = next((s for s in api.get(f"{endpoint}/schema") if s["implementation"] == spec["implementation"]), None)
    if schema is None:
        raise SystemExit(f"Lidarr has no {endpoint} implementation '{spec['implementation']}'")
    existing = by_name(api.get(endpoint), spec["name"])
    base = existing or {**schema, "name": spec["name"]}
    merged = {**base, **spec.get("options", {}), "fields": set_fields(base["fields"], spec["fields"])}
    if existing is None:
        api.write("POST", endpoint, merged, f"created {endpoint} {spec['name']}", FORCE_SAVE)
    elif merged != existing:
        api.write("PUT", f"{endpoint}/{existing['id']}", merged, f"updated {endpoint} {spec['name']}", FORCE_SAVE)


def provision(session, base_url, desired):
    api = Api(session, base_url)
    quality_id = sync_quality_profile(api, desired["qualityProfile"])
    metadata_id = sync_metadata_profile(api, desired["metadataProfile"])
    sync_root_folder(api, desired["rootFolder"], quality_id, metadata_id)
    sync_config(api, "naming", {**desired["naming"], "renameTracks": True})
    sync_config(api, "mediamanagement", desired["mediaManagement"])
    sync_config(
        api,
        "metadataProvider",
        {**desired["metadataProvider"], "writeAudioTags": "newFiles", "scrubAudioTags": False},
    )
    if os.path.exists(desired["cookiesPath"]):
        for spec in desired["indexers"]:
            sync_provider(api, "indexer", spec)
        for spec in desired["downloadClients"]:
            sync_provider(api, "downloadclient", spec)
    else:
        print(f"skipping indexer and download client: no cookies file at {desired['cookiesPath']}", flush=True)
    print(f"{api.changes} change(s)", flush=True)
    return api.changes


def wait_for_ping(base_url, attempts=60):
    for _ in range(attempts):
        try:
            if requests.get(f"{base_url}/ping", timeout=5).ok:
                return
        except requests.RequestException:
            pass
        time.sleep(2)
    raise SystemExit("Lidarr did not become ready")


def main():
    base_url = os.environ["LIDARR_URL"]
    with open(os.environ["LIDARR_API_KEY_FILE"]) as f:
        api_key = f.read().strip()
    with open(sys.argv[1]) as f:
        desired = json.load(f)
    wait_for_ping(base_url)
    session = requests.Session()
    session.headers["X-Api-Key"] = api_key
    provision(session, base_url, desired)


if __name__ == "__main__":
    main()
