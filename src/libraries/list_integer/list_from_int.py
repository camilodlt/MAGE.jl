# -*- coding: utf-8 -*-

""" Create a list from 1 or 2 ints
Exports :

- **** :
    -

"""  # noqa: E501

from utcgp.libraries import overload
from utcgp.libraries.bundle import FunctionBundle
from utcgp.libraries.list_generic.basic import (
    caster_list,
    IDENTITY_LIST,
    _new_list,
)


# ############# #
# Make list int #
# ############# #


bundle_create_list_int = FunctionBundle(
    fallback=IDENTITY_LIST,
    last_fallback=lambda: _new_list(),
    caster=caster_list,
)


# INTERNAL FUNCTIONS ---
def _make_list(*args: int) -> list[int]:
    return [*args]


# FUNCTIONS ---


@overload.overload_with_pre_call
def make_list_from_one_int(a_number: int, *args) -> list[int]:
    """Wraps a number in a list

    Parameters
    ----------
    a_number : int
               Any number

    Returns
    -------
    list[int]
            The number wrapped in a list

    Examples
    --------
    >>> make_list_from_one_int(1)
    [1]
    """
    return _make_list(a_number)


@overload.overload_with_pre_call
def make_list_from_two_int(number_1: int, number_2: int, *args) -> list[int]:
    """Wraps two numbers in a list.

    Parameters
    ----------
    number_1 : int
               Any number
    number_2 : int
               Any number

    Returns
    -------
    list[int]
            The numbers wrapped in a list

    Examples
    --------
    >>> make_list_from_two_int(1,1)
    [1,1]
    """
    return _make_list(number_1, number_2)


bundle_create_list_int.append_function(
    make_list_from_one_int, available_signatures=[(int,)]
)
bundle_create_list_int.append_function(
    make_list_from_two_int, available_signatures=[(int, int)]
)
