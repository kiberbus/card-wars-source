extends RefCounted

const TEXT := {
	"en": {
		"next": "Next",
		"rules_title": "Rules",
		"rules_back": "Back",
		"rules_desktop_controls": "Right-click to inspect any face-up card. Space speeds up animations. F11 toggles full screen. Esc opens the menu.",
		"rules_mobile_controls": "Hold a finger on a face-up card to inspect it. The Back button opens the menu.",
		"rules_body": """[b][color=#ffd75a]Goal.[/color][/b] Reduce your opponent's health from 25 to 0.

[b][color=#ffd75a]Heroes and decks.[/color][/b] Before the game, each player chooses a hero: their deck has 40 cards and 4 lands. Land types are Blue Plains, Cornfields, NiceLands, Useless Swamps, SandyLands, IcyLands, and the Ghost lands of «Лич». The «Лич» and «Древесная Ветвь» decks are fan-made, from a Tabletop Simulator mod.

[b][color=#ffd75a]Setup.[/color][/b] A coin toss decides who goes first. Players with two land types («Лимонохват», «Гантер», «Пупырка», «Марселин») arrange their own 4 lands. Each player draws 5 cards and may replace their starting hand once per game.

[b][color=#ffd75a]The field.[/color][/b] There are four lanes. Each lane has a land on your side, with room for one of your creatures on it and one building beneath it. A creature attacks only what is opposite it in the same lane.

[b][color=#ffd75a]A turn.[/color][/b]
1. Prepare all your cards (turn them upright).
2. Draw a card.
3. Spend 2 actions: play cards, use abilities, or draw a card for 1 action. Unused actions are lost at the end of the turn.
4. FLOOP: turn your creature or building sideways to use its «ПРИЁМ >>>» ability. A flipped creature cannot attack this turn, but still defends.
5. Attack: all upright creatures must attack, in the order you choose. If an opposing creature is present, both deal damage simultaneously. If the lane is empty, the opponent takes the damage.

[b][color=#ffd75a]Playing cards.[/color][/b] The cost in the circle is both the number of actions spent and the number of lands of the required type you must control. Rainbow cards work with any land. Face-down lands do not count as any type. Cost 0 cards can always be played on your turn.
A creature can be played in any of your lanes. If your upright creature is already there, it is replaced and goes to the discard pile. Buildings go beneath the land and are replaced in the same way. Spells take effect and go to the discard pile.

[b][color=#9fe7ff]Ice.[/color][/b] Cards from «Ледяной Король» and «Гантер» freeze lands with ice tokens. Creatures and buildings cannot be played on a frozen land. On your turn, spend 1 action to melt ice on your land by selecting it.

[b][color=#ffd75a]Damage.[/color][/b] Damage on creatures remains between turns. When damage reaches its defense, the creature dies and goes to its owner's discard pile. Healing damage removes damage from a creature; restoring HP returns health to a player, up to 25.

[b][color=#ffd75a]Important.[/color][/b] On the very first turn, the first player cannot FLOOP or attack. There is no hand limit, and an empty deck does not cause defeat. If an ability has a valid target, you must choose one.

[b][color=#9fe7ff]Controls.[/color][/b] Drag a card from your hand to a lane, or select the card and then a highlighted lane. Selecting your creature or building opens its menu: FLOOP, ability, attack. Select your deck to draw a card for an action. Right-click to inspect any face-up card. Space speeds up animations. F11 toggles full screen. Esc opens the menu.

[b][color=#ffd75a]2 vs 2.[/color][/b] Two teams of two sit with partners opposite each other; turns go around the table. Each team shares 40 health. Two of your lands face the opponent on your left and two face the opponent on your right: a creature attacks whoever is opposite its lane. The two middle lands count as adjacent. The first three players cannot FLOOP or attack on their first turn. «Opponent» in card text means either opponent: choose one when it matters; «each enemy creature» means creatures belonging to both. Ice tokens are unlimited, as in a two-player game. Empty seats are filled by AI; online, the AI runs on the room host's PC.

[b][color=#ffd75a]Three players.[/color][/b] Every player is on their own, with 25 health, and turns go around the table. Two of your lands face the opponent on your left and two face the opponent on your right. The first two players cannot FLOOP or attack on their first turn. «Opponent» in card text means either opponent: choose one when it matters; «each enemy creature» means creatures belonging to both. The first player to lose all health is eliminated and their cards leave the table. The remaining two finish 1 vs 1 on a regular field, lane against lane. The eliminated player watches until the end. The last player wins.

[b][color=#9fe7ff]On one device.[/color][/b] Two players can share one device. Between turns, a curtain hides the screen so your opponent cannot see your hand. If your opponent must choose a card from their hand during your turn, their cards appear on screen: look away.

[b][color=#9fe7ff]Online.[/color][/b] Both players connect to the same Radmin VPN network or local network and choose their heroes. One selects «Создать игру» (Create game) and gives their address to the other player (in Radmin it looks like 26.x.x.x); the other enters it and selects «Подключиться» (Connect). If Windows asks about the firewall, allow access. Both players must have the same game version.
If the connection drops, the game is paused rather than reset. The guest selects «Переподключиться» (Reconnect), or waits for the automatic reconnection, and the game continues from the same point.
""",
		"jake_nerd": "Jake, nerd!",
		"friend": "Sorry, Jake. Let's play again",
		"phase_title": "TURN PHASE",
		"phase_first_intro": "First turn: you already have 5 cards and 2 actions. From your next turn, draw 1 card automatically.",
		"phase_first": "First turn: prepare your cards and restore 2 actions. You already have exactly 5 cards.",
		"phase_start": "Start of turn: prepare flipped cards, restore 2 actions, and draw 1 card.",
		"phase_actions": "Action and ability phase: play creatures, buildings and spells; draw for an action and FLOOP in any order.",
		"phase_attack": "Combat phase: all prepared creatures must attack.",
		"phase_end": "End of turn: pass the turn to your opponent.",
		"phase_main": "Action and ability phase: play cards, draw for an action, and use FLOOP.",
		"welcome_one": "Welcome to Card Wars! It's Jake's favorite game, and lots of other people's too. Soon you'll love it as well. But first, let's learn these EXTREMELY COMPLICATED rules.",
		"welcome_two": "Card Wars is a tabletop duel where each player has their own deck. Epic battles take place across four lanes, just like in the cartoon. Reduce your opponent's health from 25 to 0 and you'll be awesome!",
		"lands": "The four lands on your side of the battlefield are four slots for your creatures and buildings. A lane consists of two lands facing each other.",
		"goal": "Reduce your opponent's health to 0. The type and number of lands determine which cards you can play.",
		"interface": "A card's name is at the top, cost at the upper left, land type at the upper right, and attack and defense at the bottom. Creatures go on lands, buildings beneath creatures, and spells take immediate effect and go to the discard pile. On the first turn you cannot attack or FLOOP.",
		"interface_preview": "Name at top · cost at upper left · land at upper right · attack and defense at bottom",
		"jake_intro": "Dude, let's play already! It's simple: just put down cards.",
		"play_jinn": "Let's start with a creature: it occupies a land slot. «Джинн Стрюзан» has 1 attack and 11 defense. Play «Джинн Стрюзан» in any of your lanes for 2 actions.",
		"jinn_preview": "Creature · cost 2 · attack 1 · defense 11",
		"end_first": "On the first turn you cannot attack or FLOOP. Press «Завершить ход» (End turn).",
		"draw_two": "At the start of your turn, flipped cards are prepared, 2 actions are restored, and you automatically draw 1 card: «Гномьи сопли».",
		"gnome": "Here's a new type: a spell takes effect immediately, then goes to the discard pile. «Гномьи сопли» costs 1 action and draws 3 cards. Play «Гномьи сопли».",
		"gnome_preview": "Spell · cost 1 · draw 3 cards",
		"gnome_result": "Great! You have 1 action left. Look at the highlighted action counter.",
		"baby": "«Прохладный младенец» is a rainbow creature: you don't need a particular land type to play it. Play it for 0 actions in a free lane opposite an empty enemy lane.",
		"baby_preview": "Rainbow creature · cost 0 · can be played on any land",
		"fortress": "Here's a building. It can go in any lane, even one occupied by a creature: its slot is beneath the creature. It stays in play and grants an ongoing effect. Play «Кровавая крепость» beneath «Прохладный младенец» for your last action: it gives the creature +1 attack.",
		"fortress_preview": "Building · cost 1 · creature in this lane gets +1 attack",
		"finn_confident": "I think I've got this game, NERD!",
		"battle_two": "Press «В атаку!» (To battle!) to enter combat. All prepared creatures must attack.",
		"attack_two": "Attack with both prepared creatures. In combat, creatures deal damage simultaneously; at 0 defense, a creature dies and goes to the discard pile. «Прохладный младенец» attacks an empty lane.",
		"jake_reply": "Not so fast, Finn the Nerd!",
		"end_two": "«Джинн Стрюзан» dealt %d damage to «Лучник Дэн», who dealt %d damage back. At 0 defense a creature dies and goes to the discard pile. «Прохладный младенец» also attacked Jake. End your turn.",
		"knight": "«Кожурыцарь» is strong and easily defeats «Прохладный младенец». Look at its ability: it gains +1 attack and +2 defense for each of Jake's Cornfields.",
		"knight_preview": "«Кожурыцарь»: +1 attack and +2 defense per Cornfield.",
		"turn_three": "Let's weaken «Кожурыцарь» and learn to combine cards and abilities. At the start of your turn, you automatically draw «Архитектор разума».",
		"pig": "Spend 1 action to play «Свинья» in a free lane opposite a face-up Cornfield, but not opposite «Кожурыцарь».",
		"pig_preview": "Rainbow creature · cost 1 · FLOOP flips the Cornfield across this lane",
		"floop_pig": "FLOOP is an activated ability: turn the creature sideways to use it. It is no longer prepared and cannot attack this turn, so decide which is more useful. Our goal is to weaken «Кожурыцарь»: FLOOP «Свинья» to flip the land opposite it.",
		"teleport": "«Телепорт» is a spell: it immediately moves a creature, then goes to the discard pile. Play it for 0 actions, select «Свинья», and move it to another free lane opposite a face-up Cornfield.",
		"teleport_preview": "Spell · cost 0 · moves a creature to a free lane",
		"stats_one": "The Cornfield is flipped. «Кожурыцарь» is weaker: attack %d, defense %d. Press Next.",
		"stats_one_preview": "Flipping the land immediately reduced its stats.",
		"architect": "If only «Свинья» could FLOOP again... Wait, we have «Архитектор разума»! When played, its ability prepares a flipped creature. Play it opposite «Кожурыцарь» for your last action and choose «Свинья».",
		"architect_preview": "Creature · cost 1 · on entry, prepare one of your flipped creatures",
		"floop_again": "«Свинья» is prepared again. FLOOP it once more to flip the second Cornfield and weaken «Кожурыцарь».",
		"floop_again_preview": "Flipping lands reduces its attack and defense.",
		"stats_two": "The second land is flipped! «Кожурыцарь» has %d health left, and «Архитектор разума» has %d attack. Even the 1-action Architect can defeat the 2-action Knight. Press Next.",
		"stats_two_preview": "«Кожурыцарь» keeps losing attack and defense.",
		"battle_three": "Enter combat. «Свинья» is flipped and cannot attack.",
		"attack_three": "Attack with your prepared creatures: «Архитектор разума» opposite «Кожурыцарь», and any others that are ready. Combat damage is simultaneous.",
		"jake_corn": "MY CORN!",
		"end_three": "All prepared creatures have attacked. End your turn.",
		"jake_final": "Jake played «Кукутузик» opposite «Джинн Стрюзан» and «Стена початков» opposite «Архитектор разума». Now he enters combat.",
		"wall_hit": "«Стена початков» attacked «Архитектор разума» for 2 damage; the Architect has %d health left. If it stays, it will die attacking the Wall, which can then attack you directly next turn. Replace it with «Крутой пёс» in this lane.",
		"dog_preview": "Creature · cost 2 · attack 2 · defense 7",
		"replace": "Play «Крутой пёс» in place of «Архитектор разума» in this lane. The Architect goes to the discard pile, and the new defender stops «Стена початков» from attacking you directly.",
		"battle_final": "«Крутой пёс» replaced «Архитектор разума». Enter combat and attack with all prepared creatures.",
		"attack_final": "Attack with all prepared creatures: «Крутой пёс» opposite «Стена початков», «Джинн Стрюзан» opposite «Кукутузик», and «Свинья».",
		"jake_final_dialogue": "Finn is cheating! I'm leaving!",
		"archer_summary": "Jake played «Лучник Дэн» opposite «Джинн Стрюзан». They fought simultaneously: the Djinn dealt %d damage and Dan dealt %d back. The Djinn now has %d of %d defense, Dan has %d of %d. At 0 defense a creature dies and goes to the discard pile.",
		"reject_command": "For now, perform the highlighted action.",
		"reject_choice": "Choose the highlighted target.",
	},
	"ko": {
		"next": "다음",
		"rules_title": "게임 규칙",
		"rules_back": "뒤로",
		"rules_desktop_controls": "마우스 오른쪽 버튼으로 앞면 카드를 살펴봅니다. 스페이스바는 애니메이션을 빠르게 합니다. F11은 전체 화면, Esc는 메뉴입니다.",
		"rules_mobile_controls": "앞면 카드를 손가락으로 길게 눌러 살펴봅니다. 뒤로 가기 버튼은 메뉴를 엽니다.",
		"rules_body": """[b][color=#ffd75a]목표.[/color][/b] 상대의 생명을 25에서 0으로 줄입니다.

[b][color=#ffd75a]영웅과 덱.[/color][/b] 게임 전에 각자 영웅을 선택합니다. 영웅의 덱은 카드 40장과 땅 4장으로 구성됩니다. 땅은 푸른 평원, 옥수수밭, 귀여운 땅, 쓸모없는 늪, 모래 땅, 얼음 땅이 있으며, «Лич»에게는 유령 땅이 있습니다. «Лич»와 «Древесная Ветвь» 덱은 Tabletop Simulator 모드에서 가져온 팬 제작 덱입니다.

[b][color=#ffd75a]준비.[/color][/b] 동전 던지기로 선공을 정합니다. 땅 종류가 두 개인 영웅(«Лимонохват», «Гантер», «Пупырка», «Марселин»)은 자신의 땅 4장을 직접 배치합니다. 각자 카드 5장을 뽑고, 게임당 한 번 시작 손패를 교체할 수 있습니다.

[b][color=#ffd75a]필드.[/color][/b] 구역은 네 개입니다. 각 구역의 내 땅 위에는 내 생물 하나, 땅 아래에는 건물 하나를 놓을 수 있습니다. 생물은 같은 구역의 맞은편만 공격합니다.

[b][color=#ffd75a]턴.[/color][/b]
1. 내 카드를 모두 준비합니다(똑바로 세웁니다).
2. 카드를 한 장 뽑습니다.
3. 행동 2개를 써서 카드를 사용하거나 능력을 쓰거나, 행동 1개로 카드를 뽑습니다. 남은 행동은 턴 종료 시 사라집니다.
4. 플룹: 내 생물이나 건물을 옆으로 돌려 «ПРИЁМ >>>» 능력을 사용합니다. 돌려진 생물은 이번 턴에 공격할 수 없지만 방어는 합니다.
5. 공격: 돌려지지 않은 모든 생물은 원하는 순서로 공격해야 합니다. 맞은편에 생물이 있으면 서로 동시에 피해를 줍니다. 비어 있으면 상대 플레이어가 피해를 받습니다.

[b][color=#ffd75a]카드 사용.[/color][/b] 원 안의 비용은 필요한 행동 수이자 보유해야 하는 해당 종류의 땅 수입니다. 무지개 카드는 모든 땅에 사용할 수 있습니다. 뒤집힌 땅은 어떤 종류로도 세지 않습니다. 비용 0인 카드는 내 턴에 항상 사용할 수 있습니다.
생물은 내 어느 구역에나 놓을 수 있습니다. 그곳에 내 돌려지지 않은 생물이 있으면 기존 생물은 교체되어 버림 더미로 갑니다. 건물은 땅 아래에 놓으며 같은 방식으로 교체합니다. 주문은 효과를 낸 뒤 버림 더미로 갑니다.

[b][color=#9fe7ff]얼음.[/color][/b] «Ледяной Король»과 «Гантер»의 카드는 얼음 토큰으로 땅을 얼립니다. 얼어붙은 땅에는 생물과 건물을 놓을 수 없습니다. 내 턴에 얼어붙은 내 땅을 선택하고 행동 1개를 써서 얼음을 녹일 수 있습니다.

[b][color=#ffd75a]피해.[/color][/b] 생물이 받은 피해는 턴이 지나도 남습니다. 피해가 방어력에 도달하면 생물은 쓰러져 소유자의 버림 더미로 갑니다. 피해 회복은 생물의 피해를 없애며, HP 회복은 플레이어의 생명을 최대 25까지 돌려줍니다.

[b][color=#ffd75a]중요.[/color][/b] 첫 번째 플레이어는 맨 첫 턴에 플룹과 공격을 할 수 없습니다. 손패 제한은 없으며 덱이 비어도 패배하지 않습니다. 능력에 유효한 대상이 있으면 반드시 하나를 선택해야 합니다.

[b][color=#9fe7ff]조작.[/color][/b] 손패의 카드를 구역으로 끌거나, 카드를 선택한 뒤 강조된 구역을 선택합니다. 내 생물이나 건물을 선택하면 플룹, 능력, 공격 메뉴가 열립니다. 내 덱을 선택하면 행동 하나로 카드를 뽑습니다. 마우스 오른쪽 버튼으로 앞면 카드를 살펴봅니다. 스페이스바는 애니메이션을 빠르게 합니다. F11은 전체 화면, Esc는 메뉴입니다.

[b][color=#ffd75a]2 대 2.[/color][/b] 두 명씩 두 팀을 이룹니다. 같은 팀은 마주 보고 앉으며 순서대로 턴을 진행합니다. 팀은 생명 40을 공유합니다. 내 땅 둘은 왼쪽 상대를, 나머지 둘은 오른쪽 상대를 마주 보며 생물은 자기 구역 맞은편을 공격합니다. 가운데 땅 두 개는 서로 인접합니다. 처음 세 플레이어는 각자의 첫 턴에 플룹과 공격을 할 수 없습니다. 카드의 «상대»는 두 상대 중 한 명이며 필요한 경우 직접 선택합니다. «상대의 모든 생물»은 두 상대의 생물 모두를 뜻합니다. 얼음 토큰은 2인 게임처럼 제한이 없습니다. 빈자리는 AI가 채우며, 온라인에서는 방을 만든 사람의 PC에서 AI가 실행됩니다.

[b][color=#ffd75a]3인 게임.[/color][/b] 각자 생명 25로 혼자 싸우며 순서대로 턴을 진행합니다. 내 땅 둘은 왼쪽 상대를, 나머지 둘은 오른쪽 상대를 마주 봅니다. 처음 두 플레이어는 각자의 첫 턴에 플룹과 공격을 할 수 없습니다. 카드의 «상대»는 두 상대 중 한 명이며 필요한 경우 직접 선택합니다. «상대의 모든 생물»은 두 상대의 생물 모두를 뜻합니다. 생명을 먼저 모두 잃은 플레이어는 탈락하고 그 카드들은 필드에서 사라집니다. 남은 두 명은 일반 필드에서 구역끼리 마주 보며 1 대 1로 계속합니다. 탈락한 플레이어는 끝까지 관전합니다. 마지막까지 남은 플레이어가 승리합니다.

[b][color=#9fe7ff]한 기기에서 플레이.[/color][/b] 두 명이 한 기기를 사용할 수 있습니다. 턴 사이에 가림막이 화면을 가려 상대가 내 손패를 보지 못하게 합니다. 내 턴에 상대가 자기 손패에서 카드를 골라야 한다면 그 카드들이 화면에 나타납니다. 그때는 화면을 보지 마세요.

[b][color=#9fe7ff]온라인.[/color][/b] 두 플레이어가 같은 Radmin VPN 네트워크나 로컬 네트워크에 연결하고 영웅을 선택합니다. 한 명이 «Создать игру»(게임 만들기)를 누르고 자신의 주소를 알려 줍니다(Radmin 주소 예: 26.x.x.x). 다른 플레이어는 주소를 입력하고 «Подключиться»(연결)를 누릅니다. Windows 방화벽 확인 창이 나타나면 접근을 허용합니다. 두 플레이어의 게임 버전은 같아야 합니다.
연결이 끊겨도 게임이 초기화되지 않고 일시 정지됩니다. 게스트가 «Переподключиться»(재연결)를 누르거나 자동 재연결을 기다리면 같은 지점부터 게임이 계속됩니다.
""",
		"jake_nerd": "제이크, 바보!",
		"friend": "미안해, 제이크. 다시 하자",
		"phase_title": "턴 단계 안내",
		"phase_first_intro": "첫 턴: 손에 카드 5장과 행동 2개가 있습니다. 다음 턴부터 카드 1장을 자동으로 뽑습니다.",
		"phase_first": "첫 턴: 카드를 준비하고 행동 2개를 회복합니다. 손에는 이미 카드 5장이 있습니다.",
		"phase_start": "턴 시작: 돌려진 카드를 준비하고 행동 2개를 회복한 뒤 카드 1장을 뽑습니다.",
		"phase_actions": "행동 및 능력 단계: 생물, 건물, 주문을 사용하고, 행동을 써서 카드를 뽑거나 플룹을 자유로운 순서로 사용합니다.",
		"phase_attack": "전투 단계: 준비된 모든 생물이 공격해야 합니다.",
		"phase_end": "턴 종료: 상대에게 턴을 넘깁니다.",
		"phase_main": "행동 및 능력 단계: 카드를 사용하고, 행동을 써서 뽑거나 플룹을 사용합니다.",
		"welcome_one": "카드 전쟁에 오신 걸 환영해! 제이크와 많은 친구들이 좋아하는 게임이야. 너도 곧 좋아하게 될 거야. 먼저 이 엄청나게 복잡한 규칙부터 배워 보자!",
		"welcome_two": "카드 전쟁은 각자 덱을 가진 두 플레이어의 대결이야. 만화처럼 네 개의 구역에서 멋진 전투가 펼쳐져. 상대의 생명을 25에서 0으로 줄이면 네가 이기는 거야!",
		"lands": "네 쪽의 땅 네 장은 생물과 건물을 놓는 네 개의 자리야. 서로 마주 보는 땅 두 장이 하나의 구역을 이뤄.",
		"goal": "상대의 생명을 0으로 줄이자. 땅의 종류와 개수에 따라 사용할 수 있는 카드가 달라져.",
		"interface": "카드 위쪽에는 이름, 왼쪽 위에는 비용, 오른쪽 위에는 땅 종류, 아래에는 공격력과 방어력이 있어. 생물은 땅에, 건물은 생물 아래에 놓고, 주문은 즉시 효과를 낸 뒤 버림 더미로 가. 첫 턴에는 공격과 플룹을 할 수 없어.",
		"interface_preview": "위: 이름 · 왼쪽 위: 비용 · 오른쪽 위: 땅 · 아래: 공격력과 방어력",
		"jake_intro": "친구야, 이제 게임하자! 간단해, 그냥 카드를 놓으면 돼.",
		"play_jinn": "먼저 생물을 써 보자. 생물은 땅의 한 자리를 차지해. «Джинн Стрюзан»의 공격력은 1, 방어력은 11이야. 행동 2개를 써서 네 구역 아무 곳에나 «Джинн Стрюзан»을 놓아.",
		"jinn_preview": "생물 · 비용 2 · 공격력 1 · 방어력 11",
		"end_first": "첫 턴에는 공격과 플룹을 할 수 없어. «Завершить ход»(턴 종료)를 눌러.",
		"draw_two": "턴이 시작되면 돌려진 카드가 준비되고 행동 2개가 회복돼. 카드 1장도 자동으로 뽑아: «Гномьи сопли»야.",
		"gnome": "이번에는 주문이야. 주문은 즉시 효과를 낸 뒤 버림 더미로 가. «Гномьи сопли»는 행동 1개를 쓰고 카드 3장을 뽑아. «Гномьи сопли»를 사용해 봐.",
		"gnome_preview": "주문 · 비용 1 · 카드 3장 뽑기",
		"gnome_result": "좋아! 행동이 1개 남았어. 강조된 행동 표시를 봐.",
		"baby": "«Прохладный младенец»은 무지개 생물이야. 특정 종류의 땅이 없어도 사용할 수 있어. 상대 생물이 없는 빈 구역 맞은편에 행동 0개로 놓아.",
		"baby_preview": "무지개 생물 · 비용 0 · 모든 땅에 놓을 수 있음",
		"fortress": "이번에는 건물이야. 생물이 이미 있어도 어느 구역에나 놓을 수 있어. 건물 자리는 생물 아래에 있어. 건물은 필드에 남아 지속 효과를 줘. 마지막 행동으로 «Прохладный младенец» 아래에 «Кровавая крепость»를 놓아. 생물의 공격력이 1 올라가.",
		"fortress_preview": "건물 · 비용 1 · 이 구역 생물의 공격력 +1",
		"finn_confident": "이 게임을 이해한 것 같아, 바보야!",
		"battle_two": "«В атаку!»(공격!)를 눌러 전투 단계로 가자. 준비된 생물은 모두 공격해야 해.",
		"attack_two": "준비된 생물 둘 다 공격해. 전투에서 생물들은 동시에 피해를 주고받아. 방어력이 0이 되면 쓰러져 버림 더미로 가. «Прохладный младенец»은 빈 구역을 공격해.",
		"jake_reply": "그렇게 쉽게 될까, 바보 핀!",
		"end_two": "«Джинн Стрюзан»이 «Лучник Дэн»에게 피해 %d을 주고, 반대로 피해 %d을 받았어. 방어력이 0이면 생물은 버림 더미로 가. «Прохладный младенец»도 제이크를 공격했어. 턴을 끝내자.",
		"knight": "«Кожурыцарь»는 강해서 «Прохладный младенец»을 쉽게 쓰러뜨려. 능력을 봐: 제이크의 옥수수밭마다 공격력 +1과 방어력 +2를 얻어.",
		"knight_preview": "«Кожурыцарь»: 옥수수밭마다 공격력 +1, 방어력 +2.",
		"turn_three": "«Кожурыцарь»를 약하게 만들고 카드와 능력을 조합해 보자. 턴 시작에 «Архитектор разума»를 자동으로 뽑아.",
		"pig": "행동 1개로 «Свинья»를 앞면인 옥수수밭 맞은편의 빈 구역에 놓아. «Кожурыцарь» 맞은편은 피해 줘.",
		"pig_preview": "무지개 생물 · 비용 1 · 플룹으로 맞은편 옥수수밭 뒤집기",
		"floop_pig": "플룹은 직접 사용하는 능력이야. 생물을 옆으로 돌려 효과를 쓰면 준비 상태가 풀려 이번 턴에 공격할 수 없어. 어느 쪽이 유리한지 늘 고민해야 해. 지금은 «Кожурыцарь»를 약하게 만들자. «Свинья»를 플룹해 맞은편 땅을 뒤집어.",
		"teleport": "«Телепорт»은 주문이야. 생물 하나를 즉시 옮긴 뒤 버림 더미로 가. 행동 0개로 사용하고 «Свинья»를 골라 앞면인 다른 옥수수밭 맞은편의 빈 구역으로 옮겨.",
		"teleport_preview": "주문 · 비용 0 · 생물을 빈 구역으로 이동",
		"stats_one": "옥수수밭이 뒤집혀 «Кожурыцарь»가 약해졌어. 현재 공격력 %d, 방어력 %d야. 다음을 눌러.",
		"stats_one_preview": "땅을 뒤집자 능력치가 즉시 줄었어.",
		"architect": "«Свинья»가 한 번 더 플룹할 수 있다면 좋을 텐데... 잠깐, «Архитектор разума»가 있잖아! 이 생물은 등장할 때 돌려진 생물을 준비시켜. 마지막 행동으로 «Кожурыцарь» 맞은편에 놓고 «Свинья»를 선택해.",
		"architect_preview": "생물 · 비용 1 · 등장 시 내 돌려진 생물 하나 준비",
		"floop_again": "«Свинья»가 다시 준비됐어. 한 번 더 플룹해 두 번째 옥수수밭을 뒤집고 «Кожурыцарь»를 약하게 만들자.",
		"floop_again_preview": "땅을 뒤집으면 공격력과 방어력이 줄어들어.",
		"stats_two": "두 번째 땅을 뒤집었어! «Кожурыцарь»의 남은 생명은 %d, «Архитектор разума»의 공격력은 %d야. 비용 1인 건축가도 비용 2인 기사를 이길 수 있어. 다음을 눌러.",
		"stats_two_preview": "«Кожурыцарь»의 공격력과 방어력이 더 줄었어.",
		"battle_three": "전투 단계로 가자. «Свинья»는 돌려져 있어서 공격하지 않아.",
		"attack_three": "준비된 생물로 공격해. «Кожурыцарь» 맞은편의 «Архитектор разума»와 다른 준비된 생물도 공격하자. 피해는 동시에 주고받아.",
		"jake_corn": "내 옥수수!",
		"end_three": "준비된 생물이 모두 공격했어. 턴을 끝내자.",
		"jake_final": "제이크가 «Джинн Стрюзан» 맞은편에 «Кукутузик», «Архитектор разума» 맞은편에 «Стена початков»을 놓았어. 이제 전투를 시작해.",
		"wall_hit": "«Стена початков»이 «Архитектор разума»를 공격해 피해 2를 줬어. 남은 생명은 %d이야. 그대로 두면 벽을 공격하다 쓰러지고 다음 턴에 벽이 너를 직접 공격할 수 있어. 이 구역에서 «Крутой пёс»으로 교체하자.",
		"dog_preview": "생물 · 비용 2 · 공격력 2 · 방어력 7",
		"replace": "이 구역의 «Архитектор разума» 대신 «Крутой пёс»을 놓아. 기존 생물은 버림 더미로 가고 새 방어자가 «Стена початков»의 직접 공격을 막아.",
		"battle_final": "«Крутой пёс»이 «Архитектор разума»를 대신했어. 전투 단계로 가서 준비된 생물 모두로 공격하자.",
		"attack_final": "준비된 생물 모두로 공격해: «Стена початков» 맞은편의 «Крутой пёс», «Кукутузик» 맞은편의 «Джинн Стрюзан», 그리고 «Свинья»야.",
		"jake_final_dialogue": "핀이 반칙하고 있어! 난 갈래!",
		"archer_summary": "제이크가 «Джинн Стрюзан» 맞은편에 «Лучник Дэн»을 놓았어. 동시에 싸워서 지니가 피해 %d, 댄이 피해 %d을 줬어. 현재 지니의 방어력은 %d/%d, 댄은 %d/%d야. 방어력이 0이면 생물은 버림 더미로 가.",
		"reject_command": "지금은 강조된 행동을 해 줘.",
		"reject_choice": "강조된 대상을 선택해 줘.",
	},
}


static func get_text(language: String, key: String, russian: String) -> String:
	if language == "ru":
		return russian
	if not TEXT.has(language) or not TEXT[language].has(key):
		push_error("Missing tutorial translation: %s/%s" % [language, key])
		return russian
	return TEXT[language][key]


static func korean_font() -> SystemFont:
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Malgun Gothic", "Noto Sans CJK KR", "Apple SD Gothic Neo", "NanumGothic", "sans-serif"])
	font.allow_system_fallback = true
	return font
