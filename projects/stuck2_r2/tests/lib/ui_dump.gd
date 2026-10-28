extends RefCounted
## WHAT THIS IS: the "dump" part of the UI tour. It prints every control that
## is showing on the HUD as one line of text each, so a test (or a person)
## can read where everything sits on the screen without a picture.
##
## HOW IT WORKS: dump() walks the HUD's controls from the top down, in tree
## order (the order they are drawn in, later ones on top), and prints a
## "UIDUMP" line for each one that is showing. A line is
## "UIDUMP <step> <depth> <class> <x>,<y> <w>x<h>" plus the mouse and focus
## settings, the see-through amount and what the control shows (its text,
## font size and colour, box style, bar value, gaps). Node names are left
## out on purpose: nodes made in code get made-up names, nodes in a scene
## get real ones, and both must dump the same. Two builds whose dumps match
## look the same on screen (scratchpad ui_dump.ps1 compares them).
## With `layout` on (the tour's --dump-layout option) each step also prints
## one "UIVIEW <step> <w>x<h>" line (the size of the window) and every
## UIDUMP line gets extra facts after a " |L| " marker, the ones
## tools/ui_layout_check.py needs: the control's place in the tree (path),
## whether it clips what is inside it (clip), the smallest size it can have
## (min), the script's class name (cls) for controls that draw themselves,
## the colour of a panel's box (bg), and for text how much room the text
## really takes (ink) and how many lines it has and shows (lines, vis).
## The lines without the marker are the same either way.
##
## WHO USES IT: tests/ui_tour.gd loads it with preload() and calls dump()
## at each picture step when --dump (or --dump-layout) is given.


## Print the UIDUMP lines of every control showing under `hud` for the
## picture step `step`. With `layout`, also the UIVIEW line and the extra
## facts (see the top of this file).
static func dump(hud: Control, step: String, layout: bool) -> void:
	if layout:
		var vp := hud.get_viewport().get_visible_rect().size
		print("UIVIEW %s %dx%d" % [step, roundi(vp.x), roundi(vp.y)])
	_dump_node(hud, hud, 0, step, layout)


## Print the line for `n` (if it is a control that shows) and then, if it
## shows, the lines of its children, one level deeper.
static func _dump_node(n: Node, hud: Control, depth: int, step: String, layout: bool) -> void:
	if n is CanvasItem and not (n as CanvasItem).is_visible_in_tree():
		return
	if n is Control:
		print("UIDUMP %s %d %s" % [step, depth, _describe(n as Control, hud, layout)])
	for child in n.get_children():
		_dump_node(child, hud, depth + 1, step, layout)


## One control as text (see the top of this file). Positions and sizes are
## rounded to whole pixels; colours are written as hex (rrggbbaa).
static func _describe(c: Control, hud: Control, layout: bool) -> String:
	var r := c.get_global_rect()
	var s := "%s %d,%d %dx%d mouse=%d focus=%d mod=%s" % [c.get_class(), roundi(r.position.x), roundi(r.position.y),
		roundi(r.size.x), roundi(r.size.y), c.mouse_filter, c.focus_mode, c.modulate.to_html(true)]
	# What each kind of control shows.
	if c is Label:
		var l := c as Label
		s += " text=%s size=%d color=%s align=%d wrap=%d" % [JSON.stringify(l.text), l.get_theme_font_size("font_size"),
			l.get_theme_color("font_color").to_html(true), l.horizontal_alignment, l.autowrap_mode]
	elif c is RichTextLabel:
		s += " text=%s" % JSON.stringify((c as RichTextLabel).text)
	elif c is Button:
		var b := c as Button
		s += " text=%s size=%d color=%s disabled=%s normal=%s hover=%s pressed=%s off=%s" % [JSON.stringify(b.text),
			b.get_theme_font_size("font_size"), b.get_theme_color("font_color").to_html(true), b.disabled,
			_box(b.get_theme_stylebox("normal")), _box(b.get_theme_stylebox("hover")),
			_box(b.get_theme_stylebox("pressed")), _box(b.get_theme_stylebox("disabled"))]
	elif c is ProgressBar:
		var p := c as ProgressBar
		s += " value=%.3f fill=%s back=%s" % [p.value, _box(p.get_theme_stylebox("fill")), _box(p.get_theme_stylebox("background"))]
	elif c is ColorRect:
		s += " color=%s" % (c as ColorRect).color.to_html(true)
	# The box behind panels and scroll areas, and the gaps in rows and grids.
	if c is PanelContainer or c is ScrollContainer:
		s += " panel=%s" % _box(c.get_theme_stylebox("panel"))
	if c is BoxContainer:
		s += " sep=%d" % c.get_theme_constant("separation")
	if c is GridContainer:
		s += " cols=%d hsep=%d vsep=%d" % [(c as GridContainer).columns, c.get_theme_constant("h_separation"), c.get_theme_constant("v_separation")]
	if layout:
		s += _layout_facts(c, hud)
	return s


## A box style as text: fill and border colour, border widths, corner
## radius and the space inside (left/top/right/bottom). Other kinds of box
## are named by their class ("StyleBoxEmpty").
static func _box(sb: StyleBox) -> String:
	if sb == null:
		return "none"
	if sb is StyleBoxFlat:
		var f := sb as StyleBoxFlat
		return "flat(%s,%s,b%d%d%d%d,r%d,m%d/%d/%d/%d)" % [f.bg_color.to_html(true), f.border_color.to_html(true),
			f.border_width_left, f.border_width_top, f.border_width_right, f.border_width_bottom, f.corner_radius_top_left,
			roundi(f.content_margin_left), roundi(f.content_margin_top), roundi(f.content_margin_right), roundi(f.content_margin_bottom)]
	return sb.get_class()


## The extra facts --dump-layout adds after the " |L| " marker (see the top
## of this file), written as "name=value" words with no spaces inside.
static func _layout_facts(c: Control, hud: Control) -> String:
	# Step 1: where the control is in the tree, whether it clips its
	# children, and the smallest size it can be squeezed to.
	var m := c.get_combined_minimum_size()
	var clip := 1 if (c is ScrollContainer or c.clip_contents) else 0
	var s := " |L| path=%s clip=%d min=%dx%d" % [str(hud.get_path_to(c)).replace(" ", "_"), clip, roundi(m.x), roundi(m.y)]
	# Step 2: a control with its own script draws itself when it is not a
	# panel (the minimap, the ship readout): name its class.
	var sc: Script = c.get_script()
	if sc != null and sc.get_global_name() != &"":
		s += " cls=%s" % sc.get_global_name()
	# Step 3: the colour of a panel's box.
	if c is PanelContainer or c is Panel or c is ScrollContainer:
		var f := c.get_theme_stylebox("panel") as StyleBoxFlat
		if f != null:
			s += " bg=%s" % f.bg_color.to_html(true)
	# Step 4: how much room the text takes.
	if c is Label:
		s += _label_facts(c as Label)
	elif c is RichTextLabel:
		var rt := c as RichTextLabel
		s += " ink=%dx%d" % [roundi(rt.get_content_width()), roundi(rt.get_content_height())]
	return s


## The text facts of a Label: how it is lined up from top to bottom (valign),
## how many lines its text has (lines), how many of them the label has
## room to show (vis; Godot hides the lines that do not fit), and the
## room the text takes (ink, width x height; width is 0 when the label
## wraps, because the wrapped width is not known here).
static func _label_facts(l: Label) -> String:
	var lines := l.get_line_count()
	var gap := l.get_theme_constant("line_spacing")
	var h := float(lines) * (l.get_line_height() + float(gap)) - float(gap)
	var w := 0.0
	if l.autowrap_mode == TextServer.AUTOWRAP_OFF:
		w = l.get_theme_font("font").get_multiline_string_size(l.text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, l.get_theme_font_size("font_size")).x
	return " valign=%d lines=%d vis=%d ink=%dx%d" % [l.vertical_alignment, lines, l.get_visible_line_count(), roundi(w), roundi(h)]
