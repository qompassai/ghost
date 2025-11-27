# /qompassai/ghost/docs/conf.py
# Qompass AI Ghost Docs Config
# Copyright (C) 2025 Qompass AI, All rights reserved
####################################################
project = "Qompass AI Ghost"
copyright = "Copyright (C) 2025 Qompass AI, All rights reserved"
author = "Qompass AI"
extensions = ["myst_parser"]
myst_enable_extensions = [
    "colon_fence",
    "linkify",
]
smartquotes = False
templates_path = ["_templates"]
exclude_patterns = ["_build", "Thumbs.db", ".DS_Store"]
master_doc = "index"
html_theme = "sphinx_rtd_theme"
html_static_path = []
