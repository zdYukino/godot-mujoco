extends SceneTree
func _initialize():
 var body=PhysicsServer3D.body_create()
 PhysicsServer3D.body_set_max_contacts_reported(body,4)
 PhysicsServer3D.body_set_max_contacts_reported(body,-1)
 var retained=PhysicsServer3D.body_get_max_contacts_reported(body)==4
 PhysicsServer3D.free_rid(body)
 print("CONTACT_NEGATIVE_RESULT ",retained)
 quit(0 if retained else 1)
