"""Read Swift-generated JSON without losing an integer-spelled negative zero.

Swift may encode a Double negative zero as -0. Python's default integer parser
turns that into positive integer zero, changing canonical mesh hashes on replay.
All other integers must retain their type and precision (including seeds).
"""
import json


def loads(data):
    return json.loads(data, parse_int=lambda value: -0.0 if value == '-0' else int(value))
