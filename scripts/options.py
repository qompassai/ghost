# /qompassai/ghost/scripts/options.py
# Qompass AI Ghost Options Script
# Copyright (C) 2025 Qompass AI, All rights reserved
####################################################
import json
import sys
from textwrap import indent
from typing import Any, Mapping

header = """
# Qompas Ghost options

## `ghost`

"""

template = """
`````{{option}} {key}
{description}

{type}
{default}
{example}
`````
"""

f = open(sys.argv[1])
options = json.load(f)

groups = [
    "ghost.loginAccounts",
    "ghost.certificate",
    "ghost.dkim",
    "ghost.dmarcReporting",
    "ghost.fullTextSearch",
    "ghost.redis",
    "ghost.ldap",
    "ghost.monitoring",
    "ghost.backup",
    "ghost.borgbackup",
]


def md_literal(value: str) -> str:
    return f"`{value}`"


def md_codefence(value: str, language: str = "nix") -> str:
    return indent(
        f"\n```{language}\n{value}\n```",
        prefix=2 * " ",
    )


def render_option_value(option: Mapping[str, Any], key: str) -> str:
    if key not in option:
        return ""

    if isinstance(option[key], dict) and "_type" in option[key]:
        if option[key]["_type"] == "literalExpression":
            # multi-line codeblock
            if "\n" in option[key]["text"]:
                text = option[key]["text"].rstrip("\n")
                value = md_codefence(text)
            # inline codeblock
            else:
                value = md_literal(option[key]["text"])
        # literal markdown
        elif option[key]["_type"] == "literalMD":
            value = option[key]["text"]
        else:
            assert RuntimeError(f"Unhandled option type {option[key]['_type']}")
    else:
        text = str(option[key])
        if text == "":
            value = md_literal('""')
        elif "\n" in text:
            value = md_codefence(text.rstrip("\n"))
        else:
            value = md_literal(text)

    return f"- {key}: {value}"  # type: ignore


def print_option(option):
    if (
        isinstance(option["description"], dict) and "_type" in option["description"]
    ):  # mdDoc
        description = option["description"]["text"]
    else:
        description = option["description"]
    print(
        template.format(
            key=option["name"],
            description=description or "",
            type=f"- type: {md_literal(option['type'])}",
            default=render_option_value(option, "default"),
            example=render_option_value(option, "example"),
        )
    )


print(header)
for opt in options:
    if any([opt["name"].startswith(c) for c in groups]):
        continue
    print_option(opt)

for c in groups:
    print(f"## `{c}`\n")
    for opt in options:
        if opt["name"].startswith(c):
            print_option(opt)

