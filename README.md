# Mag Revvin

Game-jam demo of a compressed-air thruster car (Godot 4.5, Jolt physics, model built in Blender 5.2).

**Play it in the browser, on desktop or phone: https://ozymodo.github.io/revvin/play/** (showcase page: https://ozymodo.github.io/revvin/)

```
godot --path ~/Projects/mag-revvin          # play
godot -e --path ~/Projects/mag-revvin       # open in the editor
```

## Controls

The layout follows Rocket League's defaults on both controller and keyboard + mouse. The help panel (F1) switches to match whichever one you last touched.

| Keyboard + mouse | Controller | |
|---|---|---|
| W / S | RT / LT | throttle · brake, reverse when stopped (full power, mirroring forward; pedals ramp in on keyboard) |
| A / D | left stick ←/→ | steer · **air:** yaw |
| W / S in the air | left stick ↑/↓ | **air:** pitch (forward = nose down). On the keyboard W/S only pitch once pressed afresh in the air, so holding W off a ramp won't nose-dive the car |
| Space / right mouse | A | tap: jump · again in the air: double jump, or with a direction held: dodge flip · hold: fly (Rocket trim) |
| Left mouse / Ctrl | B | boost (rear thrusters, 200 L tank, ~6 s) |
| Shift (or C) | X | powerslide (handbrake) · **air:** hold it and steer to roll instead of yaw |
| Q / E | LB / RB | air roll left / right · **road:** side jets push the car sideways (catch a slide) |
| Mouse | right stick | look around the car (the mouse view swings back after a second; the stick points the camera, down = behind) |
| M / mouse 4 | R3 | **MAG**: hold to pull the underside toward the surface below (see below) |
| B / middle mouse | right stick ↓ | look back |
| V | Y | camera: chase / close / far / hood |
| W + S at a stop | RT + LT | launch control (TC on) / burnout (TC off) |
| ↑ ↓ ← → | | the old flip stick: air pitch / roll; on the road ↓ presses the tyres down, ↑ hops |
| Tab | D-pad ↑ | thruster control: AUTO / HYBRID / FULL |
| Z | L3 | jet assist: on the road, stop and pivot; in flight, descend fast |
| I | D-pad → | **experimental: infinite air.** Tanks and battery never run down, so you can fly for as long as you like |
| 1 / 2 / 3 / 4 | | toggle traction control, ABS, stability control, drift assist |
| F | | suction fans on/off (off = looser, easier to drift) |
| T | D-pad ← | swap Thrust/Rocket trim (when stopped) |
| G | View | switch car: Neon / Symbiote / Phantom (when stopped) |
| X | | x-ray body |
| R | Menu | recover upright |
| Backspace | D-pad ↓ | respawn: last SKYWAY checkpoint during a lap, else the start line |
| Enter | Share | restart the SKYWAY lap (back to the start line) |
| F1 · F11 · Esc | | help · fullscreen · Esc frees the mouse (press again to quit) |

The mouse is captured when the game starts; click to capture it again after Esc. `--infinite` starts with infinite air on.

**Touch (phones and tablets):** the on-screen controls appear on a phone, or at the first touch on any device (`scripts/ui/touch_controls.gd`).
- **Left thumb:** a floating stick that steers. In the air it pitches and yaws, like a controller's left stick.
- **Right thumb:** GAS, BRAKE (reverse when stopped), JUMP (tap twice to double jump, hold to fly), BOOST, DRIFT and MAG.
- **Grab the car:** put a finger on the car and drag, and it tips the way you drag: up for a front flip, down for a back flip, sideways for a barrel roll, and diagonals mix. On the road, the first drag jumps.
  - **Hold:** keep the finger down to hold the car at that angle.
  - **Spin flat:** twist a second finger around the first.
  - **Flick:** let go mid-swipe and the car keeps spinning at the speed of the flick. The flight computer stays off for a moment so it doesn't stop the spin.
- **Anywhere else:** drag to look around. The buttons at the top left are pause, camera, recover and fullscreen.
- **On a phone** the game starts on lighter graphics: 60% render scale, low shadows, no glow or fog, capped at 60 fps. Change them in the pause menu.

**Jumping (Rocket trim):**
- **Jump:** a tap of jump fires all six jets in one short burst (valves wide open for 0.12 s), straight up the car's own axis. It pops about 2.3 m and gives about 1.4 s of air at any speed, for about 3% of the rocket tank. The fans let go instantly, so it doesn't fight them, and you keep all your speed. It works off walls and loops too, since it jumps "up" from the car.
- **Second tap:** within 1.6 s you get one more move:
  - **Double jump:** with no direction held, a further 5 m/s up, to about 5 m.
  - **Dodge:** with a direction held (stick, W/A/S/D, Q/E or arrows), a snap flip that way (front flip, back flip, barrel roll or a diagonal) and a 6 m/s shove in that direction, about 0.65 s per flip. The flight computer stands back during it, then lands you level in AUTO.
- **Off a ramp:** if you leave a ramp without jumping, you still get one jump in the air.
- **Flying:** hold jump past about 0.2 s and the jump carries straight on into flight. Lifting off at speed keeps your momentum (the hover-hold only cancels drift near a standstill).

In flight, the pedals (W/S, RT/LT) tilt the car forward or back to move, and A/D yaw it. The left stick (and the arrows) still pitch and flip the car while you fly, just as in any other jump, so you can hold jump and flip at the same time. With the sticks centred it holds a hover and cancels drift. Let go of jump and it comes down, quickly when high and gently near the ground. The flip controls also work off any ramp.

## MAG

The "mag" in Mag Revvin. An electromagnet in the floor pan pulls the underside of the car toward whatever surface is below it, up to 90 m away. Hold MAG (R3, M, mouse 4, or the MAG button on touch). The physics is in `scripts/car.gd` (`_mag_pull`), and the look, sound and slam are in `scripts/mag.gd`.

- **Getting down fast:** it reaches down the car's own axis, and if nothing is there it reaches straight down. The pull is 3g at full reach, rising to about 5g up close. It first brakes any climb, then turns the wheels to face the surface so the car lands square. A 40 m drop takes about 1.3 s instead of 2.9 s. Holding MAG also ends flight, and the jets stop cushioning the landing.
- **Clinging to walls:** tip the floor toward a wall and the field locks onto the wall instead. Once the wheels touch, it presses them on at about 2.4g on walls, loops and ceilings, so you can sit still on a wall or drive along it. It costs about 0.4% of the battery per second.
- **Slam:** coming down with MAG on at more than 15 m/s into the surface, or after a pull of more than 12 m, slams. The magnet soaks up the hit so the car sticks the landing. Power scales with impact speed and pull distance, and sets the shockwave radius from 5 m to 26 m.
  - **Damage:** enemies and bosses inside it take 25 to 160 damage (most at the centre) and get thrown outward. Scenery and buildings break as in a smaller rocket blast.
  - **Score:** the slam banks a MAG SLAM trick, and kills with it bank SLAM KILL.
- **Effects:** the coil rings under the car glow and spin up, and arcs crawl from the coil to the wheel hubs. Lightning and field rings reach down to a lock-on reticle on the surface, which turns orange once the approach will slam (the HUD shows SLAM READY). A slam fires an electric shockwave ring with lightning forking across the ground to its edge.

## Style score and tricks

Tricks, wall rides, drifts and clean driving score STYLE points (top right). The live trick readout, the drift meter and the rating pop-ups sit just under the STYLE panel. Every banked trick also tops up both air tanks, more for a bigger score: roughly 1% of a tank per 90 points, up to 30%. The air flows in over about half a second, with a vortex spiralling into the car, a glow on the tank gauges and a rising hiss. The code is in `scripts/tricks.gd`.

- **Air tricks:**
  - **Rotations:** front and back flips, barrel rolls, and spins counted in 180s (360, 540…). Doubles and triples pay more.
  - **Combos:** a flip with a roll is a CORKSCREW, and a flip or roll with a spin is a TWISTER.
  - **Air:** height above the takeoff (BIG AIR, HUGE AIR) and hang time. Time spent hovering in flight mode doesn't count as hang time.
  - **Bonuses:** threading a hoop, grabbing a tank mid-air, leaving the inverted ramp upside down, landing on a wall, and landing backwards (FAKIE).
  - **While airborne,** the HUD shows what you've done so far, and a rotation in progress, e.g. "ROLLING 193°".
- **Landing grade:** at touchdown the landing is scored on four things: is the car upright, how hard did it hit, is it still rotating, and is it pointing where it's going (or straight backwards). The ride-out for the next 0.45 s then checks whether all four wheels stay down and the car doesn't slide out.
  - The grading is forgiving: up to about 25° off level, a solid thump and a little leftover spin still land PERFECT.
  - Grades are PERFECT ×1.5, GREAT ×1.25, CLEAN ×1, SKETCHY ×0.75 and ROUGH ×0.55.
  - Coming down on the roof or side is a BAIL. You lose the trick in progress but keep the chain: its timer keeps running, so get back on your wheels quickly.
  - Only a severe CRASH ends the chain: losing more than 16 m/s (about 58 km/h) within 0.3 s, like hitting a wall. It has to show both as speed along the road (horizontal in the air) and as total speed, so hard landings, quarter-pipes, hitting a ramp or kerb at any speed, and heavy braking never count. A crash also loses any drift in progress.
- **Control:** tricks done without the flight computer's help pay more. HYBRID pays ×1.25 and FULL ×1.6. AUTO pays ×1 because it levels and cushions the car for you.
- **Ground:** wall rides and loops score by the second, and are banked once you're back on the level. Banked drifts count too. On the SKYWAY, a hoop, a split ahead of your best, a finished lap and a new best lap all score.
- **Speed:** stunts done fast pay more. Air tricks and wall rides are multiplied by the top speed reached during them: ×1 up to 60 km/h, rising to ×2 at 300 km/h. The pop-up shows it, e.g. "SPEED x1.54 (222 km/h)". Drifts already score by speed.
- **Chain:** tricks banked within 4 s of each other build a multiplier, +0.25 each up to ×3. The timer pauses while you're in the air, drifting or wall riding. Repeating the same trick pays 0.75× for each repeat among your last five (never below 0.3×), so mixing it up pays.
- **Feedback:** grade-coloured sparks off the tyres at touchdown, then a burst, shockwave rings, a flash and a camera kick when the trick banks. A chord plays that brightens with the grade. Glowing ribbon trails come off the rear corners while a chain is alive. A shockwave ring and a rising blip mark every completed rotation, and the screen edges glow for big landings.

## Air tanks and batteries

Floating pickups top the car up by a fair amount. Drive or fly through one, or within a few metres it's pulled toward the car.

- **THRUST** (amber, short) adds 40% to the thrust tank.
- **ROCKET** (red, longer, with fins) adds 35% to the rocket tank. On the Thrust trim, half of that goes into the thrust tank instead.
- **BATTERY** (cyan cell with ⚡ and two terminals) adds 35% to the battery.

**The battery drains as you play.** On top of the motors' own draw, driving fast, the jets, the boost and air time all slowly flatten it: flat out with stunts, a full pack lasts about five minutes. Braking and coasting still regen some back. Below 3% the motors drop into limp mode at 30% power, and the HUD tells you to find a battery. The drain rates are `DRAIN_*` in `car.gd`, and infinite air (I) keeps the battery full too.

**When you grab one, the car absorbs it.** The pickup shrinks into where it's going: the thrust tank across the rear, the rocket tank in the passenger seat, or the pack under the floor. The car answers: a band of light sweeps along its bodywork from nose to tail and its edges glow in the pickup's colour, as if the car itself is being rejuvenated. Air gets a soft pressure ring around the body and a small vortex drawn into the tank. A battery sends an electrical pulse across the ground under the car, which doesn't affect the driving. It then leaves the car crackling for about 4 s, with faint arcs over the body and a jittering electric trail behind the rear wheels. The tank or battery gauge glows while it fills. Banked tricks that refill the tanks get a softer version of the sweep.

They sit on the avenue lanes and every ~230 m along the SKYWAY. More sit inside each hoop, in the air over the street kickers, on the mesa, off the mega ramp, on the wall of death, over the gap jump and flip kicker, and high above the half-pipe. A tall glowing beacon marks each one from a distance. A grabbed tank comes back after 25 s. The code is in `scripts/world/air_pickups.gd`, with the effects in `scripts/fx.gd` and the sounds in `scripts/sfx.gd`.

## Enemies and combat (first wave)

Scrap-and-goo creatures ooze into the city around you, Vampire Survivors style. A new one arrives every few seconds, 55–110 m away, and more can be alive at once as THREAT climbs (one level a minute, shown in the STYLE panel).

**Enemy types.** Each spawns at a random size; bigger ones have more health, hit harder and are worth more.
- **Bees** (floaters, scrap metal and goo with flapping wings) hover and circle at range, spit goo at you, and dive straight at the car when you're close.
- **Rollers** (living spherical tyres) roll after you, trying to bump into you or roll right over the car (grinding damage while on top). They smash about the world as they go: props get knocked flying, and hard hits leave scorch marks and throw debris.
- **Hoppers** (mechanical frogs) crouch and leap on an arc aimed to land on the car. Bigger frogs jump higher. Landing on you is a stomp.

**Shooting them to pieces.** Every enemy is built from parts that break off under fire: the bee's wings, legs, plates and stinger; the roller's tread (in four patches) and hubs; the hopper's back legs, front legs, eyes and head plate. Each part has its own health, and a hit lands on the part nearest to where it struck. At half health a part gets knocked askew. At zero it tears off and tumbles away as a physics chunk that keeps the enemy's motion, plus a kick away from the hit. The stump spits sparks, and below 45% health the machine smokes. When it dies, what's left comes apart. A broken machine keeps fighting, just worse:
- **Bee:** each lost wing costs lift, so it sags, slows and wobbles, dipping toward the side that's missing wings. With no wings on one side it spirals. Down to one wing or none, it drops out of the sky and scuttles along the road after you, still spitting goo and lunging. Without its stinger, its dives hurt less.
- **Roller:** bald patches lose grip and thump each time they come round. A lost hub leaves it lopsided, so it weaves off line. Slower, but still coming.
- **Hopper:** with one back leg it leaps low and short, slewing toward the lame side and spinning in the air. With none it drags itself along in little lunges. Missing a front leg, it lands badly and is slower to go again. Missing an eye, its aim wanders.
- Every armour plate lost makes it take 5% more damage (up to 30%).

**Healing.** Every banked trick and drift patches the hull up a little: about 1 hull per 450 points, at least 1 and at most 8 per trick. The HULL bar glows green and the pop-up shows "+3 HULL".

**Damage you can see.** The bodywork picks up soot and scorch marks as the hull drops. Past 30% damage the bonnet smokes, grey at first, then black. Past 50%, sparks crackle off the body. Past 70%, it's on fire, with embers glowing in the scorched panels.

**Hull.** Hits take HULL (bottom left; a pale segment shows the damage just taken), with a red flash and a camera kick, and a moment of SHIELDED invulnerability after each hit. At zero the car is WRECKED. It blows up: a flash, a fireball, shockwaves, burning pieces thrown out and a column of black smoke, with the blast throwing the wreck up and over and leaving a scorch mark on the ground. The chain is lost, and after a couple of seconds you respawn (last SKYWAY checkpoint, else the start) with a full hull and 3 s of shield.

**Fighting back.**
- **The arsenal** fires on its own; you just drive. Damage numbers float off every hit. See "Weapons" below.
- **Ramming**, Rocket League style: driving into an enemy hurts it and knocks it flying.
  - Damage grows faster than your closing speed: twice as fast means roughly three times the damage.
  - Hitting it mid-flip multiplies that by how fast you're spinning, up to ×3.5. A dodge flip always counts as at least ×3. Flip hits also send enemies flying further.
  - Boosting adds 40%.
  - In the `flipram` test, a straight ram at 76 km/h did 108 and a dodge front-flip into the same target did 331.
- **Flip guard:** while the car is spinning fast (any flip, roll or spin), hits on you do only 40% damage.
- **Dodging:** a dodge flip (second jump with a direction) makes the car untouchable for its first 0.35 s, shown by a shimmer over the car. An attack that meets it is DODGED (no damage, 150 STYLE), so a well-timed flip slips a bee's dive, a frog's stomp or a goo shot. Ram and flip kills bank as stunts (RAM KILL, FLIP SMASH: pop-up, chain and refill). Ray gun kills add their points and keep a chain alive. A ram never counts as a crash.

Enemies live on their own physics layer: they collide with the car, the world and each other, but the car's suspension and camera rays ignore them. The code is in `scripts/enemies/` (`director.gd` spawns, `enemy.gd` is the shared base, then `bee.gd`, `roller.gd`, `hopper.gd` and the procedural `enemy_models.gd`) and `scripts/combat/` (`combat.gd`: hull, rams, projectiles, damage; `raygun.gd`). Tuning is in the constants at the top of each.

## Beasts and bosses

Four animals live in the city, each in its own territory, ruled by its **boss**: the same animal rebuilt as a high-tech monster truck. They have gunmetal armour over living parts (moss, bark, hide), glowing veins in the boss's colour, and big knobbly wheels (`scripts/world/wildlife.gd`, `scripts/world/critter.gd`, `scripts/enemies/boss*.gd`, models in `scripts/enemies/beast_models.gd`).

**Finding a boss.** Herds of its animal roam the territory, and a few strays wander further out, so follow the animals: lots of gorillas means SILVERBACK is near. Entering a territory shows a hint. There's one territory in each quadrant of the city, out in open ground. Currently they're gorilla near (180, 225), rex (−240, 90), spider (−105, −195) and elephant (360, −210), and the console prints them at start-up.

**The animals** (gorillas, young T. rexes, spiders, elephants, and the deer) graze, wander and run from fast cars. Drive slowly near the fighters and they get angry and charge in to hit back, weakly: gorillas punch, rexes and spiders bite. Elephants only fight when provoked. **Run one over** fast enough and it's converted into **biofuel**, a burst of glowing goo that flows into the battery. The speed needed:

| Animal | Speed to run it over | Biofuel |
|---|---|---|
| Spider | 9 km/h | +2% |
| Deer | 14 km/h | +3% |
| Gorilla | 22 km/h | +4% |
| Rex | 29 km/h | +5% |
| Elephant | 47 km/h | +8% |

Bump an elephant slower than that and the car bounces off it (and it's angry). Animals come back a minute later, once you're away.

**The bosses** stay home until you come within 100 m or shoot them, then hunt you. They smash through everything in front of them (trees, lamps, crates, walls, mega-block concrete, towers), their attacks blow holes in the city, and their hits are huge (25–45 hull). Each has a boss bar under the lap timer.

| Boss | Animal | Attacks |
|---|---|---|
| **SILVERBACK** | gorilla, monster-truck chassis with piston arms | **swipe** (backhand that throws the car), **slam** (leaps at you, ground-pound shockwave), **throw** (rips out a chunk of city and hurls it), **rage** (chest-beat: faster for 8 s) |
| **TYRANT** | T. rex on two giant drive wheels, tail wheel | **charge** (sprints at you, jaws open: a bite throws the car), **tail** (spins: the tail sweeps everything away), **roar** (plasma beam from the throat, cuts through buildings) |
| **WIDOWMAKER** | spider whose eight legs end in wheels | **web** (snares the car: it crawls for 3 s), **pounce** (leaps high onto you), **acid** (venom pools that burn), **brood** (calls up spiders that hunt you) |
| **MAMMOTH** | elephant built as a six-wheeled tank | **trample** (a straight-line charge that flattens everything), **cannon** (the trunk fires plasma shells), **quake** (rears up and stamps: a huge shockwave), **toss** (catches the car on its tusks) |

**Taking a boss apart.** Bosses break up the same way, and shed parts steadily over a fight (their parts take 1.8× the damage). Every wheel or leg lost slows it and makes it turn worse. It reels for a moment, sags onto that corner, drags round toward the missing side, and scrapes its stump along the road in a shower of sparks. The HUD calls out the big losses ("TYRANT LOST A WHEEL"). Losing a limb takes away the attacks that need it:
- **SILVERBACK:** with one arm left it swipes with that one. With none, it can't swipe or throw, so it leaps and slams.
- **TYRANT:** drives on two wheels, so losing one is crippling, and with both gone it drags along on its belly. Without its tail it can't spin-sweep and pitches forward off balance.
- **WIDOWMAKER:** with half its legs gone it can't pounce. Without its fangs, no acid.
- **MAMMOTH:** six wheels, so it shrugs off losing one or two. Without its trunk it has no cannon, so it tramples. Without both tusks it can't toss you.

Wheels roll away when they come off. Parts don't grow back when a boss goes home to heal.

A dodge flip avoids their hits and throws, and the flip guard cuts the damage as usual. Ramming a boss hurts it but barely moves it. Get far enough from its territory and it gives up and goes home, healing half its damage. **Beat one** for 5000 × its level in STYLE, a full battery, 50 hull and a large weapon case. It comes back stronger (+30% health) two and a half minutes later.

## Thruster control modes (Tab)

The game starts in **FULL**. Tab (D-pad ↑) cycles through the modes.

- **AUTO**: the flight computer does the work. It self-levels when you let go of the stick, holds a hover and cancels drift, and cushions hard landings. The stick commands flip and roll rates.
- **HYBRID**: the stick still commands rates, but with the stick centred the jets only stop the rotation. The car holds whatever attitude you leave it in, so you can hang in a nose-down dive or fly banked. W/S add pitch in flight. Climb-rate hold and the landing cushion stay on.
- **FULL**: no automation (except two neutral trims that apply in every mode: leaving a ramp without jumping, the car keeps the angle it took off at instead of the lip kicking its nose down, and in the air the boost thrust acts at the centre of mass's height so boosting doesn't pitch the car). The air stick is raw pitch/roll torque, A/D raw yaw, jump is raw lift thrust (feather it to hover), and jet assist (Z / L3) pushes down. Nothing levels you or cushions the landing, and lift pushes along the car's own up axis, so upside down it drives you into the ground.

On the ground the jets also work directly in every mode. Q/E, LB/RB or ←/→ push the car sideways, which is useful for catching a drift or nudging the tail back in. ↓ fires the jets upward to press the tyres into the road for extra grip. ↑ hops the car. All of it uses the rocket tank.

## Driving model

- **Tyres**: lateral grip follows a slip-angle curve (simplified Pacejka). It builds quickly, plateaus around 10–15° of slip, and only eases to about 90% in a full slide, so the car is forgiving at any speed. Cornering grip is worked out first. Traction control and ABS then use only the grip left over, so accelerating or braking out of a corner no longer washes the front out.
- **Wheelspin and lock-up**: with traction control off, too much torque spins the wheels and they lose most of their side grip, which gives power oversteer and burnouts. With ABS off, heavy braking locks the wheels; locked wheels slide and won't steer.
- **Handbrake**: locks the rear wheels and declutches the rear motors. The front motor keeps pulling, which gives AWD-style handbrake turns.
- **Drift assist** (on by default): counter-steers for you and balances the drift on throttle. More throttle keeps the rear loose; lifting off lets it grip and straighten. The rear stays grippier at high speed so fast drifts stay controllable, and it catches spins past about 25°.
- **Stability control** (off by default): nudges the yaw rate toward what the steering asks for, for tidy grip driving.
- **Steering**: lock reduces with speed but opens back up while sliding so you can counter-steer. Turn-in on keyboard slows at speed; return to centre is quick.
- **Coast regen**: lifting off slows the car gently (about 0.12 g) like an EV in regen mode, and charges the battery.
- **Feedback**: skid marks (they follow walls and loops too), tyre smoke, tyre squeal, controller rumble for slides, boost and landings, and a drift score with a combo multiplier up to x5. A drift is banked after a short pause and lost on a crash.

## Tuning against the real car

Published figures from Tesla's Oct 2026 reveal are used where they exist. In the sim, 0–100 km/h takes 0.84 s with the thrusters (Tesla: 0.81 s), top speed is about 250 mph, there are ten cold-gas nozzles on about 600 L, and the tanks run at the reported 440 bar. Mass, the motor split and fan downforce are estimates: 1.9 t, about 1 MW across three motors, and 15 kN of suction. The fans are strong enough to hold the car on a vertical wall when stopped. The jets give a thrust-to-weight of about 2.9, so the car lifts off in about a second and can flip in about 1.2 s.

## The cars

Press **G** (gamepad L3) while stopped to cycle through the cars. All three share the same layout and physics; `--car=bio` starts in the Symbiote and `--car=phantom` in the Phantom.

- **NEON**: the faceted cyberpunk wedge with cyan and magenta neon.
- **SYMBIOTE**: a rugged high-tech steampunk rig in indigo enamel and deep-green armour. It has brass rivets, copper pressure lines, compressor intake stacks, a cow-catcher, riveted mudguards and knobbly tyres on spoked brass hubs. It has no rear wing because its suction fans already provide the downforce. A living pilot sits in the glass pod, holding the yoke with its tendrils. It breathes, its eye follows your steering, and its heartbeat, and every glowing nerve-vein running from the pod to the motors, speeds up under boost, jets and speed. It lays a glowing alien goo-and-vine trail that grows tendrils and fades out over about 14 s, flings dirt clods and green goo drops, kicks up green spore haze when it slides, and lights the ground green beneath it.

- **PHANTOM**: a gloss-black electric grand tourer with a classic roadster silhouette: a long, low nose, pronounced front fenders and wide rear haunches, a teardrop smoked-glass cabin over a very raked windscreen, and a ducktail rear. High-tech green light lines trace the base of the glass, the sills and the wheel arches. It also has slim swept headlamps with green brows, a green tail bar between red lamps, green-ringed turbine-blade wheels and green underglow.

**Tyre trails.** Every car lays its own trail from the rear tyres, and it changes with speed. Each stretch of trail keeps the look it had at the speed it was laid, so speeding up and slowing down shows along it (`scripts/goo_trail.gd`, `scripts/goo_trail.gdshader`):
- **NEON**: a light ribbon. Slow, a dashed neon line. From about 75 km/h it's a solid glowing ribbon with chevrons streaming down it. Past about 125 km/h it widens into a white-hot core in a cyan plasma sheath, with arcs of electricity crackling along it. Hot sparks spray off the tyres at speed.
- **SYMBIOTE**: its goo and vines. Faster, the goo stretches thin and bright and pulses of bioluminescence race down it. Flat out it boils with glowing bubbles.
- **PHANTOM**: spectral mist. Slow, faint ghostly tyre prints. Faster, wisps of green ghost-light curl off and drift outward. Flat out, a bright flickering spectral streak with runes in it. Ghost motes rise off the tyres.

A glow under the tail, in the trail's colour, gets brighter with speed.

Rebuild the models with `tools/build_car.py` (Neon), `tools/build_car_bio.py` (Symbiote) and `tools/build_car_roadster.py` (Phantom). Shared helpers are in `tools/carkit.py`.

## The world

The proving ground sits in the ruins of an overgrown cyberpunk city. A highly advanced society has gone, nature has moved back in, and some of the tech is still running, half-grown into the plants.

- **City:** a street grid of ruined arcology towers, with avenues every 150 m. Most windows are dead or broken and a few are still lit and flickering. Vines hang from the rooflines, moss climbs from the street, and roofs have turned to garden. Some towers lean, and some have broken tops. Flickering holographic signs, levitating maglev beams with vines trailing underneath, and a skyline beyond the walls fading into the haze.
- **Roads:** every avenue is a proper road: a smooth 22 m carriageway with glowing blue edge lines and a dashed centre line, raised kerbs and sidewalks broken at the junctions. Curved kickers are dotted along the lanes, grind rails run along the sidewalks, and the avenues run straight out of the city into the stunt parks.
- **Ground:** cracked asphalt fades into overgrown blocks. Grass grows in the cracks, the old lane paint is nearly gone, and bioluminescent veins (old data lines colonised by something living) pulse through the ground and the structures.
- **Nature fused with tech:** tech-trees (dead data pylons wrapped in roots, crowned with glowing green hexagonal leaf panels). Energy pylons whose roots have taken the base. Streetlamps still burning under the vines. Mossy security drones still hovering on standby, which turn their red eye to follow you. Wrecked hover-cars with bushes growing out of the cabin.
- **Life:** deer herds (with glowing spots) that graze and bolt when you drive near, bird flocks that scatter when you come through fast or fire the jets, drifting bioluminescent spores, and swaying grass that bends away from the car.
- **Atmosphere:** golden-hour sun, volumetric haze with light shafts, glow on everything that still has power, and procedural ambience (wind, birdsong, insects, an electrical hum).

The city is generated from a fixed seed in `scripts/world/city.gd`. It stays out of the `RESERVED` areas in `scripts/level.gd`, which keep every stunt feature and test lane clear. The props and wildlife are Blender models:

```
blender --background --python tools/build_world.py -- assets/world
```

## Weapons

The car carries its weapons on **mounts**: one on each corner and one on the roof above every seat. More seats means more weapons: the Rocket trim's tank takes the passenger seat, so it has 5 mounts, and the Thrust trim has 6. Each mount is a low pod in the car's own body paint with a ring in its accent glow, sitting right on the bodywork, so the guns look built in. An empty mount is just the closed pod. You start with the ray gun.

Every weapon picks its own target (the nearest enemy it can see in range; the sniper picks the toughest), swings onto it, leads it and fires:

| Weapon | Tier | Does |
|---|---|---|
| RAY GUN | 1 | green energy bolts with a splash (COD Zombies style) |
| SCATTERBLAST | 1 | a short-range spread of pellets |
| GOLDEN DEAGLE | 2 | fast, heavy instant shots with a gold tracer |
| SAW RIPPER | 2 | a spinning blade that ricochets from enemy to enemy |
| CRYO SPIKER | 2 | ice shards whose burst chills enemies (slows them, tints them blue) |
| LONGSHOT | 3 | a sniper: 130 m, huge single hits on the toughest enemy |
| SWARM POD | 3 | a salvo of six homing missiles at different targets |
| PLASMA LANCE | 3 | a continuous bright purple-indigo beam |
| THUNDERHEAD | 4 | one big slow rocket with a huge blast |
| TESLA COIL | 4 | a lightning bolt that jumps on to up to four more enemies |

**Weapon cases.** Weapons are found in hexagonal glass cases with the weapon floating inside and a frame in its tier colour (white, blue, purple, gold). Small cases hold tier 1–2 weapons, medium 2–3, large 3–4. They're along the avenues (some hanging in the air above them), on rooftops (ride up a tower's wall to reach one), on top of the Spire and the mega ramp, on the mega-block roofs, in the parks, and floating over hills, the spine and the end of the hoop line. Cases are solid. Drive into one at anything faster than a crawl (about 5 km/h) and it bursts in a shower of glass, frame and glowing tier-coloured voxels, and the weapon is yours. Just touching it at a standstill doesn't break it. If a tower comes down, the cases on its roof come down with it. Taking a weapon:
- A new weapon takes an empty mount, corners first, then seats.
- The same weapon again levels it up, to ★★★★★: +30% damage and 10% faster fire per level.
- With every mount full, a weapon of at least the same tier replaces your weakest one. Otherwise it levels up your weakest instead.

A case refills with a new weapon after a minute. The ARSENAL panel (above the status panel, bottom right) lists each mount, its weapon and level, and a pulsing dot when it's firing. The code is in `scripts/combat/weapons.gd` (stats and models), `arsenal.gd` (mounts, targeting, firing) and `scripts/world/weapon_cases.gd`.

## Smashing the scenery

Nearly everything breaks, in a chunky voxel style: what you break comes apart into real tumbling cubes (`scripts/world/debris.gd`). Breaking through things is never a crash. It just costs a little speed. Fresh rubble passes through the car for a moment, so you don't ram your own debris, and it never trips the wheels.

**Mega-blocks** (`scripts/world/wrecking.gd`, `scripts/world/voxels.gd`) are huge voxel parking structures, 60 × 40 m and five floors high, that take up whole city blocks. They're built from 2.5 m blocks: concrete decks, concrete pillars and huge glass window bands all round, with ceiling lights on every floor. Ramps climb from floor to floor up to the roof, where a large weapon case waits. A kicker in front of each one throws you into the first-floor windows. Then drive the floors, burst out through the far side, or come down a ramp. Each floor has a pickup and some floors have crates.
- **Glass** breaks at any speed. **Concrete** walls and pillars break above 16 m/s (58 km/h). Decks only break in explosions.
- A block left hanging with nothing under it and little beside it falls too.
- Rockets blast big holes (concrete and decks included). Missiles, bolts, saws and frost shots break glass and crates. Enemies smashing into things break them too.

**Crates** are stacked along the sidewalks and round the parks, in piles of up to 3 × 3 × 3. Each crate is a 2 × 2 × 2 block of voxels. About a third of the stacks hide an air tank or battery.

**Towers** chip where they're hit, by the car above 14 m/s, by explosions, or by enemies. Chunks fly off, and each tower has hull points (more the taller it is). Wear one down and it collapses: it sinks into its own dust cloud, shedding big tumbling voxel blocks, and is gone (+2000 STYLE). Anything on its roof goes with it.

**Lamps, energy pylons and SKYWAY pillars** snap off and come down as a column of voxel blocks. Lamps go from 6 m/s, pylons from 18 m/s and pillars from 22 m/s. Explosions bring them down too. Slower knocks just shake them. The SKYWAY deck stays up. Pillars only count when you hit them from below the deck.

Trees, bushes, ferns and rubble rocks break when you hit them, and how badly depends on your speed (`scripts/world/destruction.gd`):
- **Trees:** slow, the tree shakes and drops leaves, and enough knocks break it. From 9 m/s (32 km/h) it snaps at the base and topples, leaving a stump. From 22 m/s (79 km/h) it's torn out and flung along with you.
- **Bushes and ferns:** slow, they're flattened. From 14 m/s (50 km/h) they're shredded into a spray of leaves.
- **Rocks:** slow, chips fly off. From 6 m/s (22 km/h) a rock cracks into a few chunks. From 16 m/s (58 km/h) it bursts into many, flung hard, in a cloud of dust.

Trees and rocks also throw voxel chunks (leaf blocks and stone cubes). Broken pieces are real tumbling physics bodies that fade after 10 s. They're on their own physics layer: the car's body knocks them about, but the wheels don't ride on them, so rubble can't flip you. A fast car breaks a tree before its trunk can stop you dead, so smashing through is never a crash. It costs a little speed, though, and rocks cost more. Each smash scores a few STYLE points and keeps a chain alive. Nature grows back after two minutes, once you're away.

## Skatepark world

The whole map is built to ride, in the spirit of Skate and TrackMania: curves, ramps, rails, walls and hoops everywhere, with lots of vertical stunts. The code is in `scripts/world/stunt_park.gd`, `dome.gd` and `grinds.gd`.

**The dome.** A huge dome encloses the world, so you can't leave it. 600 m out, the ground curves up into it like a giant quarter-pipe (45 m radius), then a vertical wall arcs overhead to a 300 m apex. The whole inside is drivable: ride up the wall on the fans, carve round it, or launch off it. Low down it's solid tech panelling; higher up it fades to an energy lattice you can see the sky through. A rail runs all the way round its foot, one endless grind.

**The stunt parks**, between the city and the dome wall:
- **East, THE SPIRE:** a banked road spirals 84 m up round a tower. Its inner edge is one 850 m grind. Off the top, a drop-in leads to a kicker, a gap with a hoop, and a carve toward the dome.
- **North, BIG AIR:** a mega ramp (a 48 m climb, a banked U-turn, a 42 m drop-in, a kicker, then a gap with a hoop). Also THE CANYON, a 300 m giant half-pipe with grindable rims, and a rising line of hoops to fly through.
- **West, THE HILLS:** rolling hills up to 14 m, with three rails riding over them, kickers and hoops.
- **South, THE PLAZA:** a bowl with a coping, a spine, ledges, stairs with a handrail and a bank, a funbox with a rail, and a full pipe.

**The city:**
- Every upright tower has a curved bank round its base, so drive at a wall and ride straight up it. The fans keep you on.
- The mesa has curved banks up three sides.
- The half-pipe, wall of death and mesa rims and every SKYWAY barrier are grindable.
- Hoops float over the avenues. Flying or jumping through one scores (as part of the trick if you're airborne) and gives a small turbo shove.

**Grinding**, skateboard style. Jump onto any rail or edge and the car rides it, and you keep control of the car the whole time:
- **Steer (A/D or the stick)** turns the car round on the rail. You can turn it across, or all the way round.
- **Pitch (stick, W/S in the air, or the arrows)** tilts the nose up or down. A tilt is held where you leave it, up to about 35 degrees.

The trick is the pose you hold, so change pose mid-grind for a combo:
- **NOSE GRIND:** lined up with the rail, nose dipped.
- **TAIL GRIND:** lined up, nose up.
- **BLUNTSLIDE:** turned more than 55 degrees across the rail.

Boost speeds you along the rail. Jump to pop off (hold a direction to hop off to that side; your double jump or dodge is still available), or ride it off the end.

The catch is light and natural: it only reaches about a metre, there's a small nudge toward the rail in the last couple of metres, and the car keeps the pose it lands in. On the rail, the only help is balance: it won't roll off sideways.
- Rails always catch.
- Edges (barriers, copings, road edges) only catch after you've jumped, so driving off a drop beside one won't grab it.
- A car coming down on its side or upside down misses.

A grind banks when you leave it: points for time, length and switches, with the bluntslide paying a bit more, plus the usual grade, chain, speed bonus and refill. Air tricks that end on a rail bank as "… TO GRIND". While grinding you get a stream of sparks in the style's colour, a hot streak left glowing on the rail, a metal scrape that rises with speed, and a clank on every catch and switch.

## SKYWAY stunt course

A 2.7 km TrackMania-style lap, mostly elevated and weaving between the towers. You start on its start line.

- **Layout, in order:**
  - **Start straight:** a boost pad, then the climb onto the skyway.
  - **East jump:** a sweeping banked left, then a jump over an avenue through a hoop, a long landing and a 15 m loop.
  - **NE wall ride:** a pad and climb, then a corner banked to 82°.
  - **Sky jump:** at 36 m up, a jump over the avenue through a hoop, then three camelbacks.
  - **The Stack:** a descending helix that passes under its own entry.
  - **Wall chicane:** banked to 65° left, then right. The fans hold you on at low speed. Banking always eases in and out gently, so the road never drops away from a car riding high on the outside.
  - **West jump:** over an avenue, through the third hoop.
  - **Loop two:** a pad, then a second loop.
  - **Final drop:** down over the refill lane to the line.
- **Track features:**
  - Banking is worked out from each curve's radius, so turns lean the way you want them to at speed.
  - Barriers line every elevated stretch.
  - Turns get red-orange kerbs and chevrons.
  - Green chevron pads give a turbo shove (`PAD_ACCEL` in `car.gd`). Hoops give a small one too.
- **Timing:** there are 7 checkpoints, which count only in order, and a lap timer with best and last laps. The HUD shows splits against your best (green is ahead, red-orange behind).
- **Respawn:** Backspace puts you back on the last checkpoint, standing still. Enter restarts the lap.
- **Under the deck:** pillars hold it up. Where it crosses an avenue or a test area there's no room for one, so the deck floats on glowing maglev emitters.
- **Streets stay drivable:** the course crosses avenues at least 7 m up, except on the start straight. The city keeps buildings, trees and maglev beams out of its footprint.

The course is written as turtle commands in `scripts/track/course_route.gd` (`straight`, `seg` for turn, climb and bank, `to` for a smooth connector to a point and heading, `loop`, `gap`). `scripts/track/track.gd` sweeps that into one road, barrier and deck mesh, with a single collision shape so there are no bumps at the joins. To edit the layout and check it from above:

```
godot --headless --path . --script tools/dump_track.gd -- /tmp/track.csv
python3 tools/plot_track.py /tmp/track.csv /tmp/track.png    # flags overlaps, low avenue crossings
godot --headless --fixed-fps 120 --path . -- --test=course    # autopilot drives a full lap
```

## Proving ground

- Cone slalom, a kicker, a gap jump and the 12 m mesa, now the stump of a fallen tower (Rocket trim only).
- Suction tests: the wall of death, the half-pipe and the corkscrew loop. Steer slightly right through the loop to follow its sideways offset.
- Stunts: the reveal's inverted ramp (go in fast, you leave it upside down), jumping the line-up of five cars and a Semi, a steep flip kicker, a 14 m mega ramp and speed bumps.

## How the car is modelled (`scripts/car.gd`)

- **Wheels**: raycast suspension (spring, damper, bump stop, anti-roll bars) and a friction-circle tyre model. Grip falls off once the tyres slide.
- **Three motors**: the front motor drives both front wheels. Each rear motor drives one wheel, so the outer rear wheel gets more torque in a turn.
- **Suction fans**: real downforce on the body, which compresses the springs and raises tyre load (and grip). They spool up and down, and pause in flight.
- **Thrust trim**: four rear thrusters on one 200 L tank. Thrust falls as tank pressure drops. Electric actuators gimbal the nozzles: a little steering help on the road, and pitch/yaw stabilisation in the air.
- **Rocket trim**: the passenger seat is swapped for a 400 L tank, plus six perimeter jets. A flight controller turns the request (climb rate, attitude, yaw) into one thrust vector per jet, using a minimum-norm split across the six nozzle positions. Each jet's force is applied at its real position, so stability comes out of the physics rather than being faked. It is always on in the air: it keeps the car level off jumps and cushions hard landings.
- **Onboard compressor**: besides the air tanks in the world and trick refills, an electric compressor draws in outside air and refills whichever tank is emptier, pausing while that tank is venting. It runs off the 200 kWh battery (40 kW). Under regenerative braking it gets the spare energy for free and runs 2.5× faster. A full refill takes about 35 s for the 200 L tank and about 70 s for the 400 L tank. Reports suggest the real car takes hours, so it's sped up for play. Tune it with `COMPRESSOR_LPS`, `REGEN_BOOST` and `COMPRESSOR_KW` in `car.gd`.
- **Battery**: the motors draw from it and regenerative braking puts energy back. Gameplay drain and battery pickups sit on top of that (see "Air tanks and batteries").

## Performance and level of detail

The world gets cheaper the further it is from the camera (`scripts/lod.gd`, autoload `Lod`):

- **Shaders**: the ground, buildings, overgrown surfaces and the SKYWAY road drop their fine detail with distance (cracks, grain, vines, glowing veins), and skip the expensive noise wherever it wouldn't show.
- **Mesh tiers**: trees, bushes, rubble and lamps swap to a simplified one-draw-call stand-in past 70–130 m (every material baked into vertex colours). The skyline is one mesh, and grind-rail posts are one multimesh per rail.
- **Draw distances**: grass, foliage, animals, drones, pickups, weapon cases, signs and lights all fade out by distance. Pickups and cases never go below 110 m, so you can still spot them.
- **Grass density**: a full patch close by, thinning to a third at the edge of its range.
- **Simulation**: animals, drones, bird flocks and flickering signs update every frame up close, then 30, 12 and 4 times a second further out. A fighting animal always updates every frame.

Everything scales with **Level of detail** (Low 0.6×, Medium 0.8×, High 1×, Ultra 1.35×) in the graphics settings. With **Dynamic detail** on (the default), a governor watches the frame time. When frames run over budget it pulls detail in, down to half (shorter distances, earlier shader fade, a slightly shorter shadow range). It lets detail back out when there's headroom. It aims for 120 fps on desktop and 60 on phones, tablets and the Steam Deck, never above the frame-rate limit or, with V-Sync, the refresh rate. When it's below 100%, the frame-rate readout shows the current detail level. The Steam Deck is detected and starts on Low with FSR at 77%, capped at 60.

Benchmark: `godot --path . --resolution 1920x1080 -- --bench [--preset=0..3] [--mobile] [--handheld] [--static] [--shots=dir]` visits five viewpoints, then drives a lap section, and prints fps, 1% lows, GPU time, draw calls, triangles and the detail level. Before → after on an i9-12900K desktop, using its RTX 4060 Ti and its Intel UHD 770 iGPU (roughly half a Steam Deck's GPU) (average fps, worst segment in brackets):

| Setup | Before | After |
|---|---|---|
| RTX 4060 Ti, High, 1080p | 107 (99) | 315 (281) |
| UHD 770, Steam Deck settings, 800p | 28 (21) | 40 (32) |
| UHD 770, High, 800p | 17 (15) | 21 (17) |
| UHD 770, web renderer, phone settings, 720p | 79 (55) | 107 (82) |
| RTX 4060 Ti, web renderer, phone settings, 720p | 103 (86) | 312 (264) |

## Web build and GitHub Pages

Every push to `main` runs `.github/workflows/pages.yml`. It exports the game with Godot 4.5.1, using the single-threaded web template so it runs on GitHub Pages without special headers, into `/play/`. It then publishes it alongside the showcase page in `site/`. To build it locally:

```
godot --headless --path . --export-release Web build/web/index.html
python3 -m http.server -d build/web 8000      # then open http://localhost:8000
```

## Rebuilding the model

```
blender --background --python tools/build_car.py -- assets/car.glb
blender --background --python tools/build_car_bio.py -- assets/car_bio.glb
blender --background --python tools/build_car_roadster.py -- assets/car_roadster.glb
```

This writes `assets/car.glb` and an editable `source/car.blend`. Godot ignores `source/`, because Godot's own .blend importer hangs in headless mode. The game looks up parts by node name (`Wheel_FL`, `Jet_ML`, `Thruster_0`, `Fan_L`, `Motor_RR`, `Collider`…), so keep those names if you remodel.

## Test scenarios

```
godot --headless --path . -- --test=<drag|drift|flip|loop|inverted|halfpipe|jump|refill|swap|sidejet|fullair|hop|aircontrol|tricks|flystick|halfpipe_air|crash|battery|ramp|flipkicker|streetramp|enemies|breakup|horde|flipram|arsenal|grind|wallride|tour|smash|megablock|blast|animals|boss|beasts|trails|cases|damage|reverse|course> [--car=bio|phantom] [--infinite] [--trim=thrust] [--pickups] [--jets=auto|hybrid|full]
godot --path . -- --test=flip --shots=/tmp/shots      # windowed, saves screenshots
```

Each scenario spawns the car at its feature, drives a scripted input plan and prints telemetry every 0.25 s. The drag test also prints the 0–100 km/h time. `hop` does a jump at speed, a dodge front flip, then a jump plus double jump, and prints air time and peak height. `aircontrol` checks the Rocket League bindings: W held through a jump keeps the nose level, a fresh W in the air pitches, air roll, an A/D sideflip and infinite air. The scenarios run with the jets in AUTO, the mode they were written for, unless you pass `--jets=`. `battery` starts low on charge and drives through a battery cell, then an air canister. `smash` lines up a bush, rock and tree and then a rock and a tree, hit at rising speeds (flattened, cracked, shaken, shattered…), then bursts a weapon case and a crate stack. `megablock` takes a rolling start at a mega-block's kicker, flies through the first-floor windows, crosses the deck and bursts out of the far side. `animals` runs over a gorilla, spider and rex for biofuel, bounces off an elephant too slowly, then flattens another at speed. `boss` puts a boss (`BOSS=gorilla|rex|spider|elephant` before the command) against a fully armed car circling it, and logs its attacks, the hits, its health and every part it loses (the test tops the hull up below 30). Add `BOSSCAM=1` for a camera circling the boss. `breakup` sends a tough bee, roller and hopper (`BREAKUP=bee|roller|hopper` for just one) at the parked car's gun, filmed from the side, and logs each part shot off and how they carry on. `cases` drives into three weapon cases at 8, 15 and 25 km/h, and each should burst open. Tests ignore real controllers and keyboards, so nothing plugged in can disturb a run. `trails` drives down an open lane at 40 km/h, then 100, then flat out, filmed from a tracking camera, to show the tyre trail at each speed (add `--car=bio` or `--car=phantom`). `beasts` lines up all four bosses with their animals and puts a camera on each, for screenshots. `blast` sets off four rocket-sized explosions up a mega-block's facade, then hammers the nearest tower until it collapses. `damage` steps the hull down through smoke, sparks and fire, then wrecks the car. `tricks` and `drift` start at half hull so the healing shows. `grind` pops onto a rail laid along the test lane, then (all by steering the car) tilts up to a tail grind, turns across into a bluntslide, turns back and dips into a nose grind. `reverse` drives forward for 4 s, stops, then reverses for 4 s to compare the two. `wallride` drives at a tower and rides up its wall. `tour` teleports round the parks for screenshots. `arsenal` switches to the Thrust trim, fills all six mounts (one weapon twice, to level it), surrounds the car with enemies, and drives through a case. Add `CLOSEUP=1` before the command for a close look at the mounts. Add `NOHUD=1` before any command to hide the HUD, for clean screenshots. `flipram` rams one dummy target straight, dodge-flips into a second, and fires hits at the car mid-dodge (dodged) and later in the flip (cut by the flip guard). `enemies` puts one bee, roller and two hoppers ahead, lets them attack with the gun off for 6 s (ramming what's in the way), then turns it on. `horde` parks the car in the open for 100 s while the director spawns waves, and logs kills, hits and wrecks. Enemies only appear in free play and those two scenarios. `ramp`, `flipkicker` and `streetramp` hit a kicker flat out with a chain going (the street one 20° off its axis); add `--jets=full` to check the car lands without help. `crash` keeps a chain going, then drives flat out into the mesa wall, which should end the chain. `mag` flies up about 40 m and pulls down onto three enemies (a full-power slam), then does a small hop with MAG on that is too low to slam. `magwall` starts 12 m off a tower face with the wheels toward it: MAG pulls it on (a wall slam), it clings in place, then drives along the wall. `flystick` holds jump to fly and front-flips with the left stick mid-flight. `halfpipe_air` goes flat out up the half-pipe wall and out into the air. Every scenario except `course` also logs where the car sits on screen (`scr`, 0 = centre, 1 = edge) and the worst value so far, to check the camera keeps it framed. `tricks` does a dodge backflip and a double jump with a barrel roll, then drives through an air tank. Every test prints each trick, its landing grade, points and refill. Tests leave the air tanks out of the world unless you pass `--pickups`. `course` runs an autopilot round the SKYWAY (a Stanley controller on the road's own frames, at the route's design speeds) and prints the lap time and hoops. Add `--fixed-fps 120` to run headless tests faster than real time.
