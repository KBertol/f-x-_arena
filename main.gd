extends Node2D

# Configurações do Plano Cartesiano (RF04, RF08)
const GRAPH_RECT = Rect2(40, 65, 1070, 445)
const SCALE_PX = 36.0 # 1 unidade matemática = 36 pixels
const ORIGIN_PX = Vector2(575, 287) # Ponto (0,0) no centro do quadro
const X_MIN = -14.5
const X_MAX = 14.5
const Y_MIN = -6.0
const Y_MAX = 6.0

# Estado da partida
var current_level_idx: int = 0
var param_a: float = 1.0
var param_b: float = 0.0

var is_firing: bool = false
var sim_x: float = 0.0
var sim_speed: float = 9.0 # Unidades por segundo na animação (RF05)
var curve_points: PackedVector2Array = []
var collision_point: Vector2 = Vector2.ZERO
var has_collided: bool = false
var level_won: bool = false

# Referências da Interface (UI)
var ui_layer: CanvasLayer
var menu_panel: Control
var level_select_panel: Control
var hud_panel: Control
var tutorial_dialog: AcceptDialog

var lbl_level_title: Label
var lbl_formula: Label
var lbl_attempts: Label
var lbl_feedback: Label
var input_a: LineEdit
var input_b: LineEdit
var btn_fire: Button
var btn_next_level: Button
var level_buttons: Array[Button] = []

var tutorial_step: int = 0
var tutorial_messages = [
	"Bem-vindo ao f(x) Arena!\n\nSeu objetivo é ajustar os coeficientes da função matemática para que o gráfico parta do Ponto Azul (Início), desvie dos Obstáculos Vermelhos e atinja o Alvo Verde.",
	"Como Jogar:\n\n1. Digite números reais (positivos, negativos ou decimais como 0.5 ou -1.5) nas caixas dos parâmetros 'a' e 'b'.\n2. O gráfico permanece estático enquanto você edita para estimular o cálculo mental (RF03).\n3. Clique em 'Disparar Gráfico!' para ver a trajetória animada.",
	"Dica da 1ª Fase:\n\nA função atual é f(x) = a·x + b.\nO ponto inicial está em (-8, -2) e há um obstáculo em (0, 0).\nExperimente colocar a = 0.5 e b = 2.0 e clique em Disparar!"
]

func _ready():
	build_ui()
	show_main_menu()

# Conversores entre Coordenadas Matemáticas e Pixels da Tela
func math_to_px(math_pos: Vector2) -> Vector2:
	return Vector2(
		ORIGIN_PX.x + math_pos.x * SCALE_PX,
		ORIGIN_PX.y - math_pos.y * SCALE_PX # Eixo Y invertido na tela
	)

# Avaliação das funções matemáticas de cada fase
# Avaliação matemática ancorada no ponto inicial (start_pos)
func eval_f(x: float) -> float:
	var lvl = GameData.levels[current_level_idx]
	var x0: float = lvl["start_pos"].x
	var y0: float = lvl["start_pos"].y
	var dx: float = x - x0
	
	match lvl["type"]:
		"linear":
			# f(x) = y0 + a * (x - x0)
			return y0 + param_a * dx
		"quadratic":
			# f(x) = y0 + a * (x - x0) * (x - b) -> sempre zera em x = x0
			return y0 + param_a * dx * (x - param_b)
		"sine":
			# f(x) = y0 + a * sen(b * (x - x0)) -> sempre zera em x = x0 pois sen(0) = 0
			return y0 + param_a * sin(param_b * dx)
			
	return y0

# Loop principal para animar a curva e checar colisões em tempo real (RF05, RF06)
func _process(delta: float):
	if is_firing:
		var prev_x = sim_x
		var next_x = sim_x + sim_speed * delta
		
		# Sub-amostragem para precisão na detecção de colisão
		var substeps = 25
		var step_dx = (next_x - prev_x) / substeps
		
		for i in range(1, substeps + 1):
			var test_x = prev_x + step_dx * i
			var test_y = eval_f(test_x)
			var math_pt = Vector2(test_x, test_y)
			
			# Verifica se saiu dos limites visíveis do plano cartesiano (RF08)
			if test_x > X_MAX or test_y > Y_MAX or test_y < Y_MIN:
				curve_points.append(math_to_px(math_pt))
				stop_firing(false, "Falha: O gráfico ultrapassou os limites do plano cartesiano! Analise a curva e tente novamente.", math_to_px(math_pt))
				break
			
			curve_points.append(math_to_px(math_pt))
			
			# Verifica colisão com obstáculos (RF06, RF08)
			var lvl = GameData.levels[current_level_idx]
			var hit_obs = false
			for obs in lvl["obstacles"]:
				if math_pt.distance_to(obs["pos"]) <= obs["radius"]:
					hit_obs = true
					break
			
			if hit_obs:
				stop_firing(false, "Colisão detectada com obstáculo! Observe o ponto de impacto e ajuste os parâmetros.", math_to_px(math_pt))
				break
			
			# Verifica se atingiu o alvo (RF07)
			if math_pt.distance_to(lvl["target_pos"]) <= lvl["target_radius"]:
				stop_firing(true, "Sucesso! Você atingiu o alvo com precisão matemática!", math_to_px(math_pt))
				break
		
		sim_x = next_x
		queue_redraw()

func stop_firing(won: bool, message: String, impact_px: Vector2):
	is_firing = false
	has_collided = not won
	level_won = won
	collision_point = impact_px
	lbl_feedback.text = message
	btn_fire.disabled = false
	
	if won:
		lbl_feedback.modulate = Color(0.3, 1.0, 0.4)
		GameData.unlock_next(current_level_idx)
		if current_level_idx + 1 < GameData.levels.size():
			btn_next_level.visible = true
	else:
		lbl_feedback.modulate = Color(1.0, 0.45, 0.45)
	
	queue_redraw()

# Renderização do Plano Cartesiano, Objetos e Gráfico
func _draw():
	if not hud_panel.visible:
		return
		
	# Fundo do Plano Cartesiano
	draw_rect(GRAPH_RECT, Color(0.09, 0.11, 0.15), true)
	
	# Grade secundária (1 em 1 unidade)
	var grid_color = Color(0.18, 0.22, 0.28)
	for x in range(int(X_MIN), int(X_MAX) + 1):
		var px_x = math_to_px(Vector2(x, 0)).x
		if px_x >= GRAPH_RECT.position.x and px_x <= GRAPH_RECT.end.x:
			draw_line(Vector2(px_x, GRAPH_RECT.position.y), Vector2(px_x, GRAPH_RECT.end.y), grid_color, 1.0)
			if x != 0 and x % 2 == 0:
				draw_string(ThemeDB.fallback_font, Vector2(px_x - 8, ORIGIN_PX.y + 18), str(x), HORIZONTAL_ALIGNMENT_CENTER, -1, 12, Color(0.6, 0.65, 0.7))
				
	for y in range(int(Y_MIN), int(Y_MAX) + 1):
		var px_y = math_to_px(Vector2(0, y)).y
		if px_y >= GRAPH_RECT.position.y and px_y <= GRAPH_RECT.end.y:
			draw_line(Vector2(GRAPH_RECT.position.x, px_y), Vector2(GRAPH_RECT.end.x, px_y), grid_color, 1.0)
			if y != 0:
				draw_string(ThemeDB.fallback_font, Vector2(ORIGIN_PX.x + 6, px_y + 4), str(y), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.6, 0.65, 0.7))

	# Eixos principais X e Y
	draw_line(Vector2(GRAPH_RECT.position.x, ORIGIN_PX.y), Vector2(GRAPH_RECT.end.x, ORIGIN_PX.y), Color(0.45, 0.5, 0.6), 2.0)
	draw_line(Vector2(ORIGIN_PX.x, GRAPH_RECT.position.y), Vector2(ORIGIN_PX.x, GRAPH_RECT.end.y), Color(0.45, 0.5, 0.6), 2.0)
	
	var lvl = GameData.levels[current_level_idx]
	
	# Desenha Obstáculos (Vermelhos)
	for obs in lvl["obstacles"]:
		var obs_px = math_to_px(obs["pos"])
		var obs_r = obs["radius"] * SCALE_PX
		draw_circle(obs_px, obs_r, Color(0.85, 0.22, 0.25, 0.85))
		draw_arc(obs_px, obs_r, 0, TAU, 36, Color(1.0, 0.5, 0.5), 2.0)
	
	# Desenha Alvo (Verde)
	var target_px = math_to_px(lvl["target_pos"])
	var target_r = lvl["target_radius"] * SCALE_PX
	draw_circle(target_px, target_r, Color(0.18, 0.8, 0.35, 0.85))
	draw_arc(target_px, target_r, 0, TAU, 36, Color(0.6, 1.0, 0.7), 2.5)
	draw_circle(target_px, target_r * 0.35, Color(0.9, 1.0, 0.9))
	
	# Desenha Ponto de Partida do Jogador (Azul)
	var start_px = math_to_px(lvl["start_pos"])
	draw_circle(start_px, 9.0, Color(0.2, 0.6, 1.0))
	draw_arc(start_px, 12.0, 0, TAU, 24, Color(0.6, 0.85, 1.0), 2.0)
	
	# Desenha o Traçado da Função (Amarelo/Ciano)
	if curve_points.size() >= 2:
		var line_color = Color(0.3, 1.0, 0.5) if level_won else Color(1.0, 0.85, 0.2)
		draw_polyline(curve_points, line_color, 3.5, true)
	
	# Desenha marcador de impacto ou sucesso
	if has_collided:
		draw_circle(collision_point, 7.0, Color(1.0, 0.2, 0.2))
	elif level_won:
		draw_circle(collision_point, 8.0, Color(0.4, 1.0, 0.4))

	# Moldura externa do gráfico
	draw_rect(GRAPH_RECT, Color(0.35, 0.4, 0.5), false, 2.0)

# Validação rigorosa de entrada numérica (RF02)
func parse_and_validate(text: String, param_name: String) -> Variant:
	var clean = text.strip_edges().replace(",", ".")
	if clean.is_empty():
		lbl_feedback.text = "Erro de validação: O parâmetro '" + param_name + "' está vazio! Digite um número real."
		lbl_feedback.modulate = Color(1.0, 0.4, 0.4)
		return null
		
	# Suporte a frações simples (ex: 1/2) impedindo divisão por zero
	if "/" in clean:
		var parts = clean.split("/")
		if parts.size() == 2 and parts[0].is_valid_float() and parts[1].is_valid_float():
			var den = parts[1].to_float()
			if is_zero_approx(den):
				lbl_feedback.text = "Erro matemático: Divisão por zero não é permitida no parâmetro '" + param_name + "'!"
				lbl_feedback.modulate = Color(1.0, 0.4, 0.4)
				return null
			return parts[0].to_float() / den
		else:
			lbl_feedback.text = "Erro: Formato de fração inválido no parâmetro '" + param_name + "'. Use ex: 1/2 ou 0.5."
			lbl_feedback.modulate = Color(1.0, 0.4, 0.4)
			return null
			
	if not clean.is_valid_float():
		lbl_feedback.text = "Erro: Valor inválido em '" + param_name + "'. Digite apenas números reais (ex: 2, -0.5, 1.25)."
		lbl_feedback.modulate = Color(1.0, 0.4, 0.4)
		return null
		
	return clean.to_float()

# Ação de Disparar Gráfico (RF03, RF05, RF09)
func _on_fire_pressed():
	if is_firing:
		return
		
	var val_a = parse_and_validate(input_a.text, "a")
	if val_a == null:
		return
	var val_b = parse_and_validate(input_b.text, "b")
	if val_b == null:
		return
		
	# Impede que o multiplicador principal zere a função se não fizer sentido
	if GameData.levels[current_level_idx]["type"] == "sine" and is_zero_approx(val_b):
		lbl_feedback.text = "Atenção: 'b = 0' anula o argumento do seno! Insira um valor diferente de zero."
		lbl_feedback.modulate = Color(1.0, 0.5, 0.3)
		return
		
	param_a = val_a
	param_b = val_b
	
	# Contabiliza tentativa (RF09)
	GameData.record_attempt(current_level_idx)
	update_attempts_label()
	
	# Inicia animação progressiva a partir do X inicial da fase
	var lvl = GameData.levels[current_level_idx]
	sim_x = lvl["start_pos"].x
	curve_points.clear()
	curve_points.append(math_to_px(Vector2(sim_x, eval_f(sim_x))))
	
	has_collided = false
	level_won = false
	is_firing = true
	btn_fire.disabled = true
	btn_next_level.visible = false
	lbl_feedback.text = "Traçando gráfico f(x)..."
	lbl_feedback.modulate = Color(0.85, 0.9, 1.0)
	queue_redraw()

# Reiniciar Fase sem zerar contador de tentativas (RF10)
func _on_reset_pressed():
	is_firing = false
	btn_fire.disabled = false
	has_collided = false
	level_won = false
	curve_points.clear()
	
	var lvl = GameData.levels[current_level_idx]
	input_a.text = str(lvl["default_a"])
	input_b.text = str(lvl["default_b"])
	lbl_feedback.text = "Fase reiniciada aos parâmetros padrão. " + lvl["hint"]
	lbl_feedback.modulate = Color(0.8, 0.85, 0.95)
	queue_redraw()

func load_level(idx: int):
	current_level_idx = idx
	var lvl = GameData.levels[idx]
	
	lbl_level_title.text = lvl["name"]
	lbl_formula.text = "Função da Fase:   " + lvl["formula_text"]
	input_a.text = str(lvl["default_a"])
	input_b.text = str(lvl["default_b"])
	
	is_firing = false
	btn_fire.disabled = false
	btn_next_level.visible = false
	has_collided = false
	level_won = false
	curve_points.clear()
	
	update_attempts_label()
	lbl_feedback.text = lvl["hint"]
	lbl_feedback.modulate = Color(0.8, 0.85, 0.95)
	
	menu_panel.visible = false
	level_select_panel.visible = false
	hud_panel.visible = true
	queue_redraw()

func update_attempts_label():
	var count = GameData.attempts_per_level.get(current_level_idx, 0)
	lbl_attempts.text = "Tentativas na fase: " + str(count)

# Navegação de Telas e Tutorial (RF01, RF12)
func show_main_menu():
	is_firing = false
	menu_panel.visible = true
	level_select_panel.visible = false
	hud_panel.visible = false
	queue_redraw()

func show_level_select():
	menu_panel.visible = false
	level_select_panel.visible = true
	hud_panel.visible = false
	
	for i in range(level_buttons.size()):
		var lvl = GameData.levels[i]
		var att = GameData.attempts_per_level.get(i, 0)
		if i <= GameData.max_unlocked_level:
			level_buttons[i].disabled = false
			level_buttons[i].text = lvl["name"] + "  (Desbloqueada | Tentativas: " + str(att) + ")"
		else:
			level_buttons[i].disabled = true
			level_buttons[i].text = lvl["name"] + "  [BLOQUEADA - Conclua a anterior]"
	queue_redraw()

func start_tutorial():
	load_level(0)
	tutorial_step = 0
	show_tutorial_step()

func show_tutorial_step():
	if tutorial_step < tutorial_messages.size():
		tutorial_dialog.title = "Tutorial Interativo (" + str(tutorial_step + 1) + "/" + str(tutorial_messages.size()) + ")"
		tutorial_dialog.dialog_text = tutorial_messages[tutorial_step]
		tutorial_dialog.popup_centered(Vector2i(520, 240))

func _on_tutorial_confirmed():
	tutorial_step += 1
	if tutorial_step < tutorial_messages.size():
		show_tutorial_step()

# Construção Automática de Toda a Interface Gráfica via Código
func build_ui():
	ui_layer = CanvasLayer.new()
	add_child(ui_layer)
	
	# 1. TELA INICIAL (Protótipo 4.2)
	menu_panel = Control.new()
	menu_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui_layer.add_child(menu_panel)
	
	var bg_menu = ColorRect.new()
	bg_menu.color = Color(0.08, 0.1, 0.14)
	bg_menu.set_anchors_preset(Control.PRESET_FULL_RECT)
	menu_panel.add_child(bg_menu)
	
	var vbox_menu = VBoxContainer.new()
	vbox_menu.set_anchors_preset(Control.PRESET_CENTER)
	vbox_menu.custom_minimum_size = Vector2(500, 320)
	vbox_menu.position = Vector2(-250, -160)
	vbox_menu.add_theme_constant_override("separation", 18)
	menu_panel.add_child(vbox_menu)
	
	var title = Label.new()
	title.text = "f(x) Arena"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 46)
	vbox_menu.add_child(title)
	
	var subtitle = Label.new()
	subtitle.text = "Jogo educacional de estratégia com funções matemáticas.\nAjuste os parâmetros, trace o gráfico no plano cartesiano e atinja o alvo!"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox_menu.add_child(subtitle)
	
	var btn_play = Button.new()
	btn_play.text = "Jogar (Selecionar Fase)"
	btn_play.custom_minimum_size = Vector2(0, 48)
	btn_play.pressed.connect(show_level_select)
	vbox_menu.add_child(btn_play)
	
	var btn_tut = Button.new()
	btn_tut.text = "Tutorial Interativo"
	btn_tut.custom_minimum_size = Vector2(0, 48)
	btn_tut.pressed.connect(start_tutorial)
	vbox_menu.add_child(btn_tut)
	
	# 2. TELA DE SELEÇÃO DE FASES (RF12)
	level_select_panel = Control.new()
	level_select_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui_layer.add_child(level_select_panel)
	
	var bg_lvl = ColorRect.new()
	bg_lvl.color = Color(0.08, 0.1, 0.14)
	bg_lvl.set_anchors_preset(Control.PRESET_FULL_RECT)
	level_select_panel.add_child(bg_lvl)
	
	var vbox_lvl = VBoxContainer.new()
	vbox_lvl.set_anchors_preset(Control.PRESET_CENTER)
	vbox_lvl.custom_minimum_size = Vector2(580, 360)
	vbox_lvl.position = Vector2(-290, -180)
	vbox_lvl.add_theme_constant_override("separation", 15)
	level_select_panel.add_child(vbox_lvl)
	
	var lbl_sel = Label.new()
	lbl_sel.text = "Seleção de Fases"
	lbl_sel.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_sel.add_theme_font_size_override("font_size", 32)
	vbox_lvl.add_child(lbl_sel)
	
	for i in range(GameData.levels.size()):
		var b = Button.new()
		b.custom_minimum_size = Vector2(0, 50)
		var idx = i
		b.pressed.connect(func(): load_level(idx))
		vbox_lvl.add_child(b)
		level_buttons.append(b)
		
	var btn_back_menu = Button.new()
	btn_back_menu.text = "Voltar ao Menu Inicial"
	btn_back_menu.custom_minimum_size = Vector2(0, 44)
	btn_back_menu.pressed.connect(show_main_menu)
	vbox_lvl.add_child(btn_back_menu)
	
	# 3. HUD DA FASE (Barra Superior e Painel Inferior de Controle)
	hud_panel = Control.new()
	hud_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	hud_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui_layer.add_child(hud_panel)
	
	# Barra Superior
	var top_bar = HBoxContainer.new()
	top_bar.position = Vector2(40, 15)
	top_bar.size = Vector2(1070, 40)
	top_bar.add_theme_constant_override("separation", 20)
	hud_panel.add_child(top_bar)
	
	var btn_fases = Button.new()
	btn_fases.text = "← Fases"
	btn_fases.pressed.connect(show_level_select)
	top_bar.add_child(btn_fases)
	
	lbl_level_title = Label.new()
	lbl_level_title.add_theme_font_size_override("font_size", 20)
	lbl_level_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_bar.add_child(lbl_level_title)
	
	lbl_attempts = Label.new()
	lbl_attempts.add_theme_font_size_override("font_size", 18)
	top_bar.add_child(lbl_attempts)
	
	var btn_help = Button.new()
	btn_help.text = "? Ajuda / Tutorial"
	btn_help.pressed.connect(func():
		tutorial_step = 0
		show_tutorial_step()
	)
	top_bar.add_child(btn_help)
	
	# Painel Inferior de Parâmetros e Disparo
	var bottom_box = VBoxContainer.new()
	bottom_box.position = Vector2(40, 520)
	bottom_box.size = Vector2(1070, 115)
	bottom_box.add_theme_constant_override("separation", 10)
	hud_panel.add_child(bottom_box)
	
	var controls_bar = HBoxContainer.new()
	controls_bar.add_theme_constant_override("separation", 16)
	bottom_box.add_child(controls_bar)
	
	lbl_formula = Label.new()
	lbl_formula.add_theme_font_size_override("font_size", 20)
	lbl_formula.modulate = Color(0.4, 0.85, 1.0)
	controls_bar.add_child(lbl_formula)
	
	var lbl_a = Label.new()
	lbl_a.text = "   Parâmetro a:"
	controls_bar.add_child(lbl_a)
	
	input_a = LineEdit.new()
	input_a.custom_minimum_size = Vector2(85, 38)
	input_a.placeholder_text = "Ex: 1.0"
	controls_bar.add_child(input_a)
	
	var lbl_b = Label.new()
	lbl_b.text = "Parâmetro b:"
	controls_bar.add_child(lbl_b)
	
	input_b = LineEdit.new()
	input_b.custom_minimum_size = Vector2(85, 38)
	input_b.placeholder_text = "Ex: 0.0"
	controls_bar.add_child(input_b)
	
	btn_fire = Button.new()
	btn_fire.text = "Disparar Gráfico!"
	btn_fire.custom_minimum_size = Vector2(165, 38)
	btn_fire.pressed.connect(_on_fire_pressed)
	controls_bar.add_child(btn_fire)
	
	var btn_reset = Button.new()
	btn_reset.text = "Reiniciar Fase"
	btn_reset.custom_minimum_size = Vector2(130, 38)
	btn_reset.pressed.connect(_on_reset_pressed)
	controls_bar.add_child(btn_reset)
	
	btn_next_level = Button.new()
	btn_next_level.text = "Avançar Fase →"
	btn_next_level.custom_minimum_size = Vector2(145, 38)
	btn_next_level.modulate = Color(0.4, 1.0, 0.5)
	btn_next_level.visible = false
	btn_next_level.pressed.connect(func():
		if current_level_idx + 1 < GameData.levels.size():
			load_level(current_level_idx + 1)
	)
	controls_bar.add_child(btn_next_level)
	
	lbl_feedback = Label.new()
	lbl_feedback.add_theme_font_size_override("font_size", 16)
	bottom_box.add_child(lbl_feedback)
	
	# Popup de Tutorial Interativo (RF01)
	tutorial_dialog = AcceptDialog.new()
	tutorial_dialog.ok_button_text = "Próximo"
	tutorial_dialog.confirmed.connect(_on_tutorial_confirmed)
	ui_layer.add_child(tutorial_dialog)
