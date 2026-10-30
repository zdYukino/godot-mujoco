extends RefCounted
## MuJoCo 3.16 simulate UI definitions adapted to Godot controls.
## Source: simulate/simulate.{h,cc}, Apache-2.0; see src/viewer/UPSTREAM.md.
## The host retains its event loop; no GLFW window or second simulation is created.
const LEFT := ["File","Option","Simulation","Watch","Physics","Rendering","Visualization","Group enable","Logging"]
const RIGHT := ["Joint","Control","Equality"]
const SECTION_KEYS := {"File":"F","Option":"O","Simulation":"S","Watch":"W","Physics":"P","Rendering":"R","Visualization":"V","Group enable":"G","Logging":"L","Joint":"J","Control":"C","Equality":"E"}
const FILE_ACTIONS := [["Save xml","save_xml"],["Save mjb","save_mjb"],["Print model","print_model"],["Print data","print_data"],["Quit","quit"],["Screenshot","screenshot"]]
const OVERLAY_LABELS := {"help":"Help","info":"Info","profiler":"Profiler","sensors":"Sensor"}
const PROFILER_TITLES := ["Counts","Convergence (log 10)","CPU time (msec)","Dimensions"]
const VISUAL_NAMES := {"headlight.active": "Active", "headlight.ambient": "Ambient", "headlight.diffuse": "Diffuse", "headlight.specular": "Specular", "global.orthographic": "Orthographic", "global.fovy": "Field of view", "stat.center": "Center", "global.azimuth": "Azimuth", "global.elevation": "Elevation", "stat.extent": "Extent", "global.ellipsoidinertia": "Inertia", "global.bvactive": "BVH active", "map.stiffness": "Stiffness", "map.stiffnessrot": "Rot stiffness", "map.force": "Force", "map.torque": "Torque", "map.alpha": "Alpha", "map.fogstart": "Fog start", "map.fogend": "Fog end", "map.znear": "Z near", "map.zfar": "Z far", "map.haze": "Haze", "map.shadowclip": "Shadow clip", "map.shadowscale": "Shadow scale", "stat.meansize": "All (meansize)", "scale.forcewidth": "Force width", "scale.contactwidth": "Contact width", "scale.contactheight": "Contact height", "scale.connect": "Connect", "scale.com": "Com", "scale.camera": "Camera", "scale.light": "Light", "scale.selectpoint": "Select point", "scale.jointlength": "Joint length", "scale.jointwidth": "Joint width", "scale.actuatorlength": "Actuator length", "scale.actuatorwidth": "Actuator width", "scale.framelength": "Frame length", "scale.framewidth": "Frame width", "scale.constraint": "Constraint", "scale.slidercrank": "Slider-crank", "rgba.fog": "fog", "rgba.haze": "haze", "rgba.force": "force", "rgba.inertia": "inertia", "rgba.joint": "joint", "rgba.actuator": "actuator", "rgba.actuatornegative": "actnegative", "rgba.actuatorpositive": "actpositive", "rgba.com": "com", "rgba.camera": "camera", "rgba.light": "light", "rgba.selectpoint": "selectpoint", "rgba.connect": "connect", "rgba.contactpoint": "contactpoint", "rgba.contactforce": "contactforce", "rgba.contactfriction": "contactfriction", "rgba.contacttorque": "contacttorque", "rgba.contactgap": "contactgap", "rgba.rangefinder": "rangefinder", "rgba.constraint": "constraint", "rgba.slidercrank": "slidercrank", "rgba.crankbroken": "crankbroken", "rgba.frustum": "frustum", "rgba.bv": "bv", "rgba.bvactive": "bvactive"}

static func shortcut_hints() -> String:
	var text := "MuJoCo panels: Tab left · Shift+Tab right\n"
	for title in LEFT+RIGHT: text+="Alt+%s  %s\n" % [SECTION_KEYS[title],title]
	return text+"F1 Help · F2 Info · F3 Profiler · F4 Sensors\nF11 Godot extras"

static func style(color: Color, border := Color(0,0,0,0)) -> StyleBoxFlat:
	var box := StyleBoxFlat.new(); box.bg_color=color; box.border_color=border
	box.set_border_width_all(1); box.content_margin_left=5;box.content_margin_right=5;box.content_margin_top=2;box.content_margin_bottom=2
	return box

static func make_theme(palette: int, spacing: int, font: int) -> Theme:
	# Square corners, muted section headers, compact numeric controls: mjui's
	# default organization and theme, rendered by Godot on either backend.
	var base: Color = [Color(.25,.25,.25),Color(.24,.15,.1),Color(.88,.88,.88),Color(.03,.03,.03)][clampi(palette,0,3)]
	var ink := Color(.08,.08,.08) if palette==2 else Color(.9,.9,.9)
	var theme := Theme.new(); theme.default_font_size=clampi(7*(font+1),7,42)
	for kind in ["Button","CheckBox","Label","OptionButton","LineEdit","SpinBox"]:
		theme.set_color("font_color",kind,ink); theme.set_color("font_hover_color",kind,ink);theme.set_color("font_pressed_color",kind,ink)
		theme.set_color("font_disabled_color",kind,ink.darkened(.5))
	var round_button := style(Color(.07,.07,.07),Color(.6,.4,.4));round_button.set_corner_radius_all(12)
	var round_hover := style(Color(.18,.18,.18),Color(.8,.6,.6));round_hover.set_corner_radius_all(12)
	theme.set_stylebox("normal","Button",round_button);theme.set_stylebox("hover","Button",round_hover);theme.set_stylebox("pressed","Button",round_hover)
	theme.set_stylebox("disabled","Button",style(base.darkened(.4),Color(.3,.3,.3)))
	theme.set_stylebox("focus","Button",style(Color(0,0,0,0),Color(.7,.7,.85)))
	var teal := Color(.4,.6,.6) if palette!=2 else Color(.7,.85,.85)
	for state in ["normal","hover","pressed"]: theme.set_stylebox(state,"OptionButton",style(teal))
	for state in ["normal","hover"]: theme.set_stylebox(state,"CheckBox",style(Color(.09,.09,.09),Color(.4,.4,.7)))
	for state in ["pressed","hover_pressed"]: theme.set_stylebox(state,"CheckBox",style(Color(.4,.4,.7),Color(.4,.4,.7)))
	theme.set_stylebox("disabled","CheckBox",style(Color(.09,.09,.09),Color(.3,.3,.3)))
	var pixel := Image.create(1,1,false,Image.FORMAT_RGBA8);pixel.fill(Color(0,0,0,0));var empty_icon := ImageTexture.create_from_image(pixel)
	for state in ["checked","unchecked","checked_disabled","unchecked_disabled"]: theme.set_icon(state,"CheckBox",empty_icon)
	theme.set_type_variation("MuJoCoRadio","Button")
	theme.set_stylebox("normal","MuJoCoRadio",style(Color(.07,.07,.07),Color(.4,.6,.4)))
	theme.set_stylebox("pressed","MuJoCoRadio",style(Color(.4,.6,.4),Color(.4,.6,.4)))
	theme.set_stylebox("hover","MuJoCoRadio",style(Color(.2,.3,.2),Color(.4,.6,.4)))
	theme.set_type_variation("MuJoCoSubsection","Button")
	for state in ["normal","hover","pressed","hover_pressed"]: theme.set_stylebox(state,"MuJoCoSubsection",style(Color(.1,.1,.1)))
	theme.set_type_variation("MuJoCoSection","Button")
	var gradient := Gradient.new();gradient.set_color(0,Color(.6,.2,.2) if palette==0 else Color(.6,.3,.1) if palette==1 else Color(.7,.7,.7) if palette==2 else Color(.2,.2,.2));gradient.set_color(1,Color(.1,.07,.07))
	var texture := GradientTexture2D.new();texture.gradient=gradient;texture.width=8;texture.height=32;texture.fill_from=Vector2.ZERO;texture.fill_to=Vector2(0,1)
	var header := StyleBoxTexture.new();header.texture=texture;header.content_margin_left=8;header.content_margin_right=8;header.content_margin_top=4;header.content_margin_bottom=4
	for state in ["normal","hover","pressed","hover_pressed"]: theme.set_stylebox(state,"MuJoCoSection",header)
	var slider_style := style(Color(.28,.18,.3));slider_style.content_margin_top=11;slider_style.content_margin_bottom=11
	theme.set_stylebox("slider","HSlider",slider_style)
	for state in ["grabber","grabber_highlight","grabber_disabled"]: theme.set_icon(state,"HSlider",empty_icon)
	theme.set_stylebox("grabber_area","HSlider",style(Color(.48,.29,.5)))
	theme.set_stylebox("grabber_area_highlight","HSlider",style(Color(.58,.37,.6)))
	theme.set_stylebox("normal","LineEdit",style(base.darkened(.25),base.lightened(.35)))
	theme.set_stylebox("read_only","LineEdit",style(base.darkened(.25)))
	theme.set_stylebox("panel","ScrollContainer",style(base))
	theme.set_constant("separation","VBoxContainer",2+4*spacing)
	theme.set_constant("h_separation","CheckBox",3+4*spacing)
	return theme

# Names, item types and ordering from MakePhysicsSection. Design values are
# intentionally read-only in the Godot integration; runtime controls live above.
const PHYSICS_ENUMS := {"integrator":["Euler","RK4","implicit","implicitfast","discrete"],"cone":["Pyramidal","Elliptic"],"jacobian":["Dense","Sparse","Auto"],"solver":["PGS","CG","Newton"]}
const PHYSICS_GROUPS := [
 ["",[["Integrator","integrator"],["Cone","cone"],["Jacobian","jacobian"],["Solver","solver"]]],
 ["Algorithmic Parameters",[["Timestep","timestep"],["Iterations","iterations"],["Tolerance","tolerance"],["LS Iter","ls_iterations"],["LS Tol","ls_tolerance"],["Noslip Iter","noslip_iterations"],["Noslip Tol","noslip_tolerance"],["CCD Iter","ccd_iterations"],["CCD Tol","ccd_tolerance"],["Sleep Tol","sleep_tolerance"],["SDF Iter","sdf_iterations"],["SDF Init","sdf_initpoints"]]],
 ["Physical Parameters",[["Gravity","gravity"],["Wind","wind"],["Magnetic","magnetic"],["Density","density"],["Viscosity","viscosity"],["Imp Ratio","impratio"]]],
 ["Contact Override",[["Margin","o_margin"],["Sol Imp","o_solimp"],["Sol Ref","o_solref"],["Friction","o_friction"]]],
]
const HELP := """Play / Pause             Space
Speed Up / Down          = / -
Step Back / Forward      Left / Right arrow
Toggle Left / Right UI   Tab / Shift+Tab
Cycle cameras            [ / ]
Free camera              Esc
Select                   Double-click
Select parent            Page Up
Center camera            Right double-click
Tracking camera          Ctrl+Right double-click
Zoom                     Scroll / middle drag
View Orbit               [Shift] left drag
View Pan                 [Shift] right drag
Object Rotate            Ctrl+[Shift] left drag
Object Translate         Ctrl+[Shift] right drag
Help / Info              F1 / F2
Profiler / Sensors       F3 / F4
Full screen              F5 (standalone)
Show UI shortcuts        UI right-button hold
Expand/collapse all      UI title double-click
Reset / Reload           Backspace / Ctrl+L
Align / Copy state       Ctrl+A / Ctrl+[Shift]+C
Print model / data       Ctrl+M / Ctrl+D
Screenshot / Quit        Ctrl+P / Ctrl+Q
Godot extras             F11
"""

static func visual_section(name: String) -> String:
	if name.begins_with("headlight."): return "Headlight"
	if name in ["global.orthographic","global.fovy","stat.center","global.azimuth","global.elevation"]: return "Free Camera"
	if name in ["stat.extent","global.ellipsoidinertia","global.bvactive"]: return "Global"
	if name.begins_with("map."): return "Map"
	if name.begins_with("scale.") or name=="stat.meansize": return "Scale"
	return "RGBA"
