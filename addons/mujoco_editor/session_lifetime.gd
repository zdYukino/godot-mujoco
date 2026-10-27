@tool
extends Node
# The base editor control outlives plugin reloads. UndoRedo holds bound session
# methods, so explicitly break that reference cycle before the editor exits.
var session: RefCounted
func _exit_tree() -> void:
	if session: session.close()
	session = null
