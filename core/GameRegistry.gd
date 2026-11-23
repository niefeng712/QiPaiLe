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
		"desc": "3人，叫分1~3分抢地主，地主多拿3张底牌，一打二。炸弹、王炸翻倍，春天/反春翻倍。可选经典洗牌、不洗牌（炸弹多）、癞子玩法；人不够时自动补电脑。",
		"logic": "res://games/doudizhu/DoudizhuLogic.gd",
		"view": "res://games/doudizhu/DoudizhuView.gd",
		"rules": [
			{"key": "deal", "label": "发牌方式", "default": "shuffle",
				"options": [["shuffle", "经典（洗牌）"], ["noshuffle", "不洗牌（炸弹多）"]]},
			{"key": "laizi", "label": "癞子", "default": "off",
				"options": [["off", "不用癞子"], ["on", "癞子玩法（随机一个点数当万能牌）"]]},
			{"key": "cap", "label": "封顶倍数", "default": "none",
				"options": [["none", "不封顶"], ["16", "16倍"], ["32", "32倍"], ["64", "64倍"]]},
		],
	},
	{"id": "tuolaji", "name": "升级拖拉机", "ready": false, "desc": "双副牌升级，第二阶段上线。"},
	{"id": "mahjong", "name": "麻将", "ready": false, "desc": "血战到底 / 推倒胡 / 国标等各地玩法，第三阶段上线。"},
	{"id": "checkers", "name": "中国跳棋", "ready": false, "desc": "2/3/4/6人跳棋，第三阶段上线。"},
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
	return out
