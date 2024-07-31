package game

main :: proc() {
	game = new(Game)
	init()
	for game.run {
		update()
	}
	quit()
}