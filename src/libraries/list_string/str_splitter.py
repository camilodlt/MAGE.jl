# -*- coding: utf-8 -*-
from utcgp.libraries import overload
from utcgp.libraries.bundle import FunctionBundle
from utcgp.libraries.list_string.utils import (
    caster_list_str,
    IDENTITY_LIST_STR,
)

str_splitter = FunctionBundle(IDENTITY_LIST_STR, lambda: [""], caster_list_str)


# Split an string #


@overload.overload_with_pre_call
def split_string_by(from_str: str, by: str = " ", *args) -> list[str]:
    if by == "":
        return from_str.split()
    return from_str.split(by)


str_splitter.append_function(
    split_string_by, available_signatures=[(str, str)]
)
