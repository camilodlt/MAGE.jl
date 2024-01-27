"""
Text from paper: 

Given a string representing a tweet, vali-
date whether the tweet meets Twitter’s original character
requirements. If the tweet has more than 140 characters, re-
turn the string "Too many characters". If the tweet is
empty, return the string "You didn’t type anything".
Otherwise, return "Your tweet has X characters", where
the 𝑋 is the number of characters in the tweet.
"""

train_data = [
    [[""], ["You didn't type anything"]],
    [["1"], ["Your tweet has 1 characters"]],
    [
        [
            "max length tweet that just contains letters and spaces even SOME CAPITAL LETTERS just to MAKE it INTERESTING now repeeeeeeeeeEEEEEEEeeeat it",
        ],
        ["Your tweet has 140 characters"],
    ],
    [
        [
            "40172875*&(&(%^^*!@&#()!@&^(*\$787031264123984721-43214876*%^#!(@^\$_!@^%#\$(!#@%\$(01234~~``)",
        ],
        ["Your tweet has 90 characters"],
    ],
    [
        [
            "Tooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooolong1",
        ],
        ["Too many characters"],
    ],
    [
        [
            "(@)&#N)&#@!M#&17t8023n217830123bn6 BN23780BC3879N01nc3n473N962n9768062BC3718N396b21v8365n9072B638705b097B6*&b%&%b(*B5*&%b7%(*vb&V8%v&(85V80%0857(%v97%(*&%v87c%&*c ()0*^c%08v^mN098)vf%9P8V6TfB97b99870)",
        ],
        ["Too many characters"],
    ],
    [["_m<1qqOw%20v%f.Rk8C5mP^FB1o`)&nt}(>dGqhM"], ["Your tweet has 40 characters"]],
    [
        [
            "}l[jo]YKpY8dp4[R\$zOuS78]%MjW0ZJ+:,[@j>rg2[I\"L,!>}X6\"|4Louu.a93QzQZP196|Ribzxs8R|_*lR*6C*",
        ],
        ["Your tweet has 88 characters"],
    ],
    [
        [
            "(,Fm&4rqiUM0*Ak{=l%suS*2.5*.z/f6.]O`OEudn(.#N?F0p:2s=Gdueu[z@LY\"5S^n)->t\"[czURvX~*mXqV({)NwHR!LF\"D4#l@Pc{qUc\"|0244d\$cU2l?wk>-*[>Qp0kH>rgw&x4DRI`BfG7js*!o0J_Ye@C*WENXJ{6{S,;(+YL>*PP#d<n}jxSMo<[k9",
        ],
        ["Too many characters"],
    ],
    [
        [
            "isd7vLL\\^PP11da@gNx6Of\\/T~USXN\"WNRR\"sP9m^2&NGL.aVV]N(iIa6EWW2sD3|`w@4b30d|#V3PgcI\"/&4|4D/)rb`=L3m\$,+\\c=X\\~N;8Vrdsd]_w,j.D<7g/E&Yp#f3ai[<#keqf[z",
        ],
        ["Too many characters"],
    ],
    [
        [
            "nu.F>cMZk|LCFte*pnp&GxB%zk\$p(L)qB~3Tck*lp<\$LU:RkquOGnx8q<vt\\7u%fPV~khHbfq!NXtGUKSjd\\W\$_@jRdXj[W!aBtu+m:u\$%oG/\"u\\+\$=`C?@~2c)~[U[j9ZE<w2n\\DQ",
        ],
        ["Your tweet has 138 characters"],
    ],
    [["14@CWUR|.\"sqN%&,"], ["Your tweet has 16 characters"]],
    [
        [
            "@1N;3f?Cjqcb8zRmDk`eFn5bP>T2W_|EHv0m>aATn&Ts#oFLT,ckI|7y`sgc9xrkFNo[ZXvR8r\\>%u#yWg68#I*NJ.`B8\$Tm5^`*:T7m]%xJ2Xpu))?O:0m[>?{%+>+`qQQ8?)Hq!od%(lTfu%f8z\"-u/8l=",
        ],
        ["Too many characters"],
    ],
    [
        [
            "FX;q\"IR?or!=Z!(:2?|:.dsk.lVk|sY,JB+Ep!&;seI1>_4\$9B\"Te~Z0e}TT.\"F(osz~(JdH9<=!dBH|2c*_zPO\$WmygYHI)wWOrC`IR7_8L]a?[GrZH+dT\$zj*Dg9Fc(U|lb/cXNC;Z*pHw.:?kwkdn?H+75|jM?\\w!U",
        ],
        ["Too many characters"],
    ],
    [["8Zc./q,78}}>I,S<P*B\$"], ["Your tweet has 20 characters"]],
    [
        [
            "Snu}?Azhjt}gJ}\\za(u8PXD@QI#)HC&U#LN=g_R89Sk{X\">C1;j\"|N\"SU\"yNYZ.+37VydAi<A_M`M:bhom%u5s=BMEw7JLByQ:Z#>o1M",
        ],
        ["Your tweet has 104 characters"],
    ],
    [
        [
            ";i)#v3!&Tr\"nIN^\$CCP{){]8:&DVcFIR}ZRw9R}iwoKR;`rz=x_r;k--%=fs19En]VF5/6;tIV0uZc7[+dA%\$H;kXvR\\{57|+jpOCb`,V6S+0*CGG5cl[c#tBK:GxHo/,PIY.*nEV9>;>{(I",
        ],
        ["Too many characters"],
    ],
    [
        [
            "Qsko)2G*wU*It?&NIFqo`\"y:\"DJzi9l;\\i\$BMcVZVp>0hoJOR4FGruL9|t.~<#s@f--H6:[jAZoj<r`|]?reCV.&iN=A\\&MXt8N;2tzMz",
        ],
        ["Your tweet has 105 characters"],
    ],
    [
        [
            "K\",;\$>J~s)}hxQ&OC}K[`>]F\\rlO^26l>AaJ;_+R[8S7_97qLWU>/38IaI;s3c-0+_|:Kp&/4JMl7+syq)1?[LC`Rp=Lm9?#PG[8\\GowIB4J:hL?&w+}S@Bh",
        ],
        ["Your tweet has 120 characters"],
    ],
    [
        [
            "#Qf^I?0@}@2q8o_{\"te>\"!I{_F;arvz>R1\"f\$TK;)TV^WK&`aFr`OwKR7k^n\"\\:/`n3oAlpn%}#X!?~@fL,]#K~B>-yX!vxH|BQEvU!dT`F%f*X/P%A\"9:\$GP=k<mPRn",
        ],
        ["Your tweet has 128 characters"],
    ],
    [
        ["P<h/q=F`+JW]yd+Xz8bYt,`p][s7=?/sCyJj5J%L\$3!>xM+\$\$4Y-vE@CX1R\"g9DK^f"],
        ["Your tweet has 66 characters"],
    ],
    [
        ["^X*J_%%*V:PscnFmDT)@?,r:k}_UB\$\"HgUdWOz7\$F9)0Cb"],
        ["Your tweet has 46 characters"],
    ],
    [
        ["Uxdzc6kLjT,,U,V*9V%n%-PK.Nm+:<\"Wpg4Oc@;m#U11[{@rMs>v!Hm1YwGk9`q7T8L1"],
        ["Your tweet has 68 characters"],
    ],
    [
        [
            "-glN=q7f/`oz%vPjv#n05JX8p-e]@s@|ZIWy]&f2vZab!S)WO45l;(Szc0~r\$u#^Tu>#LGM83(ko[iN\"G6p{YF0S<S7`-\"bH?k`Qe[_MX9SQJ)V%bi0{dumakU8U+K}dXJ",
        ],
        ["Your tweet has 130 characters"],
    ],
    [
        [
            "/|qnSQYvK2#Cw(U.5f6pm0HIRwWZfs?:uB-OT)/%SvZ<xA>2yKLZ%r8e%!y+)=cC+(!TZ)_O)#5xtF&o\"f&q]/~Zu(5j&`,=wzeddf+_~a1pt7\\=,67_Pd1&yL<\"SIV(ENt|di8;T_6Ak*BStt,IiI<ea9r-kJUm",
        ],
        ["Too many characters"],
    ],
    [["-Eg1,\$9o(fUZB|y>*FP9_+\$QPRG~1BRp*r%v83XJM@a"], ["Your tweet has 43 characters"]],
    [
        [
            "Anes]\$[a~\$.{:J[O#Y>d*7`#ooEl]9TUu4yc@Q{4C;Eo/\$&;PtwN*A)@m5wj]:?ai|};5:PjePtv>c8IAc-=gL7-M6#o-v.bJ|:z_CW-;1^Ij.UE5O5c<&7BBo%[s*wC^wWt?JV|IfyD",
        ],
        ["Your tweet has 140 characters"],
    ],
    [
        [
            "5HF)%Me6|TxKH7*TFeaodF==kZ]+~7^{H4pl9d(/d!3j`i=VQlMpR;EwX?8H~j4I_cI?2AniK6QBwt{N?(t-A\"}8{vbQ414``J8E_R8?XOdgR%n/j/kCaa@iyn_K~Ow{>Y0&c/zIv%05RD7t3FV}aw-cx`EuT>Wq_?q\\rWdx)IHZR",
        ],
        ["Too many characters"],
    ],
    [["^)U/t#fb,1zxi3Htfr%g0/)@(k]zsJCw&r.r?O6"], ["Your tweet has 39 characters"]],
    [
        [
            "~C3\"5lG&@*gUz%.]*KQ2ylPTzFHClg(/*}xh,,OJ\"{GI&kjitv/E|DK:,]Ajn[IBQRlw{\\8N!vFrIDt;?oLO&gAkcpJ\"i\$z6.?yi0Lbc=yRf#M9Z0s4_EUYmj0CqM}-jw.S;Jiq6@p>4j[,xz!A?xjcqHj/B>|RhNS1hpv*h>3HwszQdp\$Jvf\"g@M{_h",
        ],
        ["Too many characters"],
    ],
    [
        ["5vcw/L|<QjhTmf0lGns-D=6Dcew(5a\"\"pO-L7/`7Bj2cHd3Y|n}+O?>{u2o)eQk"],
        ["Your tweet has 63 characters"],
    ],
    [
        [
            "-9njQi0PEIl=+R:=.:<IAR!=^ht^BxEC7e3HRz#M>j}k><V#},q-!;gnnRn_-oTt}<8<_D\"3\\qtnEB*7>C0X|\"Fq~Cy4`N9b`V6ba?xJn3iSR6lR.DK.",
        ],
        ["Your tweet has 116 characters"],
    ],
    [["wP^+i!gV%#\"9@T9f\\0"], ["Your tweet has 18 characters"]],
    [
        [
            "`9v+zvV`~;%&kWS)lxge655u22xL&zEDL5n,NSn>|)b##{\$Wxchj>_7V4NgIk|F&{?epOahT\\zs03_!|Oe]ad|=@rF1b:~OusT%vu?F_#OrUZX\"D3,xL_Q5RghDL\"cDa{*5\"F\$FGno=8?cBTxH9e",
        ],
        ["Too many characters"],
    ],
    [
        [
            "f);O+t%JX4.;mYdJa@+\$\"9p%|)pgDWdSw;Ih7:_oh;}H+DMo8a+~Y.(.^\">uw*1RpW#=Ol+3m|\"e8d5P&e./!x]~O\"ley_(h%t\\)9(%Mq>/}6Pc^uKO_E4=xM?G\$_J]Mav/wQ2Bn*w#\\E~^c}aUe<i&`#:ak&F-\\:iDPVV6Pb6XF;7wgmlRwTPE?~.O~fq)",
        ],
        ["Too many characters"],
    ],
    [
        [
            "0RL<CC!5+{~fK]LM\"?yX)QundqS^^p\$i@^_bkqUz=LtQ_38Pk#UGF<1d){=,j\$QpY8<I7vWPyc8kN8{88,+dA0)\"mn_uiB?r[|`5wwW>ImG\"rd1YIW@TD%)v\\uX5bW-YXtN*FyZ\\y<##^9DL\"0EzUURZi6VV8&#``p~@(D",
        ],
        ["Too many characters"],
    ],
    [
        [
            "u|G0=)`\\t1Yd\"Bg)%_<Xb2=-TMl,4zam^~b-?U<|qdQb,~KH&iS:Z~2}2(\$@iz\\ww)h2utlB9OOm&0mm;A\$r(Qv~;Ft+U",
        ],
        ["Your tweet has 93 characters"],
    ],
    [
        [
            "*\"b]\"=xU[8-.F\"\$NE(CSxAvnWd\\[K:[P-Z/g4!wWjy#9.T5BzVBzTF4O{##pTEcr<\\i}7^PdV+YvEM@&U,\\*)83`TSs^`mj*XUVfr-QAek/j!j[:&)rG^v:y:",
        ],
        ["Your tweet has 121 characters"],
    ],
    [
        [":5V3qBC~N=#uAtn_^_5[6Zt]VN/s=\$@0GYD%Dk~=\$uz{;}.lJw@]SS.Ero"],
        ["Your tweet has 58 characters"],
    ],
    [
        [
            "|HE+l.n=#shtZBo\$:#TPnl3ACL8\"]tGeVr~,8_(>ZtRX.2f8+xcA%w#o01lo#=x+ZgXUUc}\\@V;;w7adJJT:~HW93G9yFLY~7GeoTdci/jQW%W~1[+3GVo__fSOKyDY!2NfZCYO\\0=e\"o}^5\\T*<*g\"`!c+\"vKzA=U?.;|y{c",
        ],
        ["Too many characters"],
    ],
    [
        [
            "F7gEA9@de\"kzGg15jrYZTsf:bq&<a+8KrG,t[A=0TE+DvQf(+,^?A],EGq=!,u}OxMzM(p6DqlwOO\"Dg\"[)zNFRs`:J>pS5LmR.4\"9[,T{d.>:^?=4,\"n3",
        ],
        ["Your tweet has 118 characters"],
    ],
    [
        [">]?sy3)7VBcf:I3Ka{\$\"S{fq1=tj9*7B_H@fc\$[[?o#oSYqv5@M*\"eLYCf[tz&1Nc\"m>i<j"],
        ["Your tweet has 71 characters"],
    ],
    [
        [
            "t=2!!w8yeEkk[(F0UD=,I}O?Q%,vVwo^s1{k@ml:LPG%LYs?jW-TtJ%`wNfX|4^{+:HcMx{6`UunY!\"dXa7?7K#NsH`u|O~cguE8M@)0\"Tv&Qe8&4\$[cUqx+TRXfhWvr`eQ!l&;BY^b|tA?^P{>go>%\$9>2W%;Me",
        ],
        ["Too many characters"],
    ],
    [
        [
            "\"zo@a9FHHU..0h*qM%1z\";WA4-Guiwe6AVj#8u3*@\"zA>mRbs3Wd%Y(\\U}t#2?Mz4QLHP1T\$*sCNB#s(7(j^kKTZ,yxAh;WDv&sLFl+es3C?LB[DG~0/Ax?\".R/b4{mBs::\\3HVBBZ=dnvbw+\\^!{LB2x3~Kx+F2`?<lhID^D?JVThy!\"",
        ],
        ["Too many characters"],
    ],
    [
        [
            "HV|ms1:*H\$v(xbR7l{XQF?n5H*`!ix[=a-WeD4c3?->I4@_xuo@MXcEY|9pZPt[0A`GQ7c<4c*,(vh|\"dlL<c\"sqDF\\=7<0\$~a*R+TP%F+LGZT0.\"[\"\"",
        ],
        ["Your tweet has 116 characters"],
    ],
    [
        [
            "\"8i9[33q<lQnJ\"{mjwZQuKS(?/al|/:5o^g1ddGM;i@W2r8q>fNkf&QQTDnJy{B\"\"F?Gd1MvOaGyVtKyX]JnvO9*rEo3gKDSAPA+O]+K0^8jF9-{9&@*)v,BAq5v(>/cVj*3",
        ],
        ["Your tweet has 132 characters"],
    ],
    [
        [
            "bR2Ka/>kAzyFuWMD~\"|Hv.#0j[x>X@fgHp;V1Jc=QtA,!5X9>9k>J6Yz:cJb8ODT*TYKMD\"O\"W3UHf+KZ",
        ],
        ["Your tweet has 81 characters"],
    ],
    [
        [
            "?(*LE9Mc_~JNiBU9UL>ij)JtDjcdaE)m#cZ1PS\"_:(aL8]a,0!;64(/p&mYBmaCxkUObw4\${(l,BT2UC8hQ%R:lfk6hJA\\R9FtC^D*8FJi|?/zkO(}Q|Fij\"H3MG%UkgL2wQ:+~.da;dVEKBi34l\"?Ba)R{,r?\"^|</&~DKgCU`T0Y)6sG={`T@uG\">Ov]2o&",
        ],
        ["Too many characters"],
    ],
    [
        [
            "Vb?}rSM1o0/kQ9araxEOJ2#Z|`G9nCPTgdF!|%HL1*EE^{hp8\\3E6%dD5Du\">+nqa<-1?DR\"Vr=_2s|~c(bHp|U\\]!pV\\g8",
        ],
        ["Your tweet has 95 characters"],
    ],
    [["z)#?BQwdSraj)p<FPaH^*\"[Z\"By"], ["Your tweet has 27 characters"]],
]

function twitter_algo(x, y)
    a = "Your tweet has"
    b = "characters"
    too_many = "Too many characters"
    no_chars = "You didn't type anything"
    x = x[1]
    # count string
    c = reduce_length(x)
    l_lengths = make_list_from_one_element(c)
    conds = greater_than_broadcast(l_lengths, 140)
    gr_140 = pick_element_from_vector(conds, 1)
    c = number_to_string(c)

    # make list 
    l = make_list_from_two_elements(a, c)
    l = append_to_list(l, b)
    final1 = paste_space_list_string(l)

    # is empty
    empty = str_is_empty(x)

    res = ""

    # count more than
    res = if_else_string(no_chars, final1, empty)

    res = if_else_string(too_many, res, gr_140)
    return res == y[1]


end

@testset "Twitter" begin
    for (x, y) in train_data
        @test begin
            twitter_algo(x, y)
        end
    end
end




