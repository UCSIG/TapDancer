"""
Generate build_info.h file before every build.
Add
extra_scripts =
    pre:tools/generate_build_info.py
to platformio.ini

In main.h:
#define SOFTWARE_VERSION "1.4.0." BUILD_COUNT_STR
"""

import datetime
import json
import os
import re

Import("env")


def generate_build_info():
    current_datetime = datetime.datetime.now()
    build_time = current_datetime.strftime("%d.%m.%Y %H:%M:%S")
    file_date = datetime.datetime.now().strftime("%B %d, %Y")

    main_h_file = "src/main.h"
    build_count_file = "tools/helper_data/build_count.txt"
    existing_version = "0.0.0"
    try:
        with open(build_count_file, "r") as f:
            lines = f.readlines()
            build_count = int(lines[0])

            if len(lines) > 1:
                existing_version = lines[1].strip()
    except FileNotFoundError:
        build_count = -1

    # Regex to extract version (matches something like 1.3.3 in #define SOFTWARE_VERSION "1.3.3.")
    version_pattern = r'#define SOFTWARE_VERSION\s+"([\d.]+?)\."'
    with open(main_h_file, "r") as f:
        content = f.read()
        match = re.search(version_pattern, content)
        if match:
            extracted_version = match.group(1)
            print(f"Extracted version: {extracted_version}")

            # Compare with the existing version
            if extracted_version != existing_version:
                build_count = -1

    build_count += 1
    os.makedirs(os.path.dirname(build_count_file), exist_ok=True)
    with open(build_count_file, "w+") as f:
        f.writelines([str(build_count), "\n", extracted_version])

    file_content = f"""\
/// @file build_info.h
///
/// @author UCSIG
/// @date {file_date}

/// The time of the last project build.
#define BUILD_TIME "{build_time}"

/// An incrementing build counter.
#define BUILD_COUNT {build_count}
#define BUILD_COUNT_STR "{build_count}"
"""

    with open("src/build_info.h", "w") as f:
        f.write(file_content)

    # Emit a manifest into the build output folder so packaging steps can pick
    # it up next to other build artifacts. The full version mirrors
    # SOFTWARE_VERSION ("<version>." BUILD_COUNT_STR), e.g. "1.4.2.456".
    full_version = f"{extracted_version}.{build_count}"
    build_dir = env.subst("$BUILD_DIR")
    os.makedirs(build_dir, exist_ok=True)
    with open(os.path.join(build_dir, "version.json"), "w") as f:
        json.dump(
            {"version": full_version, "build_time": build_time},
            f,
            indent=2,
        )


def change_firmware_name():
    env.Replace(PROGNAME="firmware_tapdancer")


generate_build_info()
change_firmware_name()
