from __future__ import annotations

import argparse
import calendar
import datetime as dt
import json
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path
import threading

from update_moon_from_nasa import CACHE, dataset_for_year, download_json, download_verified


STATUS = Path(__file__).resolve().parent / "nasa-offline-library-status.json"
PRINT_LOCK = threading.Lock()


def daily_frames(year: int) -> list[int]:
    days = 366 if calendar.isleap(year) else 365
    # 20:00 China Standard Time is 12:00 UTC; NASA frames begin at 1.
    return [(day - 1) * 24 + 13 for day in range(1, days + 1)]


def verify_existing(path: Path) -> bool:
    if not path.exists() or path.stat().st_size < 500_000:
        return False
    try:
        from PIL import Image
        with Image.open(path) as image:
            image.verify()
        return True
    except Exception:
        return False


def library_is_complete(year: int) -> bool:
    paths = [CACHE / f"nasa-moon-{year}-{frame:04d}.tif" for frame in daily_frames(year)]
    return all(path.exists() and path.stat().st_size >= 500_000 for path in paths)


def prepare_year(year: int, workers: int) -> dict:
    dataset = dataset_for_year(year)
    download_json(dataset["info_url"], CACHE / f"mooninfo_{year}.json")
    frames = daily_frames(year)
    missing = []
    for frame in frames:
        path = CACHE / f"nasa-moon-{year}-{frame:04d}.tif"
        if not verify_existing(path):
            missing.append(frame)

    today = dt.datetime.now().astimezone().date()
    today_frame = (today.timetuple().tm_yday - 1) * 24 + 13 if today.year == year else frames[0]
    missing.sort(key=lambda frame: (frame < today_frame, frame))
    completed = len(frames) - len(missing)
    total = len(frames)
    print(f"{year}: {completed}/{total} frames already available; downloading {len(missing)}")

    def fetch(frame: int) -> int:
        destination = CACHE / f"nasa-moon-{year}-{frame:04d}.tif"
        url = f"{dataset['frame_base']}/moon.{frame:04d}.tif"
        download_verified(url, destination)
        return frame

    errors = []
    with ThreadPoolExecutor(max_workers=workers) as pool:
        futures = {pool.submit(fetch, frame): frame for frame in missing}
        for future in as_completed(futures):
            frame = futures[future]
            try:
                future.result()
                completed += 1
                if completed % 10 == 0 or completed == total:
                    with PRINT_LOCK:
                        print(f"{year}: {completed}/{total} complete", flush=True)
            except Exception as exc:
                errors.append({"frame": frame, "error": str(exc)})

    result = {
        "year": year,
        "dataset_id": dataset["dataset_id"],
        "complete": completed == total,
        "available_frames": completed,
        "total_frames": total,
        "errors": errors[:20],
        "checked_at": dt.datetime.now().astimezone().isoformat(),
    }
    return result


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--year", type=int)
    parser.add_argument("--workers", type=int, default=4)
    args = parser.parse_args()

    now = dt.datetime.now().astimezone()
    years = [args.year] if args.year else [now.year]
    if args.year is None and now.month >= 11:
        years.append(now.year + 1)

    results = []
    failed = False
    for year in years:
        try:
            if library_is_complete(year):
                results.append({
                    "year": year,
                    "complete": True,
                    "available_frames": len(daily_frames(year)),
                    "total_frames": len(daily_frames(year)),
                    "checked_at": dt.datetime.now().astimezone().isoformat(),
                })
                continue
            result = prepare_year(year, max(1, min(args.workers, 6)))
            results.append(result)
            failed = failed or not result["complete"]
        except Exception as exc:
            results.append({
                "year": year,
                "complete": False,
                "error": str(exc),
                "checked_at": dt.datetime.now().astimezone().isoformat(),
            })
            # A future year's dataset may not be published yet; the daily task retries.
            failed = failed or year <= now.year

    STATUS.write_text(json.dumps({"years": results}, ensure_ascii=False, indent=2), encoding="utf-8")
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
