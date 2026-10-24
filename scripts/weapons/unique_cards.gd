extends RefCounted
## Catalog of the golden, one-time weapon cards.
##
## A card only enters the level-up pool after the run has taken three normal
## weapon upgrades. The effects themselves live in weapon.gd and are switched on
## by grant_unique().

const GOLD := Color(1.0, 0.79, 0.26, 1.0)

## Transparent weapon renders used as the label-free seal entry card.
const ICONS := {
	0: "res://assets/ui/seals/revolver.png",
	1: "res://assets/ui/seals/shotgun.png",
	2: "res://assets/ui/seals/akm.png",
	3: "res://assets/ui/seals/svd.png",
	4: "res://assets/ui/seals/rpd.png",
	5: "res://assets/ui/seals/saiga.png",
	6: "res://assets/ui/seals/mp9.png",
}

const BY_WEAPON := {
	0: [ # Revolver
		{
			"perk": "revolver_heat",
			"title": "Горящий крест",
			"tag": "уникальное",
			"desc": "Каждый хэдшот: +5% урона и +4% темпа (до 10 стаков).\nКрест над прицелом разгорается ярче. Гаснет через 3 с без хэдшота.",
		},
		{
			"perk": "revolver_blast",
			"title": "Пороховая печать",
			"tag": "уникальное",
			"desc": "Убийство в голову вызывает взрыв.\nУрон по площади — 1/3 базового урона, радиус 5 м.",
		},
	],
	1: [ # Double barrel
		{
			"perk": "shotgun_knockback",
			"title": "Кувалда",
			"tag": "уникальное",
			"desc": "Разброс +60%, зато каждый выстрел\nотбрасывает стрелка назад и подкидывает.",
		},
	],
	2: [ # AKM
		{
			"perk": "akm_lifesteal",
			"title": "Кровавый ручей",
			"tag": "уникальное",
			"desc": "5% нанесённого урона возвращается здоровьем.\nНе спасает от огня перегрева.",
		},
		{
			"perk": "akm_kill_heat",
			"title": "Перегрев",
			"tag": "уникальное",
			"desc": "Каждое убийство: +8% темпа и +6% скорости перезарядки.\nДержится 3 с. С 6 стаков АКМ начинает жечь стрелка.",
		},
	],
	3: [ # SVD
		{
			"perk": "svd_pierce",
			"title": "Бронебойный",
			"tag": "уникальное",
			"desc": "Пуля проходит сквозь врагов —\nдо 8 целей за один выстрел.",
		},
		{
			"perk": "svd_headshot",
			"title": "Азарт охотника",
			"tag": "уникальное",
			"desc": "Каждый хэдшот: +8% темпа (до 10 стаков).\nСброс: 3 с без хэдшота, промах или перезарядка.",
		},
	],
	4: [ # RPD
		{
			"perk": "rpd_heavy_caliber",
			"title": "Тяжёлый калибр",
			"tag": "уникальное",
			"desc": "Урон +20%, но ход с пулемётом\nпадает до 65%.",
		},
	],
	5: [ # Saiga-12K
		{
			"perk": "saiga_burst_pierce",
			"title": "Сдвоенный залп",
			"tag": "уникальное",
			"desc": "Темп как у АКМ: два быстрых выстрела за клик.\nКаждая дробинка пробивает врагов насквозь.",
		},
	],
	6: [ # MP9
		{
			"perk": "mp9_swarm",
			"title": "Свинцовый рой",
			"tag": "уникальное",
			"desc": "Темп +25% и магазин +20%.\nСвинец не кончается.",
		},
	],
}


## Returns fresh copies so the UI can freely annotate cards.
static func for_weapon(index: int) -> Array[Dictionary]:
	var cards: Array[Dictionary] = []
	for card in BY_WEAPON.get(index, []):
		cards.append((card as Dictionary).duplicate(true))
	return cards


static func icon_for(index: int) -> String:
	return String(ICONS.get(index, ""))
