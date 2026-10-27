extends Node

const SAVE_PATH = "user://fx_arena_save.cfg"

var max_unlocked_level: int = 0
var attempts_per_level: Dictionary = {0: 0, 1: 0, 2: 0}

# Configuração fixa das fases (RF04)
var levels = [
	{
		"id": 0,
		"name": "Fase 1: Função Afim",
		"formula_text": "f(x) = y₀ + a · (x - x₀)",
		"type": "linear",
		"default_a": 0.5,
		"default_b": 0.0,
		"start_pos": Vector2(-8, -2),
		"target_pos": Vector2(6, 5),
		"target_radius": 0.9,
		"obstacles": [
			{"pos": Vector2(0, 0), "radius": 1.4}
		],
		"hint": "A curva agora sempre parte do ponto azul! Ajuste 'a' para inclinar a reta até o alvo."
	},
	{
		"id": 1,
		"name": "Fase 2: Função Quadrática",
		"formula_text": "f(x) = y₀ + a · (x - x₀) · (x - b)",
		"type": "quadratic",
		"default_a": -0.08,
		"default_b": 4.0,
		"start_pos": Vector2(-6, -2),
		"target_pos": Vector2(6, -2),
		"target_radius": 0.9,
		"obstacles": [
			{"pos": Vector2(0, -1.8), "radius": 1.7}
		],
		"hint": "Parábola partindo de (x₀, y₀). 'a' controla concavidade e 'b' desloca a segunda raiz."
	},
	{
		"id": 2,
		"name": "Fase 3: Função Senoidal",
		"formula_text": "f(x) = y₀ + a · sen(b · (x - x₀))",
		"type": "sine",
		"default_a": 2.5,
		"default_b": 0.5,
		"start_pos": Vector2(-9, 0),
		"target_pos": Vector2(6.28, 0),
		"target_radius": 0.9,
		"obstacles": [
			{"pos": Vector2(-3.5, 1.5), "radius": 1.4},
			{"pos": Vector2(2.0, -1.5), "radius": 1.4}
		],
		"hint": "Onda senoidal ancorada no ponto azul. 'a' ajusta a amplitude e 'b' a frequência."
	}
]

func _ready():
	load_progress()

# Salva localmente compatível com Desktop e Web/HTML5 (RF11)
func save_progress():
	var config = ConfigFile.new()
	config.set_value("progress", "max_unlocked_level", max_unlocked_level)
	config.set_value("progress", "attempts", attempts_per_level)
	config.save(SAVE_PATH)

func load_progress():
	var config = ConfigFile.new()
	if config.load(SAVE_PATH) == OK:
		max_unlocked_level = config.get_value("progress", "max_unlocked_level", 0)
		attempts_per_level = config.get_value("progress", "attempts", {0: 0, 1: 0, 2: 0})

func record_attempt(level_idx: int):
	attempts_per_level[level_idx] = attempts_per_level.get(level_idx, 0) + 1
	save_progress()

func unlock_next(level_idx: int):
	if level_idx + 1 > max_unlocked_level and level_idx + 1 < levels.size():
		max_unlocked_level = level_idx + 1
		save_progress()
