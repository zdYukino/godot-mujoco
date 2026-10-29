@tool
extends "res://live_editor_acceptance.gd"
var publications: Array = []
var read_count := 0
func state() -> Dictionary:
	var index=mini(read_count,publications.size()-1)
	read_count+=1
	return publications[index] if index>=0 else {}
