extends Panel

## One hit point on the ship systems display: a single box that is either
## intact in its family colour or destroyed. Painted from sim state, holds
## none, decides nothing (CLAUDE.md 5.2).


func paint(intact: bool, family: String) -> void:
	$Bg.color = Palette.with_alpha(Palette.family_color(family), 0.55) if intact \
		else Palette.with_alpha(Palette.CRIT, 0.14)
