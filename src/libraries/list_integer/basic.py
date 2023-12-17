# -*- coding: utf-8 -*-

"""
Exports :

- ***bundle_basic_list_int** : identity_list (the generic one)

"""  # noqa: E501

from utcgp.libraries.bundle import FunctionBundle
from typing import TypeVar
from utcgp.libraries.list_generic.basic import (
    caster_list,
    IDENTITY_LIST,
    _new_list,
)

T = TypeVar("T")


def empty_list(*args) -> list[int]:
    return _new_list()


bundle_basic_list_int = FunctionBundle(
    IDENTITY_LIST, lambda: _new_list(), caster_list
)
bundle_basic_list_int.append_function(IDENTITY_LIST, [(list[int],)])
bundle_basic_list_int.append_function(empty_list, None)
