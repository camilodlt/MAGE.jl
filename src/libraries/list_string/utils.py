# -*- coding: utf-8 -*-
from utcgp.libraries.overload import overload_with_pre_call
from utcgp.libraries.bundle import FunctionBundle


# Casters
def caster_list_str(x: list[str]) -> list[str]:
    return x


# fallbacks
@overload_with_pre_call
def IDENTITY_LIST_STR(i: list[str], *args) -> list[str]:
    return i


@overload_with_pre_call
def space_str(*args) -> str:
    return " "


basic_list_string = FunctionBundle(
    IDENTITY_LIST_STR, lambda: "", caster_list_str
)
basic_list_string.append_function(IDENTITY_LIST_STR, [(list[str],)])
