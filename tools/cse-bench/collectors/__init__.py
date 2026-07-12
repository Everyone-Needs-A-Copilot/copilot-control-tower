"""collectors — cse-bench collector plugins.

Drop-in registry: any module placed in this package that exposes both

    COLLECTOR_NAME = "some-name"          # str
    def collect(**kwargs) -> dict: ...    # returns {"metrics": {...}, "errors": [...]}

is auto-discovered by cse_bench.py at run time (see discover_collectors()
in ../cse_bench.py). No edits to cse_bench.py are required to add a new
collector — see README.md's "Adding a collector" section.
"""
