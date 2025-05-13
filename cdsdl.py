#!/usr/bin/env python

import argparse
import cdsapi
from datetime import datetime
import os
import pathlib
import sys

# ------------------------------------------------------------------------------
# CLI
# ------------------------------------------------------------------------------

parser = argparse.ArgumentParser(
    prog='cdsdl',
    description='download Climate Data Store (CDS) datasets',
)

parser.add_argument(
    'dataset',
    help='dataset, e.g.: reanalysis-era5-land',
)

parser.add_argument(
    'variable',
    help='variable, e.g.: total_precipitation',
)

parser.add_argument(
    'output_directory',
    help='output directory, e.g.: /data/db/cds',
    type=pathlib.Path,
)

parser.add_argument(
    '--start',
    help='start year (inclusive), e.g.: 1950',
    type=int,
    required=True,
)

parser.add_argument(
    '--end',
    help='end year (exclusive), e.g.: 2025',
    type=int,
    required=True,
)

options = parser.parse_args()

dataset = options.dataset
variable = options.variable

output_directory = os.path.join(options.output_directory, variable)

start_year = options.start
end_year = options.end

if not start_year < end_year:
    sys.exit('start year must be less than end year')

# ------------------------------------------------------------------------------
# app
# ------------------------------------------------------------------------------

os.makedirs(output_directory, exist_ok=True)

client = cdsapi.Client()

for year in range(start_year, end_year):
    for month in range(1, 13):
        year = f"{year}"
        month = f"{month:02d}"

        target = os.path.join(
            output_directory,
            f"{year}_{month}.nc"
        )

        now = datetime.now()
        if f"{year}_{month}" == f"{now.year}_{now.month:02d}":
            print(f"--> skipping: {target}: current month not yet complete")
            break

        if os.path.isfile(target):
            print(f"--> skipping: {target}: already exists")
            continue
        else:
            print(f"--> downloading {target} ...")

        request = {
            "variable": [variable],
            "year": year,
            "month": month,
            "day": [
                "01", "02", "03",
                "04", "05", "06",
                "07", "08", "09",
                "10", "11", "12",
                "13", "14", "15",
                "16", "17", "18",
                "19", "20", "21",
                "22", "23", "24",
                "25", "26", "27",
                "28", "29", "30",
                "31"
            ],
            "time": [
                "00:00", "01:00", "02:00",
                "03:00", "04:00", "05:00",
                "06:00", "07:00", "08:00",
                "09:00", "10:00", "11:00",
                "12:00", "13:00", "14:00",
                "15:00", "16:00", "17:00",
                "18:00", "19:00", "20:00",
                "21:00", "22:00", "23:00"
            ],
            "data_format": "netcdf",
            "download_format": "unarchived"
        }

        client.retrieve(dataset, request, target)
