"""
Abstract type of MAGE's callable objects that are not plain Julia functions
(e.g. modular functions, LLM-generated functions).
"""
abstract type AbstractFunction end

"Whether a function accepts an argument-type tuple, as cached by `safe_call`."
@enum IsGood::Int8 begin
    Good
    Bad
    Undefined
end

"Anything a `FunctionWrapper` can hold: a Julia function or an `AbstractFunction`."
LikeFunction = Union{Function, AbstractFunction}
