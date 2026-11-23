extends RefCounted
## 游戏注册表：大厅里显示的所有游戏。新增游戏时在这里登记即可。
## 每个已上线游戏需要：
##   logic 脚本（房主端运行规则）：setup / apply / get_state / current_seat / is_over / bot_action / bot_delay
##   view  脚本（各端显示界面）：update_state / status_text

const GAMES = [
	{
		"id": "gomoku",
		"name": "五子棋",
		"ready": true,
		"seats": 2,
		"min_players": 2,
		"desc": "15×15 棋盘，黑白轮流落子，横、竖、斜任意方向先连成五子者获胜（无禁手）。",
		"logic": "res://games/gomoku/GomokuLogic.gd",
		"view": "res://games/gomoku/GomokuView.gd",
		"rules": [
			{"key": "first", "label": "执黑先手", "default": "alternate",
				"options": [["alternate", "每局轮换"], ["seat0", "座位1执黑"], ["random", "随机"]]},
		],
	},
	{
		"id": "ludo",
		"name": "飞行棋",
		"ready": true,
		"seats": 4,
		"min_players": 2,
		"desc": "2～4人，红黄蓝绿四色飞机。掷出6起飞，掷6可再掷一次；落在同色格可跳4格；踩到别人的飞机会把它撞回老家。四架飞机全部到达终点获胜。",
		"logic": "res://games/ludo/LudoLogic.gd",
		"view": "res://games/ludo/LudoView.gd",
		"rules": [
			{"key": "takeoff", "label": "起飞点数", "default": "6",
				"options": [["6", "只有6能起飞"], ["56", "5或6都能起飞"]]},
			{"key": "jump", "label": "同色跳跃", "default": "on",
				"options": [["on", "开启（同色格前进4格）"], ["off", "关闭"]]},
			{"key": "over", "label": "终点规则", "default": "bounce",
				"options": [["bounce", "超出终点要回弹"], ["free", "超出也算到达"]]},
		],
	},
	{
		"id": "doudizhu",
		"name": "斗地主",
		"ready": true,
		"seats": 3,
		"min_players": 3,
		"desc": "3人，一副牌。叫地主/抢地主或叫分，地主多拿3张底牌，一打二。可选明牌、加倍、记牌器、出牌倒计时；经典洗牌、不洗牌（炸弹多）、癞子玩法。炸弹、王炸、春天翻倍；人不够自动补电脑。",
		"logic": "res://games/doudizhu/DoudizhuLogic.gd",
		"view": "res://games/doudizhu/DoudizhuView.gd",
		"fixed": {"players": "3"},
		"rules": [
			{"key": "deal", "label": "发牌方式", "default": "shuffle",
				"options": [["shuffle", "经典（洗牌）"], ["noshuffle", "不洗牌（炸弹多）"]]},
			{"key": "laizi", "label": "癞子", "default": "off",
				"options": [["off", "不用癞子"], ["on", "癞子玩法（随机一个点数当万能牌）"]]},
			{"key": "bidmode", "label": "叫地主方式", "default": "rob",
				"options": [["rob", "叫地主 / 抢地主（每抢×2）"], ["score", "叫分（1~3分）"]]},
			{"key": "double", "label": "加倍", "default": "on",
				"options": [["on", "开启（农民×2，地主可超级加倍×4）"], ["off", "关闭"]]},
			{"key": "mingpai", "label": "明牌", "default": "on",
				"options": [["on", "开启（明牌开始×5，地主明牌×2）"], ["off", "关闭"]]},
			{"key": "counter", "label": "记牌器", "default": "on",
				"options": [["on", "开启"], ["off", "关闭"]]},
			{"key": "timer", "label": "出牌倒计时", "default": "20",
				"options": [["20", "20秒"], ["15", "15秒"], ["30", "30秒"], ["off", "不限时"]]},
			{"key": "cap", "label": "封顶倍数", "default": "none",
				"options": [["none", "不封顶"], ["16", "16倍"], ["32", "32倍"], ["64", "64倍"]]},
		],
	},
	{
		"id": "doudizhu4",
		"name": "四人斗地主",
		"ready": true,
		"seats": 4,
		"min_players": 4,
		"desc": "4人，两副牌（108张），每人25张，地主多拿8张底牌，一个地主打三个农民。炸弹4~8张，张数多的大；四张王是天王炸最大；两张同样的王算对子。人不够自动补电脑。",
		"logic": "res://games/doudizhu/DoudizhuLogic.gd",
		"view": "res://games/doudizhu/DoudizhuView.gd",
		"fixed": {"players": "4", "laizi": "off"},
		"rules": [
			{"key": "deal", "label": "发牌方式", "default": "shuffle",
				"options": [["shuffle", "经典（洗牌）"], ["noshuffle", "不洗牌（炸弹多）"]]},
			{"key": "bidmode", "label": "叫地主方式", "default": "rob",
				"options": [["rob", "叫地主 / 抢地主（每抢×2）"], ["score", "叫分（1~3分）"]]},
			{"key": "double", "label": "加倍", "default": "on",
				"options": [["on", "开启（农民×2，地主可超级加倍×4）"], ["off", "关闭"]]},
			{"key": "mingpai", "label": "明牌", "default": "on",
				"options": [["on", "开启（明牌开始×5，地主明牌×2）"], ["off", "关闭"]]},
			{"key": "counter", "label": "记牌器", "default": "on",
				"options": [["on", "开启"], ["off", "关闭"]]},
			{"key": "timer", "label": "出牌倒计时", "default": "20",
				"options": [["20", "20秒"], ["15", "15秒"], ["30", "30秒"], ["off", "不限时"]]},
			{"key": "cap", "label": "封顶倍数", "default": "none",
				"options": [["none", "不封顶"], ["16", "16倍"], ["32", "32倍"], ["64", "64倍"]]},
		],
	},
	{
		"id": "tuolaji",
		"name": "升级拖拉机",
		"ready": true,
		"seats": 4,
		"min_players": 4,
		"desc": "4人两副牌，对家一伙（座位1、3 对 座位2、4）。亮级牌定主（一对可以反主，一对王是无主），庄家拿8张底牌再扣底；跟牌要跟花色、跟对子、跟拖拉机；可以甩牌。闲家抓够80分上台，抠底翻倍；从2打起，先打过A的一方赢。人不够自动补电脑。",
		"logic": "res://games/tuolaji/TuolajiLogic.gd",
		"view": "res://games/tuolaji/TuolajiView.gd",
		"rules": [
			{"key": "throw", "label": "甩牌", "default": "on",
				"options": [["on", "允许甩牌（甩不成要退回最小的一手）"], ["off", "不允许甩牌"]]},
			{"key": "bottom", "label": "抠底翻倍", "default": "size",
				"options": [["size", "按最后一手牌型（单×2、对×4、拖拉机更多）"], ["2", "固定×2"]]},
			{"key": "timer", "label": "出牌倒计时", "default": "30",
				"options": [["30", "30秒"], ["20", "20秒"], ["off", "不限时"]]},
		],
	},
	{
		"id": "xuezhan",
		"name": "血战到底",
		"ready": true,
		"seats": 4,
		"min_players": 4,
		"desc": "四川麻将。108张（只有万条筒），不能吃，可以碰杠。开局换三张、定缺（缺的那门要先打完才能胡）。一家胡了不结束，其他人接着打，直到三家胡牌或牌摸完；摸完时查花猪、查大叫。番型：对对胡、清一色、七对、龙七对、金钩钓、根、杠上花、杠上炮、抢杠胡、海底、自摸。杠分立即结算（刮风下雨）。",
		"logic": "res://games/mahjong/MahjongLogic.gd",
		"view": "res://games/mahjong/MahjongView.gd",
		"fixed": {"mode": "xuezhan"},
		"rules": [
			{"key": "huan", "label": "换三张", "default": "on",
				"options": [["on", "开启"], ["off", "关闭"]]},
			{"key": "cap", "label": "封顶", "default": "4",
				"options": [["3", "3番（8倍）"], ["4", "4番（16倍）"], ["5", "5番（32倍）"], ["none", "不封顶"]]},
			{"key": "timer", "label": "出牌倒计时", "default": "20",
				"options": [["20", "20秒"], ["15", "15秒"], ["30", "30秒"], ["off", "不限时"]]},
		],
	},
	{
		"id": "tuidao",
		"name": "广东推倒胡",
		"ready": true,
		"seats": 4,
		"min_players": 4,
		"desc": "广东麻将。136张，不能吃，可以碰杠。可选只能自摸或可以点炮（抢杠胡都可以），可选买马（摸到1、5、9、东、中算中马，每中一匹多赢一份）。有人胡就结束。番型：鸡胡、对对胡、混一色、清一色、字一色、七对、十三幺、杠上开花、抢杠胡、海底。",
		"logic": "res://games/mahjong/MahjongLogic.gd",
		"view": "res://games/mahjong/MahjongView.gd",
		"fixed": {"mode": "tuidao"},
		"rules": [
			{"key": "pao", "label": "胡牌方式", "default": "zimo",
				"options": [["zimo", "只能自摸（抢杠胡除外）"], ["pao", "可以点炮"]]},
			{"key": "ma", "label": "买马", "default": "4",
				"options": [["0", "不买马"], ["2", "买2匹"], ["4", "买4匹"], ["6", "买6匹"]]},
			{"key": "cap", "label": "封顶", "default": "5",
				"options": [["3", "3番（8倍）"], ["4", "4番（16倍）"], ["5", "5番（32倍）"], ["none", "不封顶"]]},
			{"key": "timer", "label": "出牌倒计时", "default": "20",
				"options": [["20", "20秒"], ["15", "15秒"], ["30", "30秒"], ["off", "不限时"]]},
		],
	},
	{
		"id": "dazhong",
		"name": "大众麻将",
		"ready": true,
		"seats": 4,
		"min_players": 4,
		"desc": "最常见的打法。136张，能吃（只能吃上家）、碰、杠，可以点炮，有人胡就结束。番型：平胡、门清、对对胡、混一色、清一色、字一色、七对、十三幺、杠上开花、杠上炮、抢杠胡、海底、自摸。",
		"logic": "res://games/mahjong/MahjongLogic.gd",
		"view": "res://games/mahjong/MahjongView.gd",
		"fixed": {"mode": "dazhong"},
		"rules": [
			{"key": "cap", "label": "封顶", "default": "4",
				"options": [["3", "3番（8倍）"], ["4", "4番（16倍）"], ["5", "5番（32倍）"], ["none", "不封顶"]]},
			{"key": "timer", "label": "出牌倒计时", "default": "20",
				"options": [["20", "20秒"], ["15", "15秒"], ["30", "30秒"], ["off", "不限时"]]},
		],
	},
	{
		"id": "checkers",
		"name": "中国跳棋",
		"ready": true,
		"seats": 6,
		"min_players": 2,
		"counts": [2, 3, 4, 6],
		"offline_seats": 2,
		"desc": "2、3、4、6人（5人时自动补一个电脑）。六角星棋盘，把自己的棋子全部移到正对面的角。可以走一步到相邻空位，也可以跳过一颗棋子，能连续跳。进了终点的棋子不能再出来；自己的棋子全部进入终点就算到达（如果终点被别人的棋子堵住，60轮后终点填满且有自己的棋子也算到达）。单机默认和1个电脑下，想多人在房间里把空位设为电脑。",
		"logic": "res://games/checkers/CheckersLogic.gd",
		"view": "res://games/checkers/CheckersView.gd",
		"rules": [
			{"key": "jump", "label": "跳法", "default": "adjacent",
				"options": [["adjacent", "相邻跳（只能跳过紧挨着的棋子）"], ["far", "隔空跳（棋子在正中间就能远跳）"]]},
			{"key": "pieces", "label": "棋子数", "default": "10",
				"options": [["10", "每人10颗（标准）"], ["6", "每人6颗（快速）"]]},
			{"key": "end", "label": "结束方式", "default": "first",
				"options": [["first", "有人全部到达就结束"], ["all", "排出全部名次"]]},
			{"key": "timer", "label": "走棋倒计时", "default": "off",
				"options": [["off", "不限时"], ["30", "30秒"], ["60", "60秒"]]},
		],
	},
	{"id": "xiangqi", "name": "中国象棋", "ready": false, "desc": "后续上线。"},
	{"id": "junqi", "name": "四国军棋", "ready": false, "desc": "后续上线。"},
	{"id": "lianliankan", "name": "连连看", "ready": false, "desc": "后续上线。"},
]


static func get_game(id: String) -> Dictionary:
	for g in GAMES:
		if str(g["id"]) == id:
			return g
	return {}


static func default_rules(id: String) -> Dictionary:
	var out = {}
	var g = get_game(id)
	for r in g.get("rules", []):
		out[str(r["key"])] = str(r["default"])
	var fixed = g.get("fixed", {})
	for k in fixed:
		out[str(k)] = str(fixed[k])
	return out
