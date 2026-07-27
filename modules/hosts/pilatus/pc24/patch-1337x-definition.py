#!/usr/bin/env python3

import pathlib
import sys


source, destination = map(pathlib.Path, sys.argv[1:3])
definition = source.read_text()

identity = "id: 1337x\nname: 1337x\n"
replacement_identity = "id: 1337x-single-page\nname: 1337x (Single Page)\n"
if definition.count(identity) != 1:
    raise RuntimeError("upstream 1337x identity changed")
definition = definition.replace(identity, replacement_identity)

paths_start = definition.index("  paths:\n", definition.index("\nsearch:\n"))
paths_start += len("  paths:\n")
paths_end = definition.index("\n  keywordsfilters:", paths_start)

path_template = (
    "{{ if and (.Keywords) (eq .Config.disablesort .False) }}sort-"
    "{{ else }}{{ end }}"
    "{{ if .Keywords }}search/{{ .Keywords }}{{ else }}cat/CATEGORY{{ end }}"
    "{{ if and (.Keywords) (eq .Config.disablesort .False) }}"
    "/{{ .Config.sort }}/{{ .Config.type }}{{ else }}{{ end }}/1/"
)
category_groups = (
    ("Movies", (1, 2, 3, 4, 42, 54, 55, 66, 70, 73, 76)),
    ("TV", (5, 6, 7, 9, 28, 41, 71, 74, 75, 78, 79, 80, 81)),
    ("Music", (22, 23, 24, 25, 26, 27, 52, 53, 58, 59, 60, 68, 69)),
    (
        "Other",
        (
            10,
            11,
            12,
            13,
            14,
            15,
            16,
            17,
            18,
            19,
            20,
            21,
            33,
            34,
            35,
            36,
            37,
            38,
            39,
            40,
            43,
            44,
            45,
            46,
            47,
            48,
            49,
            50,
            51,
            56,
            57,
            67,
            72,
            77,
            82,
        ),
    ),
)
paths = "".join(
    '    - path: "{}"\n      categories: [{}]\n'.format(
        path_template.replace("CATEGORY", category),
        ", ".join(map(str, category_ids)),
    )
    for category, category_ids in category_groups
)

destination.write_text(definition[:paths_start] + paths + definition[paths_end:])
