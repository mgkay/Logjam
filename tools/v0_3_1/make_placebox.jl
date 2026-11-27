# make_placebox.jl -- the box of every Census 2020 place of `usplace()`, from the TIGER/Line 2020 place shapefiles, for
# `mapbbox(name; state)` (Logjam v0.3.1, PCV WP10, X7; MakePlan D3, his "accept" at Gate 1).
#
#   julia +1.12.6 --project=<repo> tools/v0_3_1/make_placebox.jl <shapefile directory> [<output directory>]
#
# INPUT, the one argument required: a directory holding, for each of the 52 files below (the 50 states, the District of
# Columbia and Puerto Rico), the `.shp` and `.dbf` unpacked from
#   U.S. Census Bureau, TIGER/Line Shapefiles 2020, Places (vintage 2020: the places of the 2020 Census),
#   https://www2.census.gov/geo/tiger/TIGER2020/PLACE/tl_2020_<SS>_place.zip
# whose sizes and SHA-256s, as downloaded, are
#   file                        bytes  SHA-256
#   tl_2020_01_place.zip   4954870  6441f037cf4740e070a1bf4734336ca5296da208c01c166c5a76b119fd6dfa36
#   tl_2020_02_place.zip   2791367  dceaed22eaa54312428cb0b88b570bbda5e4cb9f52c31a46537c8c5910093e24
#   tl_2020_04_place.zip   2787297  8c32c347e7c1a0b4b7a2d370a9f071936285c401875e206ca3bcdf582300f25e
#   tl_2020_05_place.zip   2326160  7e0f8bb36805f1821fb505b862eaba8c0c36bd64298b59d6a561448740c7b653
#   tl_2020_06_place.zip   9587555  ac6e5df9062d9768585e53cd93059b13e7377edf8e18a17b9ff56dad183e5fbd
#   tl_2020_08_place.zip   2687817  3f5f0c917a4005c8c4fa081610db03f10ac3a83af98654849b7ea6936ae0694b
#   tl_2020_09_place.zip    867378  f9b6012ea093c46c8e2af60c591eb9acadc571509e806182eefcd3d7752f72c9
#   tl_2020_10_place.zip    429134  63c7ad0793a3e1f15322a78285c19b9a4bd4530c9759c0b868b67d0845379b30
#   tl_2020_11_place.zip     84312  fdf452248609a770aa41447b4be5d7e9e498fda4335309d050c7f396d22f6479
#   tl_2020_12_place.zip   6427388  ed71ffb09326a6ce28d2b7201b6fedc09ca202874638e7971f4ab877902cea54
#   tl_2020_13_place.zip   4662496  dc5bade835855dcc531e2793820b4924fbec177388ee367a92e2fb63519cae43
#   tl_2020_15_place.zip    750984  93fc21bf4fe2080ec587678fa9a8f3009cfb8d5fc293263a30256cbd1b0b3e68
#   tl_2020_16_place.zip   1003589  30f84c0bddf591ac8383dca214a75d3756e16e975c402713fe2658d03b0a689c
#   tl_2020_17_place.zip   5887654  2ebeb9eeb1800bd72dcd70c2f90a4b5af0114b0b250dbb96e429ff0108456db6
#   tl_2020_18_place.zip   1986012  7300b8bcc2191d34b0c57a9514401e19cab0ef7da04aa007db1713b8765ee4f0
#   tl_2020_19_place.zip   1831263  0e30a0b6572eb910993362f5fc58b63aa823332d0d2981782d7e20e116f53a80
#   tl_2020_20_place.zip   1603198  abd5cb132f2303b5c01344f153b78c11dc10f62f0e8538611be772534c150991
#   tl_2020_21_place.zip   2528212  0fd6590255c11067af0e4dd04718984cdd362655d0c71780d6b947c0bb59753e
#   tl_2020_22_place.zip   1851538  dbab8859c6199ed24c9eff6f6df3e3262e2a1de6777e2b27a30ebcefbf522382
#   tl_2020_23_place.zip    668562  5be61d58a011dacfdb0e5b7bd97d15880525a5fb7e6ab8ea3f19aa49a0003715
#   tl_2020_24_place.zip   2563783  0b0dc8d1769136e0dd8c82a684a4948ff959c430b26db464c216a825a764ff90
#   tl_2020_25_place.zip   1158393  e28199498c856c1478bf33605da6aa8b5f333bbfbb55e9be07e07ec2a904373e
#   tl_2020_26_place.zip   1428405  1ebb5b9c7305ceefa98c8bd5a79169828d499d8e2941411f9ab945410d64c137
#   tl_2020_27_place.zip   2387526  dbad8e105b2dd5667b8e474caaf9585f7c074b7ed939b64486620886d54976aa
#   tl_2020_28_place.zip   1448492  5f54a5744358807ce644057bcaf3453dc2f7275c2eb9eb63f2a24e3416bdd08d
#   tl_2020_29_place.zip   2893269  5079c97c20d72912b5ae32f017b0bf7e68404a9c29020f1d0bff707e361a9c08
#   tl_2020_30_place.zip   2214404  ae43d819e49906df0816b5b70da07088a0e95ae5f76134e59959ea3807c5b538
#   tl_2020_31_place.zip    734471  02c4377b6fdc6ea430ca7d02cda82e7837397e85cab4b1bef8947beaeafebe0b
#   tl_2020_32_place.zip    828113  46ebf073e2b2d2cbbea4879061d69555545c4b18b2000fe97f818d39ce35af2b
#   tl_2020_33_place.zip    370568  b526235abc0b22e4130b1216762b90bf7d99670cb9fda13d5d2144804eef1b54
#   tl_2020_34_place.zip   2855806  ff1d6afa2f1e08361099847f991b8b5d5a3e7e368ae383db46683553cba0ce12
#   tl_2020_35_place.zip   2315012  e8391b6b369f699a55de7e8763acbae9dd03cc7e6ff5dcc20343de0cadb40c2d
#   tl_2020_36_place.zip   3249998  53e18de521985dbd69c2ad1c62aa5143dec0411ca122f4eaa395ff61f40b10b5
#   tl_2020_37_place.zip   7625398  b50d3b529983dc29afbb8fb522b558ccbd86acd319d2d9a5ed5fd63eed1608a7
#   tl_2020_38_place.zip    522259  fa39712affe020659d3b54a30e9bd36373249b58798b8ed5d28f9a08aa0cbea5
#   tl_2020_39_place.zip   3777800  56033d7aaf4a6ce20ecbf860aab370101863475e9f21ad9c679a304c682edc79
#   tl_2020_40_place.zip   2870084  3307921d51731463452c4a45291d8203d462eff2de5007c1b5625d6ebd85a014
#   tl_2020_41_place.zip   2242324  679248a28caa2d73a58a79d14f8958121c341c868f5fac943fb0b90d552175dd
#   tl_2020_42_place.zip   4284751  3a9b5e14ae96bb6201795b1c18bdec7cf8f2a797f7b34b322ccb4f0dd11efa1d
#   tl_2020_44_place.zip    283756  aebfd18104a97433c56977d1e54f2e943c8e445fb596ca0226f1ad57485b62cb
#   tl_2020_45_place.zip   4791165  b2d9e5741ca711c2a3cc16c783f6cb282d196aa6e52cc83474227dad2e94e985
#   tl_2020_46_place.zip    775650  7a3f8293c469a270360ced8881b642d492e79d67360d72081f14ffc791238af3
#   tl_2020_47_place.zip   4748901  84968a1ad12294e536f6b958fbcbe36efbe0864d700b8b95d2a5d6cf550cd697
#   tl_2020_48_place.zip   8979278  52dd19aef521cac977c3093d68267e4b1128448f002938a225550e84cd14ff6b
#   tl_2020_49_place.zip   1528554  da3b69df46a4323c8c26a4fe8c56e12f579e0b8060afc121a9e07ae165be4858
#   tl_2020_50_place.zip    565031  8cda6f7d6286e405e64c89cf642b3ea008609d211a840735ef6c1eff56131145
#   tl_2020_51_place.zip   3680928  a20950e52e1136a1b3fe4d92dfa6b339b01b7098d0d25bfa4920c8cc940b9f41
#   tl_2020_53_place.zip   2826224  f2000e0d5b7b38a0ff401b16a10d9c1084c1cabbf38dd852af1ec21cd7fa726e
#   tl_2020_54_place.zip   1545830  63ff5ecee05ba229026c5fdfc851143261a6fb8e7d9b4430d3229aa9182b369b
#   tl_2020_55_place.zip   3313933  741a6c89fe86d46a6ad8aee2d3b6bec3d19164222ae1fc1c72a85ec50c175065
#   tl_2020_56_place.zip    910635  d8c2122ffe03409d75fb20a5af6924c9c91de23a1519c87f7c1839fd2b1edd21
#   tl_2020_72_place.zip    740003  08883fd86c79a976bb03621bf342a8e06017cefea5984ce2b918daa0f7cd1e7d
# None of these is committed. The script reads the unpacked `.shp` and `.dbf`, whose sizes and SHA-256s it checks
# against `INPUTS` below before reading anything, and nothing else of them (the `.shx` index, the `.prj` and the
# `.cpg` are not needed).
#
# HOW THEY ARE READ, with Base Julia only (no shapefile package, so nothing is added to any environment; this
# replaces the MakePlan's separate shapefile environment):
#   - the `.shp` (ESRI Shapefile Technical Description, 1998): a 100-byte header (file code 9994 and the file length
#     in 16-bit words, big-endian; version 1000 and shape type 5, a polygon, little-endian), then one record per
#     place: an 8-byte header (record number and content length, big-endian), the shape type (5; a null shape, 0, is
#     a stop) and the polygon's bounding box, Xmin, Ymin, Xmax, Ymax, four little-endian doubles, which are what is
#     kept; the rest of the record (its parts and points) is skipped by its length. The box is the extent of every
#     point of every part of the polygon, so a place's box is the extent of its Census polygon (D3);
#   - the `.dbf` (dBASE III): its header (the record count, the header and record lengths and the 32-byte field
#     descriptors) and fixed-width records, from which `STATEFP` and `PLACEFP` are read as text (and `INTPTLON`,
#     `INTPTLAT`, the Census interior point, for the report). Records are in the `.shp`'s order, one each.
#
# THE STEPS:
#   1. every `.shp` and `.dbf` is checked against `INPUTS` and read; the two hold the same number of records, every
#      record is a polygon, no record is marked deleted, every `STATEFP` is its file's, and no (STATEFP, PLACEFP)
#      repeats;
#   2. every key (`STFIP`, `PLFIP`) of `usplace()` must be a 2020 place in the files: one that is not is a STOP,
#      reported and never guessed. The places of the files that `usplace()` does not carry are counted and printed
#      by state (Puerto Rico's among them: `usplace()` holds no territory);
#   3. the report: each `usplace()` point against the Census interior point of its place (the largest difference in
#      degrees) and whether it lies in its box;
#   4. the table is written.
#
# OUTPUT, to the repository's data/ (or to <output directory>, for a trial run):
#   - usplacebox.csv: `STFIP`, `PLFIP` (Int64, as `usplace()` has them), `LONmin`, `LONmax`, `LATmin`, `LATmax`
#     (Float64, the polygon's box as the `.shp` stores it), one row for each row of `usplace()`, sorted by
#     (`STFIP`, `PLFIP`). Written by CSV.jl's writer, as the other tables in data/ are: each float in the shortest
#     form that reads back as the `.shp`'s double (Ryu's), LF line endings, no time stamp, so every run gives the same
#     bytes; the script reads it back and asserts every value `===` the one read from the `.shp`;
#   - usplacebox.jls: the CSV read back, serialized, as the other tables' `.jls` are (Logjam reads the `.jls`).
# Prints each file's SHA-256 and size.
#
# Run at v0.3.1 (Julia 1.12.6, twice, to a scratch directory and to data/; the same bytes each time):
#   31,909 TIGER/Line 2020 places read; every one of usplace()'s 31,617 keys matched, none missing; the 292 places
#   Logjam does not carry are Puerto Rico's (72); usplace()'s points within 5e-7 degrees of the Census interior
#   points, none outside its box.
#   usplacebox.csv  SHA-256 39d6c7345c7f795a6cd87b0780202c8677155d05fda1e4f3ebbad7e109ea816b  (31,617 rows, 1,877,040 bytes)
#   usplacebox.jls  SHA-256 3ce58ccdb5d43fb2f239b522b18513b394be13fc8d5d7bcea03a04eea96d6620  (1,517,912 bytes)
#   Raleigh (37, 55000): LON (-78.818556, -78.470789), LAT (35.70825, 35.970784).

using Logjam, DataFrames, CSV, Serialization, SHA, Printf

const REPO = abspath(joinpath(@__DIR__, "..", ".."))
const DATA = joinpath(REPO, "data")
const URL = "https://www2.census.gov/geo/tiger/TIGER2020/PLACE/"

# state code => (.shp bytes, .shp SHA-256, .dbf bytes, .dbf SHA-256), as unpacked from the zips above
const INPUTS = Dict(
    "01" => (7907504, "5bddba10f83751a1ab488bcf1c4097c2965cfaa39d274cfcb8e88919ce9f2b19", 170144, "2188d517e9d74982c4cdf08207b7c7a9f0d212c08aa262aad6d999cc4467940a"),
    "02" => (4210084, "3ca1be2e3428e4b65bc1ddded54be86b80fd5d3e25bcf1aeae4b8f1dae3c05a9", 102076, "0390de8dee50c9cbd80b47206fa0e6444a11ff1aebcf6dab6513b0bf59cac516"),
    "04" => (4387896, "4349f14629b9a561924101ded75edb074c8ae534d27b479d2f837b7504bc1e53", 134108, "ffd965d6f7562b91c18fcfc0fb8815c651c49ad6d0b867e83c13542ee86ecd21"),
    "05" => (3705884, "a6d31dacba248b2ea2d3366e3f77636563b7f5ef33159f367f6a707546410f6c", 179582, "919111a27c67992b2fba7c7f5a3cccd943382ff8d4c5e96dc99c5c3f32b19802"),
    "06" => (15133656, "6623f5024fc0c4ea3440db626dc9cd39ec05a1e2fe58f328564532a4bc78d2a5", 461292, "d221b3d3414f5ec280ee53c02d25ff28a9f95c2785f20735dc3d4510c77d9990"),
    "08" => (4291160, "f5870e27b4b852a3f0f54a4d4b5f0109ecc8473a66ecb518735ec4d06255c607", 138398, "e82709099d11bd0b1c0a531abdcb25294d0465047094a21ffbfa71b54168d583"),
    "09" => (1328996, "8273cc442222fdc91b003ddbb521fadcc79362e60b52c347d5e82f0e6b88aba2", 62036, "788d46edbe1f823d550ebe5825c68d5d9da8bb8da633c397019ace198fdd1671"),
    "10" => (656028, "9535f4ece1107a665069c99e1400fde9476ca397dd82e99e546285da335bdc20", 23140, "0be5994a066f9af1c675fa63a9f37820fbe6922f28c9c92923216b79ee516c0e"),
    "11" => (117948, "8014edc2ecbba304c825f7aae2c07ce87edf5471d1245796943dba4f45f8b772", 832, "cd7767af7638a3d7a81dbe4650c4f895dde9f0954fdde8800bef3ec2a093c904"),
    "12" => (10518352, "3c0021e17269d1e8253346b8dcaf26f840018a702de62dcd345772aade8b375c", 273676, "520f3fbab4f142fb3d4c92ede784af873243b85828df897cdbf71d01d059b8b9"),
    "13" => (7325520, "ff56c06d30d5d58a9c08f95a269c5bab105cd483a1c7b21076fa452a3478cae0", 193596, "92eca9b6ef27dfb0fea2529c8442df6d3f8d280638b3bb1c637055461c4b7138"),
    "15" => (1147536, "30bd6ac687371fae4a56d43cedc3f854e9f2d33ac259538728050819e4324dc3", 47164, "ab04dc45489dd996fe42baacbc9b8f8fab68539d9675a86580dc5f471707705d"),
    "16" => (1599972, "87a637f3c490037291b8d27e4bc89c2c63469139570f33bb76cff59d48029263", 68328, "ad6971d344080b6d312920d3dd1550aaa081fea080664bb51c959f989d15664e"),
    "17" => (9608328, "f18a8f5c7d03f2a915fd8699a20a00fba861d0608f2e156bcd05852a6928a61d", 419822, "0e1f037c9ad084dd24add05f75e7f3baec213b8d63bc80c565a43a916033d2e6"),
    "18" => (3208212, "2197356fcac17b2fccc763fab98c3797cbc78697c27b15cb289a1268f7e82468", 199602, "765cff1f841069205be87a8f769510f00ef85e59622ed48282e9781cf7025f59"),
    "19" => (3005480, "25b31b036b3c29c2aea5f29a5708cfdbbf886143ec36ac5d88b551cbe5732f97", 294554, "78cc91faaf7283ead76a5a349c9a7930d1e5e744edfca85bdf0b5522cd779529"),
    "20" => (2623656, "e9b37f96e91e7a05808b0bcef46edf23794d54c61ecebe9e087d768d941b2005", 212186, "9d13eee89f939836f10dadf30bd6fe88b8158537c60b7d689b895716b3060d11"),
    "21" => (3915788, "948d10bcff86c6fcf3249555082b69ce74f0b467dcf938a76ba137a2f1337547", 159276, "710158d694690df14dbbeeee5585acb84f7948440cd18274ec4642e845f37a6d"),
    "22" => (2905744, "fda12621b6874de81595e6f054805ac7b254645c31262fed9d33da3e2eeb0dcd", 140114, "88bb6802a5918394970b1076fddf3ab2f0705d08e3fdcbb55ab47f3c7a51b40c"),
    "23" => (1024580, "a940ee7f751fdfc47a57df3b3181d9b9f316f31dc07588f6217506d030b7f9b4", 44876, "b4762ab514c41d7763bf00da1e2c293e936fb2ffd23e9a112e8d03581b224e08"),
    "24" => (4007444, "c37888f6027a847230be09f0f9cfab7471ee9c437b452c669d00468ea7ab6c2f", 153842, "acfabe5b36646b39b17539358765e5586d3d8fd7c4c98b88a4c0480d6607e132"),
    "25" => (1794376, "4c188200181b80ae06dab7b48b27c08de5a7c724baaf977886c6693fc5b4fe67", 71474, "64778700e6057c431baf51c4ac6801cb135bd7b8ae705927938d0cfa55e9c0c3"),
    "26" => (2245000, "eafb9ed35079fb0871a882f349249ed94607a5711f8f29bc944749b7b611975f", 213616, "0133ce4eedd81a57c413988940c0c06f6a1e2ba248e77c0e0fb27862e8eaf8fa"),
    "27" => (3886228, "f9c3273ff3662f3c75d13920014fa4b8fc8b2ab88aa806c70092cca7ebb77dd7", 261664, "b2c36476664594bc216d8959667af357c6fae1985768d26d252b558ca9c91875"),
    "28" => (2288476, "3ac15d6ac2f1af585af61595b34cad359eb47341448b0e6c438493602f15e923", 122954, "8ba17afc6fd6b0bc39c28348d8bce96c4e8ae1d45b7d3efe7bd6b55e5a445621"),
    "29" => (4578320, "7d604f9fc8b0a487ea2b5c76ee9ec4d41791db4dea1da55846201e219726553a", 309998, "436048dd89104376deeb27f98ff273f62c42d8a9c1b15ce922e0fa0160c22f0a"),
    "30" => (3453536, "574eaa293b86722bd13bf118fd6f08ea9276325b19b0eaf947eed3c43eca81a3", 142688, "bc5628a00f8b4c2b0e470aecf799ff8ee5a574ed55d3e125898f121da4d8f102"),
    "31" => (1144272, "575a8b4839fa8f12c4d23890bd5b4fe1c8940c21eb85c31d861dde12b83bbc58", 169286, "cc6ce9d690cb87fbc125d7013b0d1e72c395ce747dd8240464f2add387e9e23d"),
    "32" => (1294764, "e98f154c4106b235fbe43b6413a9a604676ec1966e392edf270ab70df4ae7e45", 38584, "9fff08328ef7b40212d39cfc38dfadf94beb93e2cc4ebdff1a3bf8d5feebd2f9"),
    "33" => (555652, "195e4ce2926054c85eedd5580b420838c9018282ae1e2cd73780063f9a987020", 29146, "a3e05b8d3f09b8bb30b95dff1db321e521e5cc162bc842bc0ce3c8ac5e5d5aae"),
    "34" => (4514976, "a048fb43cf2d5c46018055763232c6eb2657b67e093d60bd8f0525ed16b4ef38", 201032, "a11f5415ebbdeee58aec289672e8c09db74f5cbb49f72f11aebf245600b9c6cc"),
    "35" => (3593180, "814ae52a4fc6d28d88f742918cefcc52e7f165738d9def76f213d0e8097b0b8c", 151268, "a2fbf082bebb2c840dde8867d29af5652d3eb6b50e7f8172ec1cce14106295a4"),
    "36" => (5064820, "68169bdbd7254920d7389d29d3426a79f6d0f7baa697728a6891ac1ad80b6382", 370344, "a9273c11ad2bcc0a9e854c7f66a0f32dd15c09188c0cb3d610cbfd8f3bf6c504"),
    "37" => (12024084, "427dbb0c28f15d633ad524b1284f6681474bffe85587482baca78df7a7c5dc22", 222482, "aea908841e7c073f9fb57d0977a6db106a71f5689f13042b9a0a1272010e5682"),
    "38" => (817184, "8df8ed9888c9dbb4159f23ecef4d75b9234106776b2691c8a5062c2d169e3e05", 116662, "6c332554f46e6de6b274a9bd1b87d9e9cbdc84f2c910a9627a157df10526985e"),
    "39" => (5991548, "f427197d885f4991595f68a1c707a46cd7285772acf07269382284c6c835227e", 362336, "3e1c429a3cdf09806c2b874efdedc5ea6a0eb007a4a54c703d0455d600f3f68e"),
    "40" => (4700596, "a7a94f89add29c74b698c453e27f6ec39606e399b44a6ac426f30741b539823c", 241644, "e0982c642a9635cf13e12d42978ea1b5e3beda6fa781e2a9bde824fe8484ec78"),
    "41" => (3580848, "902e00862260bddf0ba103714a150ef3911c8580a6b6277c9ada3c7f69215335", 122382, "794e048ff51cced03def0806ddf6e69f8a3f2a95105d1a106b4409d14467f79c"),
    "42" => (6627008, "2e92082a22236df024aa0685906dc22ec1f2f813c3f92682d97e27a39d151bb4", 540514, "c176d5b0c236ee403ee5033e00cb1acf2d6dfa95c35ef73eaff5aff71d365860"),
    "44" => (440692, "395debc5ad86cecd890666e9565776a86fd3fb9945fdbc108bd7731539c15bd1", 10842, "84195a957958a8f90c3474874c9e6e42fc80f66ee6a5fc1d9f0ccdf656e55036"),
    "45" => (7535772, "566482a4b2e8740296d46d3aca12be246b479f3d55543992f48f19583926cb24", 136396, "63bfc5bb7321413f240a2ca37d0ccd3283d5acf749b0c3b680dee664d44fe667"),
    "46" => (1229648, "940343ce863b8970d0972088b3b3b34d0febd25b61d9e9deab88022c6466f386", 139542, "02f8f85d663933ed84914c0f07e77f6d3de59d02aa78f0dead98e0cbc41f38ad"),
    "47" => (7455916, "8435c25ac4238eb03df9a201f52a6ab509e7ce141d65279f5081f330c3b4beb2", 144690, "a34b0b85e4a48db541f796fd314dc67148f35dcd656bb1f078309b807ec03a12"),
    "48" => (14187700, "daea9c1613e0bedd4189a3bb93f0ba7897bd7a489443669e22d7126fc71ca489", 532506, "3eb89ee374c070eed311a01775817e539172b7fc0fc27dd904ee0d7d0cde1dd8"),
    "49" => (2449468, "089af7b33717e6dfd1291144237b217c09b3c0eadd50908079429970d05f2627", 95784, "2ae5ad72ddfb1abf779172f055a3d2f1d162b4c100a7c3a8c77bd58b7c23a9ac"),
    "50" => (858292, "ce292f9cd07ab331ab454e80f70c0d86acc31edfc056a2e099b942c9720d0512", 52026, "223f17c99dddc93bb124deb9bc9d8022235a4d718be5bc4ccd8cd2c467b01e9d"),
    "51" => (5798284, "b6481f1559119c95b0c15719a46d48225f95f2f79d37c35ad1a8cd304f269d88", 192738, "3a15a8427c79942b6164d5af02bbb85a50e3536591494905d8b41c4b4d2e9c37"),
    "53" => (4482592, "5d4ea48d0e4b18accc9042b1b7323da441f15b1e787a2b53a5d4d0c08cf27825", 183300, "c2d4b813e0df7a7128fed0b0883f92898e62871357d3aa3b79cefcb568cd385f"),
    "54" => (2377188, "08df53b1862c6221e8f7b094485bca744532001b66be5463502b5dd0816ceb59", 126100, "8878818b2d4a22daed6aa55acbfe167df108143d478bf85876825f7bf0d6198f"),
    "55" => (5400280, "c6c570bc4ab145d8448272c275e1ea3c7a40ca1005f7b8c7f6908c40c64acf49", 230490, "a02f9dcf7e04ed5c5785be70c6d3fec726664f1fc33fe5a03b920908a4cf461e"),
    "56" => (1423944, "ddfab0bb1b75eda5f368d969d839eed76dbe91723e39e1875fbeafbd6aa7a7b8", 59176, "22816ba7fb6db9f31fc3bef8fc2672e3f1bae5a54e8161a5ca035804f4ff747e"),
    "72" => (1121880, "aa88ca0bf2ae6ad1905d01a1ff5953db30dc7771dfd48a1027891dbd6fd800be", 84058, "8d54b0210a2b8f185ec13b1876b0487fbf85d1649b863e39a013c8275258f2e7"),
)

# ---- reading, Base Julia only ------------------------------------------------------------------------------------
be32(v, i) = Int(ntoh(reinterpret(Int32, v[i:i+3])[1]))         # i is 1-based
le32(v, i) = Int(ltoh(reinterpret(Int32, v[i:i+3])[1]))
le16(v, i) = Int(ltoh(reinterpret(UInt16, v[i:i+1])[1]))
lef64(v, i) = ltoh(reinterpret(Float64, v[i:i+7])[1])

function checked(path, bytes, sha)
    filesize(path) == bytes || error("$path: $(filesize(path)) bytes, not $bytes")
    b = read(path)
    h = bytes2hex(sha256(b))
    h == sha || error("$path: SHA-256 $h, not $sha")
    return b
end

# the polygon boxes of a .shp, in record order: (Xmin, Ymin, Xmax, Ymax)
function shpboxes(shp, path)
    be32(shp, 1) == 9994 || error("$path: file code $(be32(shp, 1)), not 9994")
    2 * be32(shp, 25) == length(shp) || error("$path: the header's length is not the file's")
    le32(shp, 29) == 1000 || error("$path: version $(le32(shp, 29)), not 1000")
    le32(shp, 33) == 5 || error("$path: shape type $(le32(shp, 33)), not 5 (polygon)")
    boxes = NTuple{4, Float64}[]
    p = 101
    while p <= length(shp)
        recno, clen = be32(shp, p), be32(shp, p + 4)
        recno == length(boxes) + 1 || error("$path: record $recno where $(length(boxes) + 1) was expected")
        t = le32(shp, p + 8)
        t == 5 || error("STOP: $path: record $recno has shape type $t, not 5 (a polygon)")
        b = (lef64(shp, p + 12), lef64(shp, p + 20), lef64(shp, p + 28), lef64(shp, p + 36))
        (all(isfinite, b) && b[1] <= b[3] && b[2] <= b[4]) || error("$path: record $recno's box is $b")
        push!(boxes, b)
        p += 8 + 2clen
    end
    p == length(shp) + 1 || error("$path: the last record runs past the end")
    return boxes
end

# the named text fields of a .dbf, in record order
function dbffields(dbf, path, want)
    dbf[1] == 0x03 || error("$path: dBASE version byte $(dbf[1]), not 3")
    nrec = Int(ltoh(reinterpret(UInt32, dbf[5:8])[1]))
    hlen, rlen = le16(dbf, 9), le16(dbf, 11)
    names, lens = String[], Int[]
    p = 33
    while dbf[p] != 0x0d
        push!(names, rstrip(String(dbf[p:p+10]), '\0'))
        push!(lens, Int(dbf[p+16]))
        p += 32
    end
    p == hlen || error("$path: the field descriptors end at $p, not at the header's length $hlen")
    1 + sum(lens) == rlen || error("$path: the fields do not fill a record")
    start = cumsum([2; lens])[1:end-1]                  # each field's first byte in a record (byte 1 is the flag)
    out = Dict(n => Vector{String}(undef, nrec) for n in want)
    for r in 1:nrec
        o = hlen + (r - 1) * rlen
        dbf[o + 1] == UInt8(' ') || error("$path: record $r is marked deleted")
        for n in want
            k = findfirst(==(n), names)
            k === nothing && error("$path: no field $n")
            out[n][r] = strip(String(dbf[o+start[k]:o+start[k]+lens[k]-1]))
        end
    end
    length(dbf) in (hlen + nrec * rlen, hlen + nrec * rlen + 1) || error("$path: $(length(dbf)) bytes, not its records'")
    return out, nrec
end

function main(dir, out = DATA)
    isdir(out) || mkpath(out)
    # 1. read every file
    tiger = Dict{Tuple{Int, Int}, NTuple{4, Float64}}()
    intpt = Dict{Tuple{Int, Int}, NTuple{2, Float64}}()
    for code in sort!(collect(keys(INPUTS)))
        sb, ss, db, ds = INPUTS[code]
        shpp = joinpath(dir, "tl_2020_$(code)_place.shp")
        dbfp = joinpath(dir, "tl_2020_$(code)_place.dbf")
        boxes = shpboxes(checked(shpp, sb, ss), shpp)
        f, n = dbffields(checked(dbfp, db, ds), dbfp, ("STATEFP", "PLACEFP", "INTPTLON", "INTPTLAT"))
        n == length(boxes) || error("$code: $n .dbf records, $(length(boxes)) .shp records")
        for r in 1:n
            f["STATEFP"][r] == code || error("$code: record $r has STATEFP $(f["STATEFP"][r])")
            occursin(r"^\d{5}$", f["PLACEFP"][r]) || error("$code: record $r has PLACEFP $(f["PLACEFP"][r])")
            k = (parse(Int, code), parse(Int, f["PLACEFP"][r]))
            haskey(tiger, k) && error("$code: the key $k repeats")
            tiger[k] = boxes[r]
            intpt[k] = (parse(Float64, f["INTPTLON"][r]), parse(Float64, f["INTPTLAT"][r]))
        end
    end
    println("TIGER/Line 2020 places read: ", length(tiger), " in ", length(INPUTS), " files")

    # 2. every usplace() key must be a 2020 place
    p = usplace()
    keys_lj = [(Int(s), Int(q)) for (s, q) in zip(p.STFIP, p.PLFIP)]
    length(unique(keys_lj)) == length(keys_lj) || error("usplace() has a repeated key")
    missing_keys = [k for k in keys_lj if !haskey(tiger, k)]
    println("usplace() rows: ", length(keys_lj), "; keys matched in the files: ", length(keys_lj) - length(missing_keys),
            "; missing: ", length(missing_keys))
    isempty(missing_keys) || error("STOP: usplace() keys that are not 2020 places in the files: $missing_keys")
    extra = setdiff(keys(tiger), Set(keys_lj))
    bystate = Dict{Int, Int}()
    for k in extra
        bystate[k[1]] = get(bystate, k[1], 0) + 1
    end
    println("TIGER places Logjam does not carry: ", length(extra), " (",
            join(["$(lpad(s, 2, '0')): $(bystate[s])" for s in sort!(collect(keys(bystate)))], ", "), ")")

    # 3. the report: usplace()'s point against the Census interior point, and in its box
    dmax, kmax = 0.0, keys_lj[1]
    outside = Tuple{Int, Int}[]
    for (i, k) in enumerate(keys_lj)
        d = max(abs(p.LON[i] - intpt[k][1]), abs(p.LAT[i] - intpt[k][2]))
        d > dmax && ((dmax, kmax) = (d, k))
        b = tiger[k]
        (b[1] <= p.LON[i] <= b[3] && b[2] <= p.LAT[i] <= b[4]) || push!(outside, k)
    end
    @printf("usplace() point against the Census interior point: largest difference %.3g degrees (%s)\n", dmax, kmax)
    println("usplace() points outside their place's box: ", length(outside), isempty(outside) ? "" : " $outside")

    # 4. the table, sorted by key
    ks = sort(keys_lj)
    df = DataFrame(STFIP = Int64[k[1] for k in ks], PLFIP = Int64[k[2] for k in ks],
                   LONmin = Float64[tiger[k][1] for k in ks], LONmax = Float64[tiger[k][3] for k in ks],
                   LATmin = Float64[tiger[k][2] for k in ks], LATmax = Float64[tiger[k][4] for k in ks])
    io = IOBuffer()
    CSV.write(io, df)
    b = take!(io)
    count(==(UInt8('\r')), b) == 0 || error("CR in the CSV")
    back = CSV.read(IOBuffer(copy(b)), DataFrame; ntasks = 1)
    names(back) == names(df) || error("the CSV's names read back changed")
    for n in names(df)
        eltype(back[!, n]) == eltype(df[!, n]) || error("column $n reads back as $(eltype(back[!, n]))")
        all(back[!, n] .=== df[!, n]) || error("column $n does not read back as the .shp's values")
    end
    csvp, jlsp = joinpath(out, "usplacebox.csv"), joinpath(out, "usplacebox.jls")
    write(csvp, b)
    serialize(jlsp, back)
    j = open(deserialize, jlsp)
    (isequal(j, back) && eltype.(eachcol(j)) == eltype.(eachcol(back))) || error("the .jls does not read back")
    @printf("wrote usplacebox.csv  %d rows  %d bytes  sha256 %s\n", nrow(df), length(b), bytes2hex(sha256(b)))
    @printf("wrote usplacebox.jls             %d bytes  sha256 %s\n", filesize(jlsp), bytes2hex(open(sha256, jlsp)))
    r = only(findall((df.STFIP .== 37) .& (df.PLFIP .== 55000)))
    println("Raleigh (37, 55000): LON ", (df.LONmin[r], df.LONmax[r]), "  LAT ", (df.LATmin[r], df.LATmax[r]))
end

length(ARGS) in (1, 2) || error("usage: make_placebox.jl <shapefile directory> [<output directory>]")
main(ARGS...)
