local wezterm = require("wezterm")

return {
	color_scheme = "Kanagawa (Gogh)",
	font = wezterm.font_with_fallback({
		"JetBrainsMono Nerd Font",
		"FiraCode Nerd Font",
	}),
	colors = {
		tab_bar = {
			background = "#1F1F28", -- overall tab bar background
			active_tab = {
				bg_color = "#2A2A37",
				fg_color = "#DCD7BA",
			},
			inactive_tab = {
				bg_color = "#1F1F28",
				fg_color = "#727169",
			},
			inactive_tab_hover = {
				bg_color = "#2A2A37",
				fg_color = "#DCD7BA",
			},
			new_tab = {
				bg_color = "#1F1F28",
				fg_color = "#7E9CD8",
			},
			new_tab_hover = {
				bg_color = "#2A2A37",
				fg_color = "#DCD7BA",
			},
		},
	},
	text_background_opacity = 1.0,
	window_background_opacity = 0.95,
}
