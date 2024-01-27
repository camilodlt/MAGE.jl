using UTCGP.str_paste: paste_list_string
using UTCGP.listinteger_string
using UTCGP: liststring_broadcast
"""
Text from paper: 

Given a string of one or more words
(separated by spaces), reverse all of the words that are ﬁve
or more letters long and return the resulting string.
"""

train_data = [
    [[""], [""]],
    [["a"], ["a"]],
    [["this is a test"], ["this is a test"]],
    [["this is another test"], ["this is rehtona test"]],
    [["hi"], ["hi"]],
    [["cat"], ["cat"]],
    [["walk"], ["walk"]],
    [["jazz"], ["jazz"]],
    [["llama"], ["amall"]],
    [["heart"], ["traeh"]],
    [["pantry"], ["yrtnap"]],
    [["helpful"], ["lufpleh"]],
    [["disrespectful"], ["luftcepsersid"]],
    [["stop spinning these"], ["stop gninnips eseht"]],
    [["couple longer words"], ["elpuoc regnol sdrow"]],
    [["oneloongworrrrrrrrrd"], ["drrrrrrrrrowgnooleno"]],
    [["a b c d e f g h i j"], ["a b c d e f g h i j"]],
    [["ab cd ef gh ij kl mn"], ["ab cd ef gh ij kl mn"]],
    [["abc def gef hij klm"], ["abc def gef hij klm"]],
    [["word less than five"], ["word less than five"]],
    [["abcde fghij klmno"], ["edcba jihgf onmlk"]],
    [["abcdef ghijkl mnopqr"], ["fedcba lkjihg rqponm"]],
    [["abcdefg hijklmn"], ["gfedcba nmlkjih"]],
    [["abcdefgh ijklmnop"], ["hgfedcba ponmlkji"]],
    [["abcdefghi jklmnopqrs"], ["ihgfedcba srqponmlkj"]],
    [["on pineapple island"], ["on elppaenip dnalsi"]],
    [["maybe this isgood"], ["ebyam this doogsi"]],
    [["racecar palindrome"], ["racecar emordnilap"]],
    [["ella is a short pali"], ["ella is a trohs pali"]],
    [["science hi"], ["ecneics hi"]],
    [["kaj"], ["kaj"]],
    [["yun"], ["yun"]],
    [["ssc mwdr zoxar i"], ["ssc mwdr raxoz i"]],
    [["w x ozcj izctai"], ["w x ozcj iatczi"]],
    [["tplfev"], ["veflpt"]],
    [["flt oyzgacgw d"], ["flt wgcagzyo d"]],
    [["yhsufnfw qbherj"], ["wfnfushy jrehbq"]],
    [["bxtdtlfp nwgbfoplj"], ["pfltdtxb jlpofbgwn"]],
    [["idpxl e"], ["lxpdi e"]],
    [["slqkdsdo twn"], ["odsdkqls twn"]],
    [["gjb jbim hepru v"], ["gjb jbim urpeh v"]],
    [["bvz lrcj i"], ["bvz lrcj i"]],
    [["oat i u lhy"], ["oat i u lhy"]],
    [["il"], ["il"]],
    [["atlee ueeimz"], ["eelta zmieeu"]],
    [["xg g"], ["xg g"]],
    [["mncdqexn qdqtsnnq"], ["nxeqdcnm qnnstqdq"]],
    [["vl"], ["vl"]],
    [["rgmya kuwcynr"], ["aymgr rnycwuk"]],
    [["li dzg f"], ["li dzg f"]],
]

function spin_worlds_algo(x, y)
    w = split_string_to_vector(x[1], " ")
    # length
    lengths = listinteger_string.length_broadcast(w)
    # length more than 5 
    lengths = greater_than_broadcast(lengths, 4)
    # Reverse the needed ones 
    to_rev = subset_by_mask(w, lengths)
    reved_string = liststring_broadcast.reverse_broadcast(to_rev)
    final = replace_vec_at(w, reved_string, lengths)
    # concat 
    res = paste_space_list_string(final)
    res == y[1]
end

@testset "Spin Words" begin
    for (x, y) in train_data
        @test begin
            spin_worlds_algo(x, y)
        end
    end
end



