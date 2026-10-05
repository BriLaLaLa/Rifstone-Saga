extends GutHookScript
## Eseguito da GUT prima dei test: i salvataggi automatici di GameState vanno su un file di prova.
## Senza questo, i test (es. quest completate, oro, livelli) finivano nel salvataggio vero del giocatore.


func run() -> void:
	var gs = gut.get_tree().root.get_node_or_null("GameState")
	if gs:
		gs.SAVE_PATH = "user://gut_test_save.dat"
