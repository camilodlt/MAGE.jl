
import UTCGP.listtuple_mappings
import UTCGP: listgeneric_utils

"""
Text from paper: 

This problem gives 3 strings.
The ﬁrst two represent a cipher, mapping each character in
one string to the one at the same index in the other string.
The program must apply this cipher to the third string and
return the deciphered message.
"""

train_data = [
    [["", "", ""], [""]],
    [["a", "a", "a"], ["a"]],
    [["j", "h", "j"], ["h"]],
    [["a", "z", "a"], ["z"]],
    [["e", "l", "eeeeeeeeee"], ["llllllllll"]],
    [["h", "d", "hhhhhhhhhhhhhhhhhhhh"], ["dddddddddddddddddddd"]],
    [["o", "z", "oooooooooooooooooooooooooo"], ["zzzzzzzzzzzzzzzzzzzzzzzzzz"]],
    [
        [
            "abcdefghijklmnopqrstuvwxyz",
            "zyxwvutsrqponmlkjihgfedcba",
            "bvafvuqgjkkbeccipwdfqttgzl",
        ],
        ["yezuefjtqppyvxxrkdwujggtao"],
    ],
    [
        [
            "abcdefghijklmnopqrstuvwxyz",
            "cdqutzayxshgfenjowrkvmpbil",
            "thequickbrownfxjmpsvlazydg",
        ],
        ["kytovxqhdwnpezbsfjrmgcliua"],
    ],
    [
        ["otghvwmkclidzryxsfqeapnjbu", "alpebhxmnrcyiosvtgzjwuqdfk", "aaabbbccc"],
        ["wwwfffnnn"],
    ],
    [["ahijsnzmge", "vquxakjihd", "sesjiiaimnigsznazmeises"], ["adaxuuvuikuhajkvjiduada"]],
    [
        ["nhmrvipgeqwkdaus", "ridphyqvnogtkwbj", "hvhkepnaavqrrnruwhn"],
        ["ihitnqrwwhopprpbgir"],
    ],
    [
        [
            "wtqvydhsibomfkpauzngjrex",
            "rgqbwpzctfexknoudshljvay",
            "jfnwqbvgdwdpfguugvozxbsgtv",
        ],
        ["jkhrqfblprpoklddlbesyfclgb"],
    ],
    [
        ["lyehnmakqtfcpxbidgvuswozrj", "smcbvtrypohilzujnwxgdefkaq", "oldgntpmwrbf"],
        ["fsnwvolteauh"],
    ],
    [["ndfkgrvtyzhojxmsael", "mxchvedjiswrafylqgu", "zgg"], ["svv"]],
    [["vzhskyufdbrpnxco", "grqicaftudjzxsle", "vnnshkzznfycb"], ["gxxiqcrrxtald"]],
    [["qspfh", "rjupe", "sqfhphhhqqf"], ["jrpeueeerrp"]],
    [
        ["pqirexahjdscbwluogy", "gvwapncuxbydeqzoksm", "bqbgyscicprolcoruudoss"],
        ["evesmydwdgakzdkaoobkyy"],
    ],
    [["xtb", "icf", "bttbxttxbt"], ["fccficcifc"]],
    [
        ["qhxirvpwkldgtmanbcy", "txbyjulrsacnqmwvoph", "pihddqrmyhxwiwvqmpnnpdy"],
        ["lyxcctjmhxbryrutmlvvlch"],
    ],
    [["ifysnmkxpgcutjrqa", "kntwepzcvolhmsabf", "jnm"], ["sep"]],
    [
        ["bgednvolkcas", "oqmhtkjuxzyi", "dvnecdeolosgckognabgea"],
        ["hktmzhmjujiqzxjqtyoqmy"],
    ],
    [
        [
            "ujvldtryxnkhwqmipoefgzbasc",
            "wtycgmraiszfdnhxvbuqpejolk",
            "ggkwndvbhqkijtckvtyuvyzv",
        ],
        ["ppzdsgyjfnzxtmkzymawyaey"],
    ],
    [["oxjdvhcakfwgeqzsultymbnr", "nsmfzuxkwtybeiljqgdvcrph", "kbxycvhbx"], ["wrsvxzurs"]],
    [
        [
            "oicvprnqjxdszlmktaeyhfbgu",
            "mnaeyoxfjwrdqigzkhustbpcl",
            "brtvccahpfivtmxhzdeccffrnl",
        ],
        ["pokeaahtybnekgwtqruaabboxi"],
    ],
    [["ga", "cv", "gggaaggggaaa"], ["cccvvccccvvv"]],
    [
        ["aocdflukhbrwypexqnimvgsjtz", "iknmrvuojwgezlsqfydatpcxbh", "hbocgmob"],
        ["jwknpakw"],
    ],
    [
        ["zyjpvtiuoasncfrwlbexd", "yjqmzfgpborhdcetuaknl", "rlzrudfdccctifowysptojvs"],
        ["euyeplcldddfgcbtjrmfbqzr"],
    ],
    [
        ["esyqdfpnchwjizt", "pmaoexucgqrdfsw", "wiqcwpyeyippdnqqjcjwsheh"],
        ["rfogruapafuuecoodgdrmqpq"],
    ],
    [["sywhacxjkznuvdplibfeo", "aetxmnzcourdqlibhgwfs", "bpxszjepzydl"], ["gizaucfiuelb"]],
    [["wf", "gi", "ffffww"], ["iiiigg"]],
    [["nzmopduliqhvxsyabgrfk", "mqnatergjxslypkfdzohc", "addnyq"], ["feemkx"]],
    [
        ["wspdrqfcjneg", "gcwfrhdltxmz", "pdcnwewdpgcnsfgwpndqwsggjg"],
        ["wflxgmgfwzlxcdzgwxfhgczztz"],
    ],
    [["iyhe", "tuoj", "hhyeeiyeeehieh"], ["ooujjtujjjotjo"]],
    [["buhatzqgo", "ufoexmltg", ""], [""]],
    [["eybzn", "zeoyc", "enyzbb"], ["zceyoo"]],
    [["ylz", "fny", "lyzyzyzy"], ["nfyfyfyf"]],
    [["opxjlniurcw", "wvnrdagjfou", "poocwwrnnijcowriol"], ["vwwouufaagrowufgwd"]],
    [
        [
            "opsclzwyvjkfmnidhugqtbexr",
            "qyofxjvlctwbnedguimphskrz",
            "xkvqbsfdduelvnoqnpiorxeig",
        ],
        ["rwcpsobggikxceqpeydqzrkdm"],
    ],
    [["wvjpgi", "oycdfg", "jppvgjwwwjgjijpggijvp"], ["cddyfcooocfcgcdffgcyd"]],
    [
        ["apoyvzufmnsrblxwqedcktijh", "txwmsdqkilcjyovabzrnpufhe", "ypztvhqzurr"],
        ["mxdusebdqjj"],
    ],
    [
        ["nguiefrhpxtzklacb", "kxeuncborltmgdipw", "hakkcbabpxgucefunhhcilb"],
        ["oiggpwiwrlxepncekoopudw"],
    ],
    [["upihedrb", "dmwxrfzo", "ibdhueiiubrbuhhupp"], ["wofxdrwwdozodxxdmm"]],
    [["nrisomby", "qlepmbos", "yiyiyibyo"], ["seseseosm"]],
    [["zxuwomavnfeqsdircptbgl", "lrnfpihvcezxdywobsjgkm", "ctcawgxcnv"], ["bjbhfkrbcv"]],
    [
        [
            "lfjnstuevxwirzgyqhkaodpcmb",
            "tqkphfowiuacegrbmslzjxyvdn",
            "fxxanfvrwugjkdtbzkvfwsmi",
        ],
        ["quuzpqieaorklxfngliqahdc"],
    ],
    [["h", "p", "hhhhhhhhhhhh"], ["pppppppppppp"]],
    [["ihuokympqznjevxwab", "adiewytksbplzgoqcf", "bppqiziohevazwk"], ["fkksabaedzgcbqw"]],
    [["cjtowrx", "jdzbhfi", "wxojwjcjorjjt"], ["hibdhdjdbfddz"]],
    [
        ["rpwxugfketanhbdjqlizvmc", "fjnkgiuhsyecrlmobtwzxaq", "bwdrcpggheljpxlecbjxak"],
        ["lnmfqjiirstojktsqlokeh"],
    ],
]


replace_by_mapping_str = listgeneric_utils.replace_by_mapping_factory(String)

function cipher_algo(x, y)
    # mapping
    from = x[1]
    to = x[2]
    to_change = x[3]

    # from 
    from = split_string_to_vector(from, "")
    to = split_string_to_vector(to, "")
    to_change = split_string_to_vector(to_change, "")

    # mapping tuples 
    mappings = listtuple_mappings.mappings_a_to_b(from, to)

    # Replace by matching 
    res = replace_by_mapping_str(to_change, mappings)

    # paste list 
    pred = paste_list_string(res)
    pred == y[1]
end

@testset "Substitution Cipher" begin
    for (x, y) in train_data
        @test begin
            cipher_algo(x, y)
        end
    end
end



