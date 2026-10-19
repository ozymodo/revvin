extends RefCounted
## The SKYWAY stunt course, written as turtle commands (see track.gd).
## Distances in metres, turns and headings in degrees (+ = left; heading
## 0 = north, 90 = west, -90 = east, 180 = south), bank in degrees.
## Features (pads, hoops, checkpoints) are recorded here by sample index
## and placed by course.gd.
##
## Everything stays at least 7 m up where it crosses an avenue, so the
## streets underneath stay drivable.

const Track := preload("res://scripts/track/track.gd")

const START := Vector3(40, 0.12, 300)
const START_YAW := -PI / 2                                  # east

var checkpoints: Array[int] = []    # sample index of each checkpoint (0 = start/finish)
var jumps: Array = []               # [kicker-end sample index, gap m, design speed m/s]
var pads: Array[int] = []           # sample index at the start of each boost pad
var names: Array[String] = []       # sign text at each checkpoint


func build(t: Track) -> void:
	t.start(START, START_YAW)
	t.target_speed = 40.0
	_cp(t, "START")
	t.straight(30)
	_pad(t)
	t.straight(40)
	t.target_speed = 55.0
	t.straight(150, 22, 0)                                  # climb onto the skyway
	t.to(Vector3(350, 24, 225), 0)                          # sweeping left: north

	# --- East run: jump the avenue, long landing, loop
	_cp(t, "EAST JUMP")
	t.straight(15)
	_jump(t, 34, 2, 0.1)
	t.straight(150, -2, 0)                                  # long landing
	t.target_speed = 32.0
	t.straight(20)
	t.loop(15, 1)
	t.target_speed = 55.0
	t.straight(15)
	_cp(t, "WALL RIDE")

	# --- Climb and the NE wall ride (banked hard round the corner)
	_pad(t)
	t.straight(95, 16, 0)
	t.target_speed = 42.0
	t.seg(45, 22, 0, 0, 72, 14)
	t.seg(40, 46, 0, 0, 82, 14)
	t.seg(45, 22, 0, 0, 0, 16)
	t.target_speed = 55.0

	# --- North run, west at ~36 m: big jump over the avenue, camelbacks
	t.straight(20)
	_cp(t, "SKY JUMP")
	t.straight(20)
	_jump(t, 36, 3, 0.1)
	t.straight(110, -5, 0)
	for i in 3:                                             # camelbacks
		t.straight(20, 2.0, 0)
		t.straight(20, -2.0, 0)
	t.target_speed = 40.0
	t.to(Vector3(-210, 26, -250), 90)

	# --- The Stack: a descending helix that passes under its own entry
	_cp(t, "THE STACK")
	t.target_speed = 30.0
	t.seg(300, -360, -17, 0, -22)
	t.seg(25, 0, 0, 0, 0)
	t.target_speed = 50.0

	# --- West run south: wall chicane (banked near-vertical both ways; the
	# fans keep you on at low speed), then a jump over the avenue
	t.to(Vector3(-350, 12, -230), 180)
	_cp(t, "WALL CHICANE")
	t.straight(10)
	t.target_speed = 35.0
	t.seg(50, 22, 0, 0, 65, 14)
	t.seg(50, 22, 0, 0, 0, 14)
	t.straight(10)
	t.seg(50, -22, 0, 0, -65, 14)
	t.seg(50, -22, 0, 0, 0, 16)
	t.target_speed = 50.0
	t.straight(10)
	_jump(t, 28, 2, 0.08)
	t.straight(70, -2, 0)
	t.target_speed = 40.0
	t.to(Vector3(-250, 10, 175), -90)                       # left: east

	# --- South run east: second loop, then the final drop to the line
	_cp(t, "LOOP TWO")
	_pad(t)
	t.straight(30)
	t.target_speed = 30.0
	t.straight(25)
	t.loop(13, -1)
	t.target_speed = 45.0
	t.straight(20)
	t.to(Vector3(-80, 14, 215), 180)                        # right: south
	_cp(t, "FINAL DROP")
	t.to(Vector3(-30, 8, 300), -90, 0.0, 0.0, 0.45)         # left: east, over the refill lane
	t.target_speed = 40.0
	t.to(START + Vector3(-1, 0, 0), rad_to_deg(START_YAW))


## Kicker, gap and the start of a downhill landing, with a hoop at the top
## of the arc the car flies at the current target speed.
func _jump(t: Track, gap: float, drop: float, kick_grade: float) -> void:
	t.straight(20, 20 * kick_grade * 0.5, kick_grade)
	jumps.append([t.pts.size() - 1, gap, t.target_speed])
	t.gap(gap, drop, -0.18)


func _cp(t: Track, label: String) -> void:
	checkpoints.append(t.pts.size() - 1)
	names.append(label)
	t.mark(Track.F_LINE, 2)


func _pad(t: Track) -> void:
	pads.append(t.pts.size() - 1)
	t.mark(Track.F_PAD, 14)
