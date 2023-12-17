# -*- coding: utf-8 -*-
from utcgp.libraries import overload
from utcgp.libraries.bundle import FunctionBundle
from utcgp.libraries.list_string.utils import (
    caster_list_str,
    IDENTITY_LIST_STR,
)

slice_list_string = FunctionBundle(
    IDENTITY_LIST_STR, lambda: [""], caster_list_str
)


@overload.overload_with_pre_call
def pick_from_inclusive(list_str: list[str], from_i: int, *args) -> list[str]:
    """
    i = 2
    a = [0,1,2,3]
    Result = [2,3]
    """
    return list_str[from_i:]


@overload.overload_with_pre_call
def pick_from_exclusive(list_str: list[str], from_i: int, *args) -> list[str]:
    """
    i = 2
    a = [0,1,2,3]
    Result = [3]
    """
    return list_str[from_i + 1 :]


@overload.overload_with_pre_call
def pick_until_inclusive(
    list_str: list[str], until_i: int, *args
) -> list[str]:
    """
    i = 2
    a = [0,1,2,3]
    Result = [0,1,2]
    """
    return list_str[: until_i + 1]


def pick_until_exclusive(
    list_str: list[str], until_i: int, *args
) -> list[str]:
    """
    i = 2
    a = [0,1,2,3]
    Result = [0,1]
    """
    return list_str[:until_i]


slice_list_string.append_function(
    pick_from_inclusive, available_signatures=[(list[str], int)]
)
slice_list_string.append_function(
    pick_from_exclusive, available_signatures=[(list[str], int)]
)
slice_list_string.append_function(
    pick_until_inclusive, available_signatures=[(list[str], int)]
)
slice_list_string.append_function(
    pick_until_exclusive, available_signatures=[(list[str], int)]
)
