from __future__ import annotations

import datetime as dt
import json
import math
from pathlib import Path
import subprocess
import sys
import time
import urllib.parse
import urllib.request

import numpy as np
from PIL import Image, ImageFilter


ROOT = Path(__file__).resolve().parent
CACHE = ROOT / "cache"
CACHE.mkdir(exist_ok=True)
PORTRAIT_OUTPUT = ROOT / "moon-phase-henan-1600x2560.png"
LANDSCAPE_OUTPUT = ROOT / "moon-phase-henan-2560x1600.png"
STATUS = ROOT / "nasa-moon-status.json"
APPLY_SCRIPT = ROOT / "apply_adaptive_wallpaper.ps1"

NASA_SEARCH_URL = "https://svs.gsfc.nasa.gov/api/search/"
KNOWN_DATASETS = {2026: 5587}
UTC_OFFSET = dt.timedelta(hours=8)
ZHENGZHOU_LATITUDE = 34.7466
ZHENGZHOU_LONGITUDE = 113.6254
ORIENTATION_VERSION = "zhengzhou-zenith-up-current-hour-adaptive-clock-v5"


def dataset_for_year(year: int) -> dict:
    config_path = CACHE / f"nasa-dataset-{year}.json"
    try:
        cached = json.loads(config_path.read_text(encoding="utf-8"))
        if cached.get("schema_version") == 2:
            return cached
    except (FileNotFoundError, json.JSONDecodeError):
        pass

    dataset_id = KNOWN_DATASETS.get(year)
    if dataset_id is None:
        query = urllib.parse.urlencode({"search": f"Moon Phase and Libration, {year}"})
        request = urllib.request.Request(
            f"{NASA_SEARCH_URL}?{query}",
            headers={"User-Agent": "Mozilla/5.0 MoonWallpaper/1.0"},
        )
        with urllib.request.urlopen(request, timeout=60) as response:
            results = json.load(response)["results"]
        exact_title = f"Moon Phase and Libration, {year}"
        matches = [item for item in results if item.get("title") == exact_title]
        if not matches:
            raise RuntimeError(f"NASA has not published its north-up Moon dataset for {year} yet")
        dataset_id = int(matches[0]["id"])

    major_group = (dataset_id // 10000) * 10000
    group = (dataset_id // 100) * 100
    root = (
        f"https://svs.gsfc.nasa.gov/vis/a{major_group:06d}/"
        f"a{group:06d}/a{dataset_id:06d}"
    )
    config = {
        "schema_version": 2,
        "year": year,
        "dataset_id": dataset_id,
        "frame_base": f"{root}/frames/3840x2160_16x9_30p/plain",
        "info_url": f"{root}/mooninfo_{year}.json",
    }
    config_path.write_text(json.dumps(config, indent=2), encoding="utf-8")
    return config


def target_for_today() -> tuple[dt.date, int, str, dict]:
    local_today = (dt.datetime.now(dt.timezone.utc) + UTC_OFFSET).date()
    # Fixed 20:00 China Standard Time view, equivalent to 12:00 UTC.
    utc_hour = 12
    frame = (local_today.timetuple().tm_yday - 1) * 24 + utc_hour + 1
    dataset = dataset_for_year(local_today.year)
    url = f"{dataset['frame_base']}/moon.{frame:04d}.tif"
    return local_today, frame, url, dataset


def read_status() -> dict:
    try:
        return json.loads(STATUS.read_text(encoding="utf-8"))
    except (FileNotFoundError, json.JSONDecodeError):
        return {}


def download_verified(url: str, destination: Path) -> None:
    partial = destination.with_suffix(destination.suffix + ".download")
    headers = {"User-Agent": "Mozilla/5.0 MoonWallpaper/1.0"}
    last_error: Exception | None = None
    for attempt in range(3):
        try:
            request = urllib.request.Request(url, headers=headers)
            with urllib.request.urlopen(request, timeout=45) as response:
                data = response.read()
            if len(data) < 500_000:
                raise RuntimeError(f"Downloaded frame is unexpectedly small: {len(data)} bytes")
            partial.write_bytes(data)
            with Image.open(partial) as image:
                image.verify()
            partial.replace(destination)
            return
        except Exception as exc:
            last_error = exc
            partial.unlink(missing_ok=True)
            if attempt < 2:
                time.sleep(15 * (attempt + 1))
    raise RuntimeError(f"NASA frame download failed after retries: {last_error}")


def download_json(url: str, destination: Path) -> list[dict]:
    if not destination.exists():
        partial = destination.with_suffix(destination.suffix + ".download")
        request = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0 MoonWallpaper/1.0"})
        with urllib.request.urlopen(request, timeout=60) as response:
            data = response.read()
        parsed = json.loads(data)
        if len(parsed) < 8000:
            raise RuntimeError("NASA Moon information file is incomplete")
        partial.write_bytes(data)
        partial.replace(destination)
    return json.loads(destination.read_text(encoding="utf-8"))


def local_sky_rotation(info: dict, when_utc: dt.datetime) -> tuple[float, float]:
    """Return PIL rotation and topocentric altitude for a naked-eye, zenith-up view."""
    # NASA supplies geocentric J2000 coordinates and distance. Subtract the
    # observer's WGS84 position, then measure the zenith's position angle in
    # the Moon's tangent plane. Positive position angle runs north through east.
    jd = when_utc.timestamp() / 86400.0 + 2440587.5
    centuries = (jd - 2451545.0) / 36525.0
    gmst = (
        280.46061837
        + 360.98564736629 * (jd - 2451545.0)
        + 0.000387933 * centuries * centuries
        - centuries * centuries * centuries / 38710000.0
    ) % 360.0

    latitude = math.radians(ZHENGZHOU_LATITUDE)
    local_sidereal = math.radians((gmst + ZHENGZHOU_LONGITUDE) % 360.0)
    eccentricity_sq = 0.0818191908426**2
    prime_vertical = 6378.137 / math.sqrt(1.0 - eccentricity_sq * math.sin(latitude) ** 2)
    observer = (
        prime_vertical * math.cos(latitude) * math.cos(local_sidereal),
        prime_vertical * math.cos(latitude) * math.sin(local_sidereal),
        prime_vertical * (1.0 - eccentricity_sq) * math.sin(latitude),
    )

    right_ascension = math.radians(float(info["j2000"]["ra"]) * 15.0)
    declination = math.radians(float(info["j2000"]["dec"]))
    distance = float(info["distance"])
    moon = (
        distance * math.cos(declination) * math.cos(right_ascension),
        distance * math.cos(declination) * math.sin(right_ascension),
        distance * math.sin(declination),
    )
    topocentric = tuple(moon[i] - observer[i] for i in range(3))
    topocentric_length = math.sqrt(sum(value * value for value in topocentric))
    direction = tuple(value / topocentric_length for value in topocentric)
    topo_ra = math.atan2(direction[1], direction[0])
    topo_dec = math.asin(direction[2])

    east = (-math.sin(topo_ra), math.cos(topo_ra), 0.0)
    north = (
        -math.sin(topo_dec) * math.cos(topo_ra),
        -math.sin(topo_dec) * math.sin(topo_ra),
        math.cos(topo_dec),
    )
    observer_length = math.sqrt(sum(value * value for value in observer))
    zenith = tuple(value / observer_length for value in observer)
    zenith_dot_moon = sum(zenith[i] * direction[i] for i in range(3))
    projected_zenith = tuple(zenith[i] - zenith_dot_moon * direction[i] for i in range(3))
    position_angle = math.degrees(
        math.atan2(
            sum(projected_zenith[i] * east[i] for i in range(3)),
            sum(projected_zenith[i] * north[i] for i in range(3)),
        )
    )
    altitude = math.degrees(math.asin(zenith_dot_moon))

    # NASA's unmagnified north-up sky view has celestial east to the left.
    # PIL uses positive angles counter-clockwise, so zenith-up is -PA.
    return -position_angle, altitude


def apply_naked_eye_shadow(moon: Image.Image) -> Image.Image:
    """Compress NASA's display-brightened night side toward a naked-eye view."""
    pixels = np.asarray(moon.convert("RGBA"), dtype=np.float32).copy()
    rgb = pixels[..., :3]
    alpha = pixels[..., 3]
    luminance = (
        0.2126 * rgb[..., 0]
        + 0.7152 * rgb[..., 1]
        + 0.0722 * rgb[..., 2]
    ) / 255.0

    # Preserve directly sunlit terrain, while reducing the rendered night side
    # to a very faint earthshine. Smooth interpolation avoids a second artificial
    # edge beside the real terminator.
    transition = np.clip((luminance - 0.04) / (0.22 - 0.04), 0.0, 1.0)
    transition = transition * transition * (3.0 - 2.0 * transition)
    shadow_factor = 0.16 + 0.84 * transition
    shadow_factor[alpha <= 3] = 1.0
    pixels[..., :3] = np.clip(rgb * shadow_factor[..., None], 0, 255)
    return Image.fromarray(pixels.astype(np.uint8), "RGBA")


def prepare_moon(
    frame_path: Path,
    rotation_degrees: float,
    diameter: int,
) -> Image.Image:
    source = Image.open(frame_path).convert("RGBA")
    arr = np.asarray(source)
    alpha = arr[..., 3]
    if alpha.max() > 0:
        mask = alpha > 3
    else:
        mask = np.max(arr[..., :3], axis=2) > 3
    ys, xs = np.where(mask)
    if len(xs) == 0:
        raise RuntimeError("NASA frame does not contain a visible Moon")

    margin = 8
    box = (
        max(0, int(xs.min()) - margin),
        max(0, int(ys.min()) - margin),
        min(source.width, int(xs.max()) + margin + 1),
        min(source.height, int(ys.max()) + margin + 1),
    )
    moon = source.crop(box)
    scale = min(diameter / moon.width, diameter / moon.height)
    new_size = (max(1, round(moon.width * scale)), max(1, round(moon.height * scale)))
    moon = moon.resize(new_size, Image.Resampling.LANCZOS)
    moon = moon.rotate(rotation_degrees, resample=Image.Resampling.BICUBIC, expand=True)
    moon = apply_naked_eye_shadow(moon)
    moon = moon.filter(ImageFilter.UnsharpMask(radius=0.40, percent=24, threshold=2))
    return moon


def render_variant(
    frame_path: Path,
    rotation_degrees: float,
    output: Path,
    canvas_size: tuple[int, int],
    diameter: int,
    center: tuple[int, int],
) -> None:
    moon = prepare_moon(frame_path, rotation_degrees, diameter)
    canvas = Image.new("RGBA", canvas_size, (0, 0, 0, 255))
    x = center[0] - moon.width // 2
    y = center[1] - moon.height // 2
    canvas.alpha_composite(moon, (x, y))
    canvas.convert("RGB").save(output, optimize=True)


def compose(frame_path: Path, rotation_degrees: float) -> None:
    # The portrait layout preserves the original secondary-monitor composition.
    render_variant(
        frame_path,
        rotation_degrees,
        PORTRAIT_OUTPUT,
        (1600, 2560),
        1180,
        (800, 1720),
    )
    # The laptop layout is native 2560x1600. The Moon is centered beneath the
    # live clock widget, with enough separation to keep both elements legible.
    render_variant(
        frame_path,
        rotation_degrees,
        LANDSCAPE_OUTPUT,
        (2560, 1600),
        980,
        (1280, 800),
    )


def apply_wallpaper() -> None:
    subprocess.run(
        [
            "powershell.exe", "-NoProfile", "-ExecutionPolicy", "Bypass",
            "-WindowStyle", "Hidden",
            "-File", str(APPLY_SCRIPT),
            "-PortraitWallpaper", str(PORTRAIT_OUTPUT),
            "-LandscapeWallpaper", str(LANDSCAPE_OUTPUT),
        ],
        check=True,
        creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0),
    )


def main() -> int:
    local_date, frame, url, dataset = target_for_today()
    now_utc = dt.datetime.now(dt.timezone.utc)
    observation_slot = now_utc.strftime("%Y-%m-%dT%H:00Z")
    status = read_status()
    if (
        status.get("local_date") == local_date.isoformat()
        and status.get("orientation") == ORIENTATION_VERSION
        and status.get("observation_slot_utc") == observation_slot
        and PORTRAIT_OUTPUT.exists()
        and LANDSCAPE_OUTPUT.exists()
    ):
        apply_wallpaper()
        print(f"Already current: {local_date} frame {frame}")
        return 0

    frame_path = CACHE / f"nasa-moon-{local_date.year}-{frame:04d}.tif"
    try:
        if not frame_path.exists():
            download_verified(url, frame_path)
        info_path = CACHE / f"mooninfo_{local_date.year}.json"
        moon_info = download_json(dataset["info_url"], info_path)
        observation_frame = (
            (now_utc.timetuple().tm_yday - 1) * 24 + now_utc.hour + 1
            if now_utc.year == local_date.year
            else frame
        )
        observation_info = moon_info[observation_frame - 1]
        observation_utc = dt.datetime.strptime(
            observation_info["time"], "%d %b %Y %H:%M UT"
        ).replace(tzinfo=dt.timezone.utc)
        rotation_degrees, altitude = local_sky_rotation(observation_info, observation_utc)
        compose(frame_path, rotation_degrees)
        apply_wallpaper()
        STATUS.write_text(
            json.dumps(
                {
                    "local_date": local_date.isoformat(),
                    "frame": frame,
                    "source_url": url,
                    "orientation": ORIENTATION_VERSION,
                    "observation_slot_utc": observation_slot,
                    "reference_location": {
                        "name": "Zhengzhou, Henan",
                        "latitude": ZHENGZHOU_LATITUDE,
                        "longitude": ZHENGZHOU_LONGITUDE,
                    },
                    "source_image_time": "20:00 Asia/Shanghai",
                    "local_observation_time": (observation_utc + UTC_OFFSET).strftime(
                        "%Y-%m-%d %H:00 Asia/Shanghai"
                    ),
                    "image_rotation_degrees": round(rotation_degrees, 3),
                    "moon_altitude_degrees": round(altitude, 3),
                    "updated_at": dt.datetime.now().astimezone().isoformat(),
                },
                ensure_ascii=False,
                indent=2,
            ),
            encoding="utf-8",
        )
        print(
            f"Updated from NASA: {local_date} frame {frame}; "
            f"Zhengzhou current-hour rotation {rotation_degrees:.3f} deg, "
            f"altitude {altitude:.3f} deg"
        )
        return 0
    except Exception as exc:
        # Preserve and re-apply the last valid wallpaper. A later scheduled run retries.
        if PORTRAIT_OUTPUT.exists() and LANDSCAPE_OUTPUT.exists():
            apply_wallpaper()
        print(str(exc), file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
