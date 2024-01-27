using UTCGP: integer_cond
using UTCGP.number_arithmetic: number_minus
using UTCGP.listgeneric_utils: append_to_list, unique_in_list
using UTCGP.listgeneric_basic: reverse_list
using UTCGP.listgeneric_subset: subset_by_indices

"""
Text from the paper: 

Middle Character (CW) Given a string, return the middle
character as a string if it is odd length; return the two middle
characters as a string if it is even length.
"""
train_data = [
    [["Q"], ["Q"]],
    [[" "], [" "]],
    [["\$"], ["\$"]],
    [["E9"], ["E9"]],
    [[")b"], [")b"]],
    [["DOG"], ["O"]],
    [["OGD"], ["G"]],
    [["test"], ["es"]],
    [["\$3^:1"], ["^"]],
    [["middle"], ["dd"]],
    [["      "], ["  "]],
    [["hi  ~1"], ["  "]],
    [["  hi~1"], ["hi"]],
    [["hi~1  "], ["~1"]],
    [["testing"], ["t"]],
    [["XM?c%>x"], ["c"]],
    [["E:Rfg3u*xnNO;J0/csv?{sH]US+iG7x?y qK01c!*~\$L@~ypk6hZ_r!/\"=D\$"], ["7x"]],
    [["{+3h:TlB 9>3=)oKt/ms*9\$J.y5[0\$>F-uotVi;s.TnXOaH@}ytkuZuNsz\"?H:!=4*q"], ["u"]],
    [["A0yIZgWF W!V@Epj~5J2Cu141sYe/,EE8uW.ZUe7"], ["2C"]],
    [[".&v8BZ\"[\"-uQ9^VsDrj\"*CBs"], ["Q9"]],
    [["#-%Kxeo>3W;\"#3O-"], [">3"]],
    [["wu{u^_uaT%zhe%3b0\`jhy>@\`g;H4p4lG??jpzfTpsj^27i@Lk?!3W|Ev"], ["4p"]],
    [["qF\"pt\"PUFs hUnH5-%qcrgUAPA~("], ["nH"]],
    [["wyq!\"\`Kf@^H04f0ZgZ}@CJ\\{MTq\"0ymM82U~2tCHs0jVwUn"], ["{"]],
    [["!{E\`KCzk@p.08)vbch|c_ZmM-br\$\"7{"], ["b"]],
    [["?/*f*lb60UL-@ )&l-tt4&]X5A,{GMjM7y+1vkU \`wMplDB*w3r\\}[j}TY[b_;:"], ["M"]],
    [
        [
            "76bzIYVmeESi?i.Cw:c|z^+n\"/p#BFKaaPVLf)!aV@]8hr=Nb+B\\4I;I|I8r~C/a^h3mEB@HM[pSy\`*[4xPx1}ky2N",
        ],
        ["hr"],
    ],
    [
        [
            "lG49o=}ZD>\\ hHvt7|WwBy^erk(UtXY[M,6&s2k8ftLF.=wN!Mz(p[Ph:*ML:-7g|e^!1I-So.~3.a&vrBd",
        ],
        ["t"],
    ],
    [["\$N?k]:)<l\\*>JfbMSY~T|z19VJ>y/b-J6> q"], ["Y~"]],
    [["VF}HDG4nElLV/,^p#LH=CT\`\"RG5@hSa*5q"], ["#L"]],
    [
        [
            "HEg_gi@ZaI65R6WJKRQbAW{()I>:t@a0D0^>9n(oWChPrWROiYV8OJM?j=^Lq%>p-XG0}+ZpIVf#D,AP66\$NX#",
        ],
        ["hP"],
    ],
    [
        [
            "#tGdS34Q?ZN;.htDi&a056dKmy}oD*zrIR=_Wi\"UXl\\3-/Hx)U1n45VOnsbQ1/JJ5gQG7yC^>KXB,*8y~U(K{O[iw?#- j~G6u",
        ],
        [")U"],
    ],
    [
        ["F.\"lb? y)L@ks+d\`M.B{<i_zYf8Brb0VFr#>:?K4b+@6%IHw-;m=a\".h,w\`-OdXF%537oz>"],
        [">"],
    ],
    [["IA,>:#CL\\_\"\$#Ijqt;_St\"sq^5geR>/>\\]?y<ms5~~>C+#}cWhAm>Z6_C_X|5"], ["/"]],
    [["1mw<3ZH.%mEK"], ["ZH"]],
    [["3M-p.PIW\$*RC;Z0:M<PA5<w8v0-h:#(AKR"], ["M<"]],
    [["LsPvW\".#DOcmk+p%p"], ["D"]],
    [["\`>IaU|"], ["Ia"]],
    [["m}e,BnS Q59~E)oz^)%?MR(,U/vU#aVGD57.l\"\\.Ls8G7j"], ["(,"]],
    [["u.ZBajsYqG<-o_v?_[L_\$4Cpf,E%!"], ["v"]],
    [["c;=&8\`/.VnsnW\`jKu,Z*2#@bzkiv}+-3TElFox\`5\"9;|u:~+Nu2"], ["k"]],
    [
        [
            "5.oKR-\\BIk67a<{e~Ur0j7m\`#d7\`V\"t9<t)?>~,G!wIEqk)1E4cLXz^TWR~fb0gy2~e}k\`h~=q;9\`M+",
        ],
        ["G"],
    ],
    [
        [
            "W@1m|2,XjoSIMj#&;R;KqbXDXbc\$h<pf]Z8\$(LzvPwuh\$zCDPg#2hLGrAG&P>uISL_h(]L_wuM:}aXB[Ba=\$",
        ],
        ["wu"],
    ],
    [["uDBp;W+S[+6 n;\`gixOtPN(86#\"G0Le"], ["g"]],
    [["r{/\"!"], ["/"]],
    [["GVZT-m)C,(k#^u8Zd0qY!*_rf(-\`\\\\\\\"o"], ["d"]],
    [
        [
            "og=&vh.F\$\"wx\"zla2;*\$/+\$0IFA04\$*(-rb?obA!\`-,w/TU]+HzoYynKo\$q y{3kJ/Qk\\p8G.>~F.!gJRU&_GzD,%r^ag}\$,oC|N",
        ],
        ["Hz"],
    ],
    [["aAE6n<jXwf=a~w,&EW\"Z[j[^/TL\"O,Q;3*OMKbiV,KI4\$QN6a^@N"], ["TL"]],
    [["\\i=7"], ["i="]],
    [["kI[G"], ["I["]],
]

function middle_character_algo(x, y)
    x = x[1]
    length_string = reduce_length(x) # int
    even = modulo(length_string, 2)
    res = integer_cond.is_eq_to(even, 0)
    # div 2 
    m_c = number_div(length_string, 2)
    middle_char = floor(Int, m_c) # caster
    middle_char = number_sum(middle_char, 1)
    # Max
    l = make_list_from_two_elements(1, middle_char)
    middle_char = reduce_max(l)
    subset_indices = make_list_from_one_element(middle_char)
    right_middle = number_minus(middle_char, 1) # 
    next_middle = if_else_multiplexer(res, right_middle, middle_char)
    subset_indices = append_to_list(subset_indices, next_middle)
    subset_indices = unique_in_list(subset_indices)
    subset_indices = reverse_list(subset_indices)
    res = split_string_to_vector(x, "")
    res = subset_by_indices(res, subset_indices)# subset
    res = paste_list_string(res)
    return res == y[1]
end

@testset "Middle Character" begin
    for (x, y) in train_data
        @test begin
            middle_character_algo(x, y)
        end
    end
end
