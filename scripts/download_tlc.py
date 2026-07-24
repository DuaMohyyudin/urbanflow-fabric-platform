"""
Download raw NYC TLC source data into data/raw/.

Sources
-------
Yellow taxi trip records : monthly Parquet, one row per completed trip
Taxi zone lookup         : CSV, one row per TLC zone (dimension source)

This script is idempotent: files already on disk are skipped, so it is
safe to re-run when adding months. Nothing here is written to Git —
data/ is gitignored.
"""

from pathlib import Path

import requests
from tqdm import tqdm

# --- Configuration -------------------------------------------------------

TRIP_BASE = "https://d37ci6vzurychx.cloudfront.net/trip-data"
ZONE_URL = "https://d37ci6vzurychx.cloudfront.net/misc/taxi_zone_lookup.csv"

# Start with one quarter. Widen once the schema and quality rules are known.
MONTHS = ["2024-01", "2024-02", "2024-03"]

OUT = Path("data/raw")


# --- Helpers -------------------------------------------------------------

def download_stream(url: str, dest: Path) -> None:
    """Download a URL to dest, streaming in chunks with a progress bar.

    Streaming avoids holding the whole file in memory — this matters once
    the download list grows beyond a few months.
    """
    if dest.exists():
        print(f"skip   {dest.name}")
        return

    response = requests.get(url, stream=True, timeout=60)
    response.raise_for_status()  # turn a 404/500 into a loud failure

    total = int(response.headers.get("content-length", 0))

    with open(dest, "wb") as file, tqdm(
        total=total, unit="B", unit_scale=True, desc=dest.name
    ) as bar:
        for chunk in response.iter_content(chunk_size=8192):
            file.write(chunk)
            bar.update(len(chunk))


def download_trips(month: str) -> None:
    """Download one month of yellow taxi trip records."""
    filename = f"yellow_tripdata_{month}.parquet"
    download_stream(f"{TRIP_BASE}/{filename}", OUT / filename)


def download_zone_lookup() -> None:
    """Download the taxi zone lookup table (source for dim_zone)."""
    download_stream(ZONE_URL, OUT / "taxi_zone_lookup.csv")


# --- Entry point ---------------------------------------------------------

def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)

    for month in MONTHS:
        download_trips(month)

    download_zone_lookup()

    print(f"\ndone. files in {OUT.resolve()}")


if __name__ == "__main__":
    main()