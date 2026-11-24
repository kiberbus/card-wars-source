extends RefCounted

const TEXT := {
	"ancient_scholar": {
		"en": "FLOOP >>> Return a random Rainbow card from your discard pile to your hand. If you have a building in this lane, gain 1 action.",
		"ko": "플룹 >>> 내 버림 더미에서 무작위 무지개 카드 한 장을 손으로 되돌려. 이 구역에 내 건물이 있다면 행동 1개를 얻어.",
	},
	"archer_dan": {
		"en": "FLOOP >>> Destroy a chosen building in the lane of Лучника Дэна.",
		"ko": "플룹 >>> Лучника Дэна의 구역에 있는 건물 하나를 선택해 파괴해.",
	},
	"big_foot": {
		"en": "FLOOP >>> Turn a chosen face-down land you control face up.",
		"ko": "플룹 >>> 내가 지배하는 뒤집힌 땅 하나를 선택해 앞면으로 돌려.",
	},
	"blood_fortress": {
		"en": "Your creature in this lane gets +1 attack.",
		"ko": "이 구역에 있는 내 생물의 공격력이 1 올라가.",
	},
	"celestial_castle": {
		"en": "Your creature in this lane gets +3 defense.",
		"ko": "이 구역에 있는 내 생물의 방어력이 3 올라가.",
	},
	"cerebral_bloodstorm": {
		"en": "Deal 1 damage to each opposing creature.",
		"ko": "상대의 모든 생물에게 피해 1을 줘.",
	},
	"cool_dog": {
		"en": "Your creatures in adjacent lanes cannot be attacked.",
		"ko": "인접한 구역에 있는 내 생물은 공격받지 않아.",
	},
	"corn_dog": {
		"en": "Кукутузик gets +1 defense for each Cornfield you control. If you have 3 or fewer Cornfields, Кукутузик gets +1 attack.",
		"ko": "Кукутузик은 내가 지배하는 옥수수밭마다 방어력 +1을 얻어. 내 옥수수밭이 3개 이하라면 Кукутузик은 공격력 +1을 얻어.",
	},
	"corn_lord": {
		"en": "+1 attack for each of your other Corn creatures.",
		"ko": "내 다른 옥수수 생물마다 공격력 +1.",
	},
	"corn_ronin": {
		"en": "+1 attack for each adjacent Cornfield.",
		"ko": "인접한 옥수수밭마다 공격력 +1.",
	},
	"corn_scepter": {
		"en": "Deal 1 damage to a chosen creature for each Cornfield you control.",
		"ko": "내가 지배하는 옥수수밭마다 선택한 생물에게 피해 1을 줘.",
	},
	"cornataur": {
		"en": "When Зернотавр enters play, deal 1 damage to your opponent for each Cornfield you control.",
		"ko": "Зернотавр가 등장하면 내가 지배하는 옥수수밭마다 상대에게 피해 1을 줘.",
	},
	"cross_pollination": {
		"en": "Each of your Corn creatures gets +1 attack this turn for each land type you control.",
		"ko": "이번 턴에 내 각 옥수수 생물은 내가 지배하는 땅의 종류마다 공격력 +1을 얻어.",
	},
	"dragon_claw": {
		"en": "FLOOP >>> Move one of your creatures to an empty lane.",
		"ko": "플룹 >>> 내 생물 하나를 빈 구역으로 옮겨.",
	},
	"drooling_dude": {"en": "", "ko": ""},
	"embarrassing_bard": {
		"en": "FLOOP >>> Draw a card for each of your flooped creatures, including this one.",
		"ko": "플룹 >>> 이 생물을 포함해 내 플룹된 생물마다 카드 한 장을 뽑아.",
	},
	"evil_eye": {"en": "", "ko": ""},
	"field_of_nightmares": {
		"en": "Deal 1 damage to your opponent for each card in their hand.",
		"ko": "상대의 손에 있는 카드마다 상대에게 피해 1을 줘.",
	},
	"field_reaper": {
		"en": "To play this card, discard a card. When Жнец enters play, move a chosen creature from this lane to an adjacent empty lane you control.",
		"ko": "이 카드를 사용하려면 카드 한 장을 버려. Жнец이 등장하면 이 구역의 생물 하나를 선택해 내가 지배하는 인접한 빈 구역으로 옮겨.",
	},
	"field_stalker": {
		"en": "At the start of your turn, each player draws a card.",
		"ko": "내 턴 시작에 각 플레이어는 카드 한 장을 뽑아.",
	},
	"gnome_snot": {
		"en": "Draw 3 cards.",
		"ko": "카드 3장을 뽑아.",
	},
	"heavenly_gazer": {
		"en": "FLOOP >>> Put a spell from your discard pile on top of your deck.",
		"ko": "플룹 >>> 내 버림 더미의 주문 카드 한 장을 내 덱 맨 위에 놓아.",
	},
	"husker_knight": {
		"en": "+1 attack and +2 defense for each Cornfield you control.",
		"ko": "내가 지배하는 옥수수밭마다 공격력 +1, 방어력 +2.",
	},
	"husker_worm": {
		"en": "When Шаи-Кукуруз enters play, flip one of your Cornfields.",
		"ko": "Шаи-Кукуруз가 등장하면 내 옥수수밭 하나를 뒤집어.",
	},
	"legion_of_earlings": {
		"en": "When Легион початочков enters play, you may return a chosen creature in this lane to its owner's hand.",
		"ko": "Легион початочков이 등장하면 이 구역의 생물 하나를 선택해 그 소유자의 손으로 되돌릴 수 있어.",
	},
	"nice_ice_baby": {
		"en": "+3 attack while your opponent has no creature in this lane.",
		"ko": "이 구역에 상대 생물이 없는 동안 공격력 +3.",
	},
	"patchy_pumpkin": {
		"en": "FLOOP >>> Deal 1 damage to a chosen creature. Do this once for each Cornfield you have. (Each creature may only be chosen once.)",
		"ko": "플룹 >>> 선택한 생물에게 피해 1을 줘. 내 옥수수밭마다 한 번씩 이 효과를 적용해. (각 생물은 한 번만 선택할 수 있어.)",
	},
	"phyllis": {"en": "", "ko": ""},
	"psionic_architect": {
		"en": "When Архитектор разума enters play, you may prepare one of your flooped creatures.",
		"ko": "Архитектор разума가 등장하면 내 플룹된 생물 하나를 준비시킬 수 있어.",
	},
	"punk_cat": {
		"en": "Each creature that changed lanes this turn gets +2 attack.",
		"ko": "이번 턴에 구역을 옮긴 모든 생물의 공격력이 2 올라가.",
	},
	"reclaim_landscape": {
		"en": "You may turn one of your lands face up and move one of your buildings to any lane you control without a building.",
		"ko": "내 땅 하나를 앞면으로 돌리고 내 건물 하나를 내가 지배하는 건물이 없는 구역으로 옮길 수 있어.",
	},
	"schoolhouse": {
		"en": "FLOOP >>> Until the end of the turn, your creature in this lane loses all abilities and gains the FLOOP ability of a random creature with a FLOOP ability from your discard pile.",
		"ko": "플룹 >>> 턴이 끝날 때까지 이 구역의 내 생물은 모든 능력을 잃고, 내 버림 더미에서 플룹 능력이 있는 무작위 생물 하나의 플룹 능력을 얻어.",
	},
	"silo_of_truth": {
		"en": "Spend 2 actions >>> Steal a random card from your opponent's hand and play it for free.",
		"ko": "행동 2개 사용 >>> 상대의 손에서 무작위 카드 한 장을 훔쳐 비용 없이 사용해.",
	},
	"spirit_soldier": {
		"en": "Each adjacent creature gets +1 attack.",
		"ko": "인접한 모든 생물의 공격력이 1 올라가.",
	},
	"struzann_jinn": {
		"en": "+2 attack for each of your flooped creatures.",
		"ko": "내 플룹된 생물마다 공격력 +2.",
	},
	"teleport": {
		"en": "Move one of your creatures to one of your empty lands.",
		"ko": "내 생물 하나를 내 빈 땅 하나로 옮겨.",
	},
	"the_pig": {
		"en": "FLOOP >>> Flip a chosen Cornfield in this lane.",
		"ko": "플룹 >>> 이 구역의 옥수수밭 하나를 선택해 뒤집어.",
	},
	"travelin_farmer": {
		"en": "When Фермер-покатун leaves play, deal 1 damage to your opponent for each card in their hand.",
		"ko": "Фермер-покатун이 게임에서 나가면 상대의 손에 있는 카드마다 상대에게 피해 1을 줘.",
	},
	"uni_knight": {
		"en": "Spend 1 action >>> A chosen creature in this lane gets −10 attack this turn.",
		"ko": "행동 1개 사용 >>> 이 구역에서 선택한 생물은 이번 턴에 공격력 −10을 얻어.",
	},
	"wall_of_ears": {
		"en": "+1 defense for each Cornfield in play, including all players' Cornfields.",
		"ko": "모든 플레이어의 옥수수밭을 포함해 게임 중인 옥수수밭마다 방어력 +1.",
	},
	"woad_blood": {
		"en": "Each creature that changed lanes this turn gets +2 attack.",
		"ko": "이번 턴에 구역을 옮긴 모든 생물의 공격력이 2 올라가.",
	},
	"woad_mobile_home": {
		"en": "FLOOP >>> Move a creature from an adjacent lane to this lane, if it is empty.",
		"ko": "플룹 >>> 이 구역이 비어 있다면 인접한 구역의 생물 하나를 이 구역으로 옮겨.",
	},
	"woad_talisman": {
		"en": "A chosen Plains creature you control gets +2 attack this turn.",
		"ko": "내가 지배하는 선택한 평원 생물은 이번 턴에 공격력 +2를 얻어.",
	},
	"woadic_chief": {
		"en": "+2 attack for each spell you played this turn.",
		"ko": "이번 턴에 내가 사용한 주문마다 공격력 +2.",
	},
	"woadic_marauder": {
		"en": "When Синюшный злопыхатель changes lanes during a turn, draw a card.",
		"ko": "Синюшный злопыхатель이 턴 중에 구역을 옮기면 카드 한 장을 뽑아.",
	},
}
