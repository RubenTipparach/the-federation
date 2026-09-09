"""The six dialects of docs/17, each a module that builds one faction's hulls.

Every module exports `build(cls)` taking a row of `shipkit.CLASSES` and
returning a `shipkit.Hull`. The kit decides shape, `paint.py` decides colour,
and `tools/gen_fleet.py` writes what they agree on.
"""
