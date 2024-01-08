using UTCGP.str_caps: capitalize_all
using UTCGP.str_grep: remove_pattern
using UTCGP.list_string_split: split_string_to_vector
using UTCGP.liststring_caps: uppercasefirst_list_string
using UTCGP.str_paste: paste_list_string
using UTCGP.str_caps: lowercase_at
using UTCGP: bundle_string_caps

"""
Text from PSB2 : Take a string in kebab-case and con-
vert all of the words to camelCase. Each group of words to
convert is delimited by "-", and each grouping is separated
by a space. For example: "camel-case example-test-string"
→ "camelCase exampleTestString".
"""

train_data = [
    [[""], [""]],
    [["nospaceordash"], ["nospaceordash"]],
    [["two-words"], ["twoWords"]],
    [["two words"], ["two words"]],
    [["all separate words"], ["all separate words"]],
    [["all-one-word-dashed"], ["allOneWordDashed"]],
    [["loooooong-wooooords"], ["loooooongWooooords"]],
    [["loooooong wooooords"], ["loooooong wooooords"]],
    [["a-b-c-d-e-f-g-h-i-j"], ["aBCDEFGHIJ"]],
    [["a b c d e f g h i j"], ["a b c d e f g h i j"]],
    [["saaaaaaaaaaaaaaaaame"], ["saaaaaaaaaaaaaaaaame"]],
    [["goav-pxc-ib"], ["goavPxcIb"]],
    [["wru qhv"], ["wru qhv"]],
    [["n"], ["n"]],
    [["s os mj-tjol"], ["s os mjTjol"]],
    [["ehk f levt sl-xk"], ["ehk f levt slXk"]],
    [["d-ispuq qxo-kxb pp"], ["dIspuq qxoKxb pp"]],
    [["rct y-p-l ds"], ["rct yPL ds"]],
    [["a-yuq lvu"], ["aYuq lvu"]],
    [["t-qi"], ["tQi"]],
    [["g qp"], ["g qp"]],
    [["lk-i-s-wc-vt-sok"], ["lkISWcVtSok"]],
    [["jl d"], ["jl d"]],
    [["vjlk"], ["vjlk"]],
    [["o-xhe"], ["oXhe"]],
    [["h-b dbexc-fhja"], ["hB dbexcFhja"]],
    [["er-pxhq-hu"], ["erPxhqHu"]],
    [["hg-qftap"], ["hgQftap"]],
    [["cc b zyew"], ["cc b zyew"]],
    [["usz njfo-q la"], ["usz njfoQ la"]],
    [["i-rzt-cqd-jdbn-jraw"], ["iRztCqdJdbnJraw"]],
    [["mhwim-qvfz-wgcqg"], ["mhwimQvfzWgcqg"]],
    [["wganv utaq he"], ["wganv utaq he"]],
    [["qvq-hoik"], ["qvqHoik"]],
    [["db-f"], ["dbF"]],
    [["euiv"], ["euiv"]],
    [["vxnf i"], ["vxnf i"]],
    [["ax"], ["ax"]],
    [["nla mnjz"], ["nla mnjz"]],
    [["o"], ["o"]],
    [["papl-jwkt-dkpde"], ["paplJwktDkpde"]],
    [["b rt"], ["b rt"]],
    [["lz"], ["lz"]],
    [["prz"], ["prz"]],
    [["llhe gz-euxq elg"], ["llhe gzEuxq elg"]],
    [["ysvz-zf"], ["ysvzZf"]],
    [["lzrh-yawii-n"], ["lzrhYawiiN"]],
    [["o"], ["o"]],
    [["vu"], ["vu"]],
    [["bo-vesd-vdzr-xwx"], ["boVesdVdzrXwx"]],
]

function camel_case_algo1(x, y)
    x = x[1]
    x = split_string_to_vector(x, "-")
    pred = uppercasefirst_list_string(x)
    pred = paste_list_string(pred)
    # pred = lowercase_at(pred, 1)
    pred = UTCGP.evaluate_fn_wrapper(bundle_string_caps[6], [pred, 1]) # if str is "", lowercase at will fail, but, "" is the fallback
    return pred == y[1]
end

@testset "Camel case" begin
    for (x, y) in train_data
        @test begin
            camel_case_algo1(x, y)
        end
    end
end
