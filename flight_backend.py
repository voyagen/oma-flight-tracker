#!/usr/bin/env python3
"""Public Flightradar24 observations, isolated by origin-local departure day."""
import argparse
import datetime as dt
import json
import math
import os
from pathlib import Path
import re
import sys
import tempfile
from urllib.error import HTTPError, URLError
from urllib.parse import urlencode
from urllib.request import Request, urlopen
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError


TIMEOUT = 10


def obj(value):
    return value if isinstance(value, dict) else {}


def number(value):
    if isinstance(value, bool) or value is None:
        return None
    try:
        result = float(value)
        return result if math.isfinite(result) else None
    except (TypeError, ValueError):
        return None


def timestamp(value):
    value = number(value)
    return int(value) if value is not None and value > 0 else None


def request_json(url):
    request = Request(url, headers={
        "User-Agent": "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 Chrome/131.0.0.0 Safari/537.36",
        "Accept": "application/json",
        "Referer": "https://www.flightradar24.com/",
    })
    with urlopen(request, timeout=TIMEOUT) as response:
        return json.load(response)


def airport(value):
    value = obj(value)
    position = obj(value.get("position"))
    return {
        "code": obj(value.get("code")).get("iata"),
        "city": obj(position.get("region")).get("city"),
        "lat": number(position.get("latitude")),
        "lon": number(position.get("longitude")),
        "tz": obj(value.get("timezone")).get("name"),
    }


def departure_day(departure, zone):
    departure = timestamp(departure)
    if departure is None or not zone:
        return None
    try:
        return dt.datetime.fromtimestamp(departure, ZoneInfo(zone)).date().isoformat()
    except (ZoneInfoNotFoundError, ValueError, OverflowError, TypeError):
        return None


def matches_detail(detail, flight, day):
    identification = obj(detail.get("identification"))
    actual_flight = obj(identification.get("number")).get("default")
    timing = obj(detail.get("time"))
    departure = (obj(timing.get("real")).get("departure")
                 or obj(timing.get("scheduled")).get("departure"))
    origin = obj(obj(detail.get("airport")).get("origin"))
    zone = obj(origin.get("timezone")).get("name")
    return (str(actual_flight or "").upper().replace(" ", "") == flight
            and departure_day(departure, zone) == day)


def point(value):
    value = obj(value)
    lat = number(value.get("lat"))
    lon = number(value.get("lon", value.get("lng")))
    stamp = timestamp(value.get("timestamp", value.get("ts")))
    if lat is None or lon is None or stamp is None or not (-90 <= lat <= 90 and -180 <= lon <= 180):
        return None
    return {"lat": lat, "lon": lon, "timestamp": stamp,
            "heading": number(value.get("heading", value.get("hd"))),
            "altitude": number(value.get("altitude", value.get("alt"))),
            "speed": number(value.get("speed", value.get("spd")))}


def merge_trail(*trails):
    # Provider trails run backwards; a timestamp is one observation, not a frame.
    observations = {}
    for trail in trails:
        for value in trail or []:
            observation = point(value)
            if observation is not None:
                observations[observation["timestamp"]] = observation
    return [observations[key] for key in sorted(observations)]


def local_times(result):
    for endpoint, zone_key, time_key in (("origin", "departureZone", "departure"),
                                         ("destination", "arrivalZone", "arrival")):
        zone = result.get(zone_key)
        try:
            tz = ZoneInfo(zone) if zone else None
        except (ZoneInfoNotFoundError, ValueError, TypeError):
            tz = None
        result[endpoint] = {key: value for key, value in obj(result.get(endpoint)).items()
                            if key in ("code", "city", "lat", "lon", "tz")}
        for key in (time_key, "scheduled" + time_key.title()):
            stamp = timestamp(result.get(key))
            label = None
            if stamp is not None and tz is not None:
                try:
                    local = dt.datetime.fromtimestamp(stamp, tz)
                    label = local.strftime("%H:%M")
                    if local.date().isoformat() != result.get("date"):
                        label += local.strftime(" · %b %d")
                except (OverflowError, ValueError):
                    pass
            result[key + "Label"] = label
    return result


def normalize(detail, flight, day):
    timing = obj(detail.get("time"))
    scheduled, real, estimated, other = (obj(timing.get(key)) for key in
                                          ("scheduled", "real", "estimated", "other"))
    airports = obj(detail.get("airport"))
    origin, destination = airport(airports.get("origin")), airport(airports.get("destination"))
    aircraft = obj(detail.get("aircraft"))
    trail = merge_trail(detail.get("trail"))
    status = obj(detail.get("status"))
    result = {
        "flight": flight, "date": day,
        "flightId": obj(detail.get("identification")).get("id"),
        "status": status.get("text") or obj(obj(status.get("generic")).get("status")).get("text"),
        "airline": obj(detail.get("airline")).get("name"),
        "aircraft": obj(aircraft.get("model")).get("text") or obj(aircraft.get("model")).get("code"),
        "registration": aircraft.get("registration"),
        "origin": origin, "destination": destination,
        "departure": timestamp(real.get("departure") or estimated.get("departure") or scheduled.get("departure")),
        "arrival": timestamp(real.get("arrival") or estimated.get("arrival") or other.get("eta") or scheduled.get("arrival")),
        "scheduledDeparture": timestamp(scheduled.get("departure")),
        "scheduledArrival": timestamp(scheduled.get("arrival")),
        "departureZone": origin["tz"], "arrivalZone": destination["tz"],
        "arrivalGate": obj(obj(airports.get("destination")).get("info")).get("gate"),
        "position": trail[-1] if trail else None, "trail": trail,
        # ETA belongs to this metadata observation, never to a newer feed fix.
        "metadataUpdated": timestamp(other.get("updated")),
        "error": None, "warning": None,
    }
    return local_times(result)


def empty_result(flight, day):
    result = normalize({}, flight, day)
    result["status"] = "No data"
    return result


def fetch_detail(flight_id):
    payload = request_json("https://data-live.flightradar24.com/clickhandler/?" + urlencode({"flight": flight_id}))
    if not isinstance(payload, dict) or not payload.get("identification"):
        raise ValueError("provider returned no flight detail")
    return payload


def fetch_history(flight):
    payload = request_json("https://api.flightradar24.com/common/v1/flight/list.json?" + urlencode({
        "query": flight, "fetchBy": "flight", "page": 1, "limit": 25,
    }))
    data = obj(obj(obj(payload).get("result")).get("response")).get("data")
    if not isinstance(data, list):
        raise ValueError("provider returned no flight history")
    return [item for item in data if isinstance(item, dict)]


def error_text(label, exc):
    if isinstance(exc, HTTPError):
        return f"{label}: HTTP {exc.code}"
    return f"{label}: {exc}"


def load_json(path):
    try:
        with path.open(encoding="utf-8") as stream:
            return obj(json.load(stream))
    except (OSError, ValueError):
        return {}


def save_cache(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(mode="w", encoding="utf-8", dir=path.parent,
                                         prefix=path.name + ".", delete=False) as stream:
            temporary = stream.name
            json.dump(data, stream, separators=(",", ":"), allow_nan=False)
        os.replace(temporary, path)
    finally:
        if temporary and os.path.exists(temporary):
            os.unlink(temporary)


def fetch(flight, day):
    cache_root = Path(os.environ.get("XDG_CACHE_HOME") or Path.home() / ".cache") / "oma-flight-tracker"
    cache_path = cache_root / f"{flight}-{day}.json"
    cached = load_json(cache_path)
    if (cached.get("flight") != flight or cached.get("date") != day
            or departure_day(cached.get("departure"), cached.get("departureZone")) != day):
        cached = {}
    result = empty_result(flight, day)
    result.update((key, cached[key]) for key in result if key in cached)
    warnings = []
    if not result.get("flightId"):
        try:
            matches = [item for item in fetch_history(flight) if matches_detail(item, flight, day)]
            if matches:
                result = normalize(matches[0], flight, day)
        except (OSError, ValueError, URLError) as exc:
            warnings.append(error_text("History unavailable", exc))
    flight_id = result.get("flightId")
    if flight_id:
        try:
            detail = fetch_detail(flight_id)
            if not matches_detail(detail, flight, day) or str(obj(detail.get("identification")).get("id")) != str(flight_id):
                raise ValueError("provider detail does not match selected flight and departure date")
            refreshed = normalize(detail, flight, day)
            # Preserve metadata fields when a provider response omits optional values.
            for key, value in refreshed.items():
                if value is not None and key not in ("trail", "position", "error", "warning"):
                    result[key] = value
            result["trail"] = merge_trail(result.get("trail"), refreshed["trail"])
            result["position"] = result["trail"][-1] if result["trail"] else None
        except (OSError, ValueError, URLError) as exc:
            warnings.append(error_text("Detail unavailable", exc))
    # A live feed alone cannot establish a departure day. Never guess from its
    # position timestamp: overnight and historical flights would be mislabeled.
    try:
        feed = request_json("https://data-cloud.flightradar24.com/zones/fcgi/feed.js?" + urlencode({"flight": flight}))
        if not isinstance(feed, dict):
            raise ValueError("provider returned an invalid live feed")
        row = feed.get(str(flight_id)) if flight_id else None
        if isinstance(row, list) and len(row) > 16:
            feed_flight = str(row[13] or "").upper().replace(" ", "")
            if feed_flight != flight:
                raise ValueError("live feed flight number does not match selected flight")
            observation = point({"lat": row[1], "lon": row[2], "heading": row[3],
                                 "altitude": row[4], "speed": row[5], "timestamp": row[10]})
            if observation is None:
                raise ValueError("live feed contains no valid position")
            result["trail"] = merge_trail(result.get("trail"), [observation])
            result["position"] = result["trail"][-1]
            result["registration"] = row[9] or result.get("registration")
            result["aircraft"] = result.get("aircraft") or row[8] or None
        elif not flight_id:
            warnings.append("Live feed not attached: selected departure date could not be verified")
        else:
            warnings.append("No live feed position for selected flight ID")
    except (OSError, ValueError, URLError) as exc:
        warnings.append(error_text("Live feed unavailable", exc))
    local_times(result)
    metadata_stamp = timestamp(result.get("metadataUpdated"))
    position_stamp = timestamp(obj(result.get("position")).get("timestamp"))
    if flight_id and metadata_stamp and (warnings or (position_stamp and position_stamp > metadata_stamp)):
        observed = dt.datetime.fromtimestamp(metadata_stamp, dt.timezone.utc).strftime("%Y-%m-%d %H:%M:%S UTC")
        warnings.append(f"ETA/airport details cached; metadata observed {observed}")
    elif flight_id and not metadata_stamp:
        warnings.append("ETA/airport metadata observation time unavailable")
    result["warning"] = "; ".join(warnings) or None
    result["error"] = None if flight_id else f"No verified data for {flight} departing {day}"
    if flight_id:
        try:
            save_cache(cache_path, result)
        except OSError as exc:
            result["warning"] = "; ".join(filter(None, [result["warning"], error_text("Cache unavailable", exc)]))
    return result


def flight_argument(value):
    value = value.strip().upper()
    if not re.fullmatch(r"(?:[A-Z]{2,3}|[A-Z][0-9]|[0-9][A-Z])[0-9]{1,4}[A-Z]?", value):
        raise argparse.ArgumentTypeError("flight must be an airline code and flight number, e.g. AA1")
    return value


def date_argument(value):
    try:
        if not re.fullmatch(r"[0-9]{4}-[0-9]{2}-[0-9]{2}", value):
            raise ValueError()
        return dt.date.fromisoformat(value).isoformat()
    except ValueError:
        raise argparse.ArgumentTypeError("date must be a valid YYYY-MM-DD") from None


def _behavior_check():
    """Offline regression check: import this function; no network or cache writes."""
    sample = {"identification": {"number": {"default": "AA1"}},
              "airport": {"origin": {"timezone": {"name": "America/New_York"}}},
              "time": {"real": {"departure": 1791288000}}}
    assert matches_detail(sample, "AA1", "2026-10-06")
    assert not matches_detail(sample, "AA1", "2026-10-05")
    assert not matches_detail(sample, "AA2", "2026-10-06")
    earlier = {"lat": 1, "lon": 2, "timestamp": 100}
    later = {"lat": 2, "lon": 3, "timestamp": 200}
    trail = merge_trail([later, earlier], [earlier, later])
    assert [item["timestamp"] for item in trail] == [100, 200]
    assert merge_trail(trail, [earlier]) == trail


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--flight", required=True, type=flight_argument)
    parser.add_argument("--date", required=True, type=date_argument)
    args = parser.parse_args()
    try:
        result = fetch(args.flight, args.date)
    except Exception as exc:
        result = empty_result(args.flight, args.date)
        result["error"] = f"Flight data unavailable: {exc}"
    json.dump(result, sys.stdout, separators=(",", ":"), allow_nan=False)
    sys.stdout.write("\n")


if __name__ == "__main__":
    main()
