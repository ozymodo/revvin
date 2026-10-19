extends SceneTree
## Dumps the course centre line for tools/plot_track.py:
##   godot --headless --path . --script tools/dump_track.gd -- out.csv

const Track := preload("res://scripts/track/track.gd")
const Route := preload("res://scripts/track/course_route.gd")


func _initialize() -> void:
	var out: String = OS.get_cmdline_user_args()[0]
	var t := Track.new()
	var r := Route.new()
	r.build(t)
	var f := FileAccess.open(out, FileAccess.WRITE)
	f.store_line("x,y,z,upx,upy,upz,w,flags,group,dist")
	for i in t.pts.size():
		var p := t.pts[i]
		var u := t.ups[i]
		f.store_line("%f,%f,%f,%f,%f,%f,%f,%d,%d,%f" % [p.x, p.y, p.z, u.x, u.y, u.z, t.widths[i], t.flags[i], t.groups[i], t.dists[i]])
	f.store_line("#cp," + ",".join(r.checkpoints.map(func(x): return str(x))))
	f.store_line("#hoop," + ",".join(r.jumps.map(func(x): return str(x[0]))))
	f.close()
	print("samples ", t.pts.size(), " length ", t.dists[t.dists.size() - 1])
	t.free()
	quit()
