using UTCGP
using UTCGP: CGPNode, ConstantNode, InputNode, SharedInput, InputPromise,
             modelArchitecture, Library, FunctionWrapper, FunctionBundle,
             OperationInput, Operation, Program

function _modular_function_program_fixture()
    cfg_model = modelArchitecture(
        [Int, Int], [2, 2],
        [String, Int],
        [Int], [2],
    )

    fallback_str = () -> ""
    bundle_string = FunctionBundle(fallback_str)
    empty_str = FunctionWrapper((args...) -> "", :empty_str, nothing, fallback_str)
    str_space = FunctionWrapper((args...) -> " ", :str_space, nothing, fallback_str)
    stringify = FunctionWrapper((x::Int, args...) -> string(x), :string, nothing, fallback_str)
    push!(bundle_string.functions, [empty_str, str_space, stringify]...)

    fallback_int = () -> 0
    bundle_int = FunctionBundle(fallback_int)
    identity_int = FunctionWrapper((x::Int, args...) -> x, :identity_int, nothing, fallback_int)
    add = FunctionWrapper((x::Int, y::Int, args...) -> x + y, :add, nothing, fallback_int)
    str_length = FunctionWrapper((x::String, args...) -> length(x), :length, nothing, fallback_int)
    push!(bundle_int.functions, [identity_int, add, str_length]...)

    ml = UTCGP.MetaLibrary([Library([bundle_string]), Library([bundle_int])])

    shared_inputs = SharedInput([
        InputNode(1234, 1, 1, 1),
        InputNode(10, 2, 2, 1),
    ])

    str_node = CGPNode(nothing, 1, 1, 1)
    len_node = CGPNode(nothing, 1, 1, 2)
    add_node = CGPNode(nothing, 2, 2, 2)
    out_node = OutputNode(nothing, 3, 3, 2)
    five_node = ConstantNode(5, 0, 0, 2)

    str_op = Operation(
        stringify,
        str_node,
        [OperationInput(InputPromise(1), -1, Int)],
    )

    len_op = Operation(
        str_length,
        len_node,
        [OperationInput(str_node, 1, String)],
    )

    add_op = Operation(
        add,
        add_node,
        [
            OperationInput(len_node, 2, Int),
            OperationInput(InputPromise(2), -1, Int),
        ],
    )

    out_op = Operation(
        add,
        out_node,
        [
            OperationInput(add_node, 2, Int),
            OperationInput(five_node, 2, Int),
        ],
    )

    full_program = Program([str_op, len_op, add_op, out_op], shared_inputs)
    full_program.is_reversed = true

    return (; cfg_model, ml, full_program, identity_int)
end
