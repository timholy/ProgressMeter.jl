"""
Yoinked from https://github.com/briandowns/spinner

Copyright (c) 2022 Brian J. Downs

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
"""

const spinner_collection = Dict{UInt, Vector{String}}(
    1 => ["←", "↖", "↑", "↗", "→", "↘", "↓", "↙"],
    2 => ["▁", "▃", "▄", "▅", "▆", "▇", "█", "▇", "▆", "▅", "▄", "▃", "▁"],
    3 => ["▖", "▘", "▝", "▗"],
    4 => ["┤", "┘", "┴", "└", "├", "┌", "┬", "┐"],
    5 => ["◢", "◣", "◤", "◥"],
    6 => ["◰", "◳", "◲", "◱"],
    7 => ["◴", "◷", "◶", "◵"],
    8 => ["◐", "◓", "◑", "◒"],
    9 => [".", "o", "O", "@", "*"],
    10 => ["|", "/", "-", "\\"],
    11 => ["◡◡", "⊙⊙", "◠◠"],
    12 => ["⣾", "⣽", "⣻", "⢿", "⡿", "⣟", "⣯", "⣷"],
    13 => [">))'>", " >))'>", "  >))'>", "   >))'>", "    >))'>", "   <'((<", "  <'((<", " <'((<"],
    14 => ["⠁", "⠂", "⠄", "⡀", "⢀", "⠠", "⠐", "⠈"],
    15 => ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"],
    16 => ["a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l", "m", "n", "o", "p", "q", "r", "s", "t", "u", "v", "w", "x", "y", "z"],
    17 => ["▉", "▊", "▋", "▌", "▍", "▎", "▏", "▎", "▍", "▌", "▋", "▊", "▉"],
    18 => ["■", "□", "▪", "▫"],
    19 => ["←", "↑", "→", "↓"],
    20 => ["╫", "╪"],
    21 => ["⇐", "⇖", "⇑", "⇗", "⇒", "⇘", "⇓", "⇙"],
    22 => ["⠁", "⠁", "⠉", "⠙", "⠚", "⠒", "⠂", "⠂", "⠒", "⠲", "⠴", "⠤", "⠄", "⠄", "⠤", "⠠", "⠠", "⠤", "⠦", "⠖", "⠒", "⠐", "⠐", "⠒", "⠓", "⠋", "⠉", "⠈", "⠈"],
    23 => ["⠈", "⠉", "⠋", "⠓", "⠒", "⠐", "⠐", "⠒", "⠖", "⠦", "⠤", "⠠", "⠠", "⠤", "⠦", "⠖", "⠒", "⠐", "⠐", "⠒", "⠓", "⠋", "⠉", "⠈"],
    24 => ["⠁", "⠉", "⠙", "⠚", "⠒", "⠂", "⠂", "⠒", "⠲", "⠴", "⠤", "⠄", "⠄", "⠤", "⠴", "⠲", "⠒", "⠂", "⠂", "⠒", "⠚", "⠙", "⠉", "⠁"],
    25 => ["⠋", "⠙", "⠚", "⠒", "⠂", "⠂", "⠒", "⠲", "⠴", "⠦", "⠖", "⠒", "⠐", "⠐", "⠒", "⠓", "⠋"],
    26 => ["ｦ", "ｧ", "ｨ", "ｩ", "ｪ", "ｫ", "ｬ", "ｭ", "ｮ", "ｯ", "ｱ", "ｲ", "ｳ", "ｴ", "ｵ", "ｶ", "ｷ", "ｸ", "ｹ", "ｺ", "ｻ", "ｼ", "ｽ", "ｾ", "ｿ", "ﾀ", "ﾁ", "ﾂ", "ﾃ", "ﾄ", "ﾅ", "ﾆ", "ﾇ", "ﾈ", "ﾉ", "ﾊ", "ﾋ", "ﾌ", "ﾍ", "ﾎ", "ﾏ", "ﾐ", "ﾑ", "ﾒ", "ﾓ", "ﾔ", "ﾕ", "ﾖ", "ﾗ", "ﾘ", "ﾙ", "ﾚ", "ﾛ", "ﾜ", "ﾝ"],
    27 => [".  ", ".. ", "..."],
    28 => ["▁", "▂", "▃", "▄", "▅", "▆", "▇", "█", "▉", "▊", "▋", "▌", "▍", "▎", "▏", "▏", "▎", "▍", "▌", "▋", "▊", "▉", "█", "▇", "▆", "▅", "▄", "▃", "▂", "▁"],
    29 => [".", "o", "O", "°", "O", "o", "."],
    30 => ["+", "x"],
    31 => ["v", "<", "^", ">"],
    32 => [">>--->", " >>--->", "  >>--->", "   >>--->", "    >>--->", "    <---<<", "   <---<<", "  <---<<", " <---<<", "<---<<"],
    
    # Original didn't have fixed width
    33 => ["|       ", "||      ", "|||     ", "||||    ", "|||||   ", "||||||  ", "||||||| ", "||||||||", "||||||| ", "||||||  ", "|||||   ", "||||    ", "|||     ", "||      ", "|       "],

    34 => ["[          ]", "[=         ]", "[==        ]", "[===       ]", "[====      ]", "[=====     ]", "[======    ]", "[=======   ]", "[========  ]", "[========= ]", "[==========]"],
    35 => ["(*---------)", "(-*--------)", "(--*-------)", "(---*------)", "(----*-----)", "(-----*----)", "(------*---)", "(-------*--)", "(--------*-)", "(---------*)"],
    36 => ["█▒▒▒▒▒▒▒▒▒", "███▒▒▒▒▒▒▒", "█████▒▒▒▒▒", "███████▒▒▒", "██████████"],
    37 => ["[                    ]", "[=>                  ]", "[===>                ]", "[=====>              ]", "[======>             ]", "[========>           ]", "[==========>         ]", "[============>       ]", "[==============>     ]", "[================>   ]", "[==================> ]", "[===================>]"],
    38 => ["🌍", "🌎", "🌏"],
    39 => ["◜", "◝", "◞", "◟"],
    40 => ["⬒", "⬔", "⬓", "⬕"],
    41 => ["⬖", "⬘", "⬗", "⬙"],
    42 => ["[>>>          >]", "[]>>>>        []", "[]  >>>>      []", "[]    >>>>    []", "[]      >>>>  []", "[]        >>>>[]", "[>>          >>]"],
    43 => ["♠", "♣", "♥", "♦"],
    44 => ["➞", "➟", "➠", "➡", "➠", "➟"],
    45 => ["  |  ", " \\   ", "_    ", " \\   ", "  |  ", "   / ", "    _", "   / "],
    46 => ["  . . . .", ".   . . .", ". .   . .", ". . .   .", ". . . .  ", ". . . . ."],
    47 => [" |     ", "  /    ", "   _   ", "    \\  ", "     | ", "    \\  ", "   _   ", "  /    "],
    48 => ["⎺", "⎻", "⎼", "⎽", "⎼", "⎻"],
    49 => ["▹▹▹▹▹", "▸▹▹▹▹", "▹▸▹▹▹", "▹▹▸▹▹", "▹▹▹▸▹", "▹▹▹▹▸"],
    50 => ["[    ]", "[   =]", "[  ==]", "[ ===]", "[====]", "[=== ]", "[==  ]", "[=   ]"],
    51 => ["( ●    )", "(  ●   )", "(   ●  )", "(    ● )", "(     ●)", "(    ● )", "(   ●  )", "(  ●   )", "( ●    )"],
    52 => ["✶", "✸", "✹", "✺", "✹", "✷"],
    53 => ["▐|\\____________▌", "▐_|\\___________▌", "▐__|\\__________▌", "▐___|\\_________▌", "▐____|\\________▌", "▐_____|\\_______▌", "▐______|\\______▌", "▐_______|\\_____▌", "▐________|\\____▌", "▐_________|\\___▌", "▐__________|\\__▌", "▐___________|\\_▌", "▐____________|\\▌", "▐____________/|▌", "▐___________/|_▌", "▐__________/|__▌", "▐_________/|___▌", "▐________/|____▌", "▐_______/|_____▌", "▐______/|______▌", "▐_____/|_______▌", "▐____/|________▌", "▐___/|_________▌", "▐__/|__________▌", "▐_/|___________▌", "▐/|____________▌"],
    54 => ["▐⠂       ▌", "▐⠈       ▌", "▐ ⠂      ▌", "▐ ⠠      ▌", "▐  ⡀     ▌", "▐  ⠠     ▌", "▐   ⠂    ▌", "▐   ⠈    ▌", "▐    ⠂   ▌", "▐    ⠠   ▌", "▐     ⡀  ▌", "▐     ⠠  ▌", "▐      ⠂ ▌", "▐      ⠈ ▌", "▐       ⠂▌", "▐       ⠠▌", "▐       ⡀▌", "▐      ⠠ ▌", "▐      ⠂ ▌", "▐     ⠈  ▌", "▐     ⠂  ▌", "▐    ⠠   ▌", "▐    ⡀   ▌", "▐   ⠠    ▌", "▐   ⠂    ▌", "▐  ⠈     ▌", "▐  ⠂     ▌", "▐ ⠠      ▌", "▐ ⡀      ▌", "▐⠠       ▌"],
    55 => ["¿", "?"],
    56 => ["⢹", "⢺", "⢼", "⣸", "⣇", "⡧", "⡗", "⡏"],
    57 => ["⢄", "⢂", "⢁", "⡁", "⡈", "⡐", "⡠"],
    58 => [".  ", ".. ", "...", " ..", "  .", "   "],
    59 => [".", "o", "O", "°", "O", "o", "."],
    60 => ["▓", "▒", "░"],
    61 => ["▌", "▀", "▐", "▄"],
    62 => ["⊶", "⊷"],
    63 => ["▪", "▫"],
    64 => ["□", "■"],
    65 => ["▮", "▯"],
    66 => ["-", "=", "≡"],
    67 => ["d", "q", "p", "b"],
    68 => ["∙∙∙", "●∙∙", "∙●∙", "∙∙●", "∙∙∙"],
    69 => ["🌑 ", "🌒 ", "🌓 ", "🌔 ", "🌕 ", "🌖 ", "🌗 ", "🌘 "],
    70 => ["☗", "☖"],
    71 => ["⧇", "⧆"],
    72 => ["◉", "◎"],
    73 => ["㊂", "㊀", "㊁"],
    74 => ["⦾", "⦿"],
    75 => ["ဝ", "၀"],
    76 => ["▌", "▀", "▐▄"],
    77 => ["⠈⠁", "⠈⠑", "⠈⠱", "⠈⡱", "⢀⡱", "⢄⡱", "⢄⡱", "⢆⡱", "⢎⡱", "⢎⡰", "⢎⡠", "⢎⡀", "⢎⠁", "⠎⠁", "⠊⠁"],
    78 => ["________", "-_______", "_-______", "__-_____", "___-____", "____-___", "_____-__", "______-_", "_______-", "________", "_______-", "______-_", "_____-__", "____-___", "___-____", "__-_____", "_-______", "-_______", "________"],
    79 => ["|_______", "_/______", "__-_____", "___\\____", "____|___", "_____/__", "______-_", "_______\\", "_______|", "______\\_", "_____-__", "____/___", "___|____", "__\\_____", "_-______"],
    80 => ["□", "◱", "◧", "▣", "■"],
    81 => ["□", "◱", "▨", "▩", "■"],
    82 => ["░", "▒", "▓", "█"],
    83 => ["░", "█"],
    84 => ["⚪", "⚫"],
    85 => ["◯", "⬤"],
    86 => ["▱", "▰"],
    87 => ["➊", "➋", "➌", "➍", "➎", "➏", "➐", "➑", "➒", "➓"],
    88 => ["½", "⅓", "⅔", "¼", "¾", "⅛", "⅜", "⅝", "⅞"],
    89 => ["↞", "↟", "↠", "↡"]
)