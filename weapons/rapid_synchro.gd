extends Sprite

export var repairReplacementPrice = 472999
export var repairReplacementTime = 1
export var repairFixPrice = 30000
export var repairFixTime = 12

export var powerDraw = 469000.0
export var power = 93800.0
export var maxCharge = 56500.0 
export var discharge = 25000.0
#export var minCharge = 2250.0 #unused
export var maxStormCharge = 56500
export var maxStorms = 1
export var systemName = "SYSTEM_SYNCHRO_RAPID"
export var maxDistance = 65536.0
export var hostilityDistance = 6000
export var command = "w"
export var pitchScale = 16
export var penetration = 10
export (PackedScene) var stormScene
export var hostilityForFullCharge = 0.05

export var kineticDamageScale = 0.025
export var afterImageTime = 0.16
#export var afterImageMin = 0.1

export var mass = 26250

export (float, 0, 1, 0.05) var kineticPart = 0.25
export (float, 0, 1, 0.05) var thermalPart = 0.4
export (float, 0, 1, 0.05) var empPart = 0.4
export (float, 0, 1, 0.05) var lingeringPart = 0.05

# Cooldown
export var maxCycle = 20.0
export var cycleIncrement = 1.0
export var cycleDecrement = 1.5
export var overheatCycleDecrement = 0.5

# Spark Visuals
export var spark_charge_rate = 5.0
export var spark_decay_rate = 10.0
export (float, 0.0, 1.0, 0.05) var decayFloorFactor = 0.8
export var sparkStartCycle = 1.0
export var sparkMaxCycle = 15.0
export var sparkCurveExponent = 0.2
const SPARK_AUDIO_STOP_THRESHOLD = 0.5
const overheatSparkMultiplier = 1.25
export var overheatSpikeOffset = 5.0
export var overheatSpikeFadeCycles = 20.0


onready var audioCharge = $AudioCharge
onready var audioFire = $AudioFire
onready var flare = $Flare
onready var beamCore = $BeamCore
onready var sparks = [$Sparks1, $Sparks2, $Sparks3]
onready var initialSparkRect: Rect2 = sparks[0].region_rect 
onready var _space_state = get_world_2d().direct_space_state
onready var _initial_flare_energy = flare.energy

var ray: Vector2
var ship 
var slot 

var timeOffsets = []

var _is_overheated = false
var status_threshold = 30

var charge = 0.0
var cycle = 0.0
var firepower = 0.0
var _is_charging = false
var _time_since_last_fire = 1e10
var _last_fire_distance = 0.0
var _play_fire_sound = false

var current_spark_bias = 0.0
var _shader_time = 0.0
var _final_shader_bias_for_audio = 0.0


func _ready():
	ship = getShip()
	var parent = get_parent()
	if "slot" in parent:
		slot = parent.slot
	
	if material != null: 
		material = material.duplicate()

	for s in sparks:
		s.material = s.material.duplicate()
		timeOffsets.append(randf() * 60.0)

#	ray = Vector2(0, -maxDistance)
#
#	flare.visible = false
#	beamCore.visible = false
#	for s in sparks:
#		s.visible = false

func fire(p: float):
	firepower = clamp(p, 0.0, 1.0)

func getStatus():
	var status = 100.0
	if cycle <= 0.0001:
		status = 100.0
	else:
		var progress = clamp(cycle / maxCycle, 0.0, 1.0)
		status = 100.0 * pow(1.0 - progress, 2.0)
	if _is_overheated:
		return min(status, status_threshold - 0.1) 
	else:
		return status

func getPower():
	if maxCharge <= 0.0: return 0.0
	return clamp(charge / maxCharge, 0.0, 1.0) * 100.0

func shouldFire():
	return ship.powerBalance > powerDraw * 0.5

func boresight():
	return {
		"start": global_position,
		"range": maxDistance,
		"angle": deg2rad(0.1),
		"direction": global_rotation
	}

func getSlotName(param: String):
	return "weaponSlot.%s.%s" % [slot, param]


func _physics_process(delta):
	_is_charging = not _is_overheated and firepower > 0.0
	
	if _is_charging:
		if charge < maxCharge:
			var energyRequired = delta * firepower * powerDraw
			var energy_drawn = ship.drawEnergy(energyRequired)
			if powerDraw > 0.0:
				charge += energy_drawn * (power / powerDraw)
			else:
				charge += energy_drawn * power
			charge = clamp(charge, 0.0, maxCharge)
	
		if charge >= maxCharge:
			_fire_weapon(delta)
			charge = 0.0
			cycle = clamp(cycle + cycleIncrement, 0.0, maxCycle)
			if cycle >= maxCycle:
				_is_overheated = true
				_is_charging = false
	
	var current_cycle_decrement_rate = 0.0
	if _is_overheated:
		current_cycle_decrement_rate = overheatCycleDecrement
		if cycle <= 0.0001:
			_is_overheated = false
	elif not _is_charging:
		current_cycle_decrement_rate = cycleDecrement
		charge = clamp(charge - discharge * delta, 0, maxCharge)
	
	if current_cycle_decrement_rate > 0.0:
		cycle = max(cycle - current_cycle_decrement_rate * delta, 0.0)
	
	_time_since_last_fire += delta


func _fire_weapon(delta):
	_play_fire_sound = true
	_time_since_last_fire = 0.0
	_last_fire_distance = maxDistance
	
	var hit_result = _space_state.intersect_ray(
		global_position,
		global_position + ray.rotated(global_rotation),
		ship.physicsExclude,
		35,
		true,
		false
	)
	
	if hit_result:
		var collider = hit_result.collider
		var can_process_hit = Tool.claim(collider) 
		
		if can_process_hit:
			var output = self.charge
			var charge_scale_factor = 1.0
			
			var pen_direction = (hit_result.position - global_position).normalized()
			var pen_magnitude = penetration * charge_scale_factor
			var effective_hit_pos = hit_result.position + pen_direction * pen_magnitude
			

			_last_fire_distance = global_position.distance_to(effective_hit_pos)
			_last_fire_distance = min(_last_fire_distance, maxDistance)
			
			if collider.has_method("applyEnergyDamage"):
				collider.applyEnergyDamage(output * thermalPart, effective_hit_pos, delta)
			if collider.has_method("applyKineticDamage"):
				collider.applyKineticDamage(output * kineticPart * kineticDamageScale, effective_hit_pos)
			if collider.has_method("applyEmpDamage"):
				collider.applyEmpDamage(output * empPart, effective_hit_pos, delta)
			
			if collider.has_method("applyHostility"):
				var safe_hostility_distance = max(hostilityDistance, 1.0)
				var hostility_range_attenuation = 1.0 - clamp((_last_fire_distance - safe_hostility_distance) / safe_hostility_distance, 0.0, 1.0)
				collider.applyHostility(
					ship.faction,
					hostilityForFullCharge * charge_scale_factor * hostility_range_attenuation
				)

			ship.youHit(collider, charge_scale_factor)

			flare.global_position = hit_result.position
			flare.rotation = randf() * 2.0 * PI
			
			_spawn_storms(output * lingeringPart, effective_hit_pos)
			
			Tool.release(collider)


func _spawn_storms(initial_storm_power: float, spawn_position: Vector2):
	if not stormScene or maxStorms <= 0 or initial_storm_power <= 0.0:
		return

	var field = ship.get_parent()

	var current_total_storm_power = initial_storm_power
	var power_per_storm_ideal = current_total_storm_power / float(maxStorms)
	var storms_to_spawn_count = maxStorms

	while current_total_storm_power > 0.0 and storms_to_spawn_count > 0:
		storms_to_spawn_count -= 1
		var storm_instance = stormScene.instance()
		
		var charge_for_this_storm = min(max(float(self.maxStormCharge), power_per_storm_ideal), current_total_storm_power)
	
		storm_instance.chargeLimit = charge_for_this_storm
		storm_instance.global_position = spawn_position
		
		Tool.deferCallInPhysics(field, "add_child", [storm_instance])
		
		current_total_storm_power -= charge_for_this_storm

#BEWARE NIGHTMARE
func _process(delta):
	_update_spark_bias(delta)
	_update_visuals(delta)
	_update_audio(delta)


func _update_spark_bias(delta):
	var target_spark_bias = 0.0
	var use_charge_rate_for_lerp = false
	var current_visual_multiplier = 1.0
	var cycle_factor = 0.0
	var cycle_range = sparkMaxCycle - sparkStartCycle
	
	if cycle_range > 0.0:
		cycle_factor = pow(clamp((cycle - sparkStartCycle) / cycle_range, 0.0, 1.0), sparkCurveExponent)
	elif cycle >= sparkMaxCycle:
		cycle_factor = 1.0
		
	var floor_bias = cycle_factor * decayFloorFactor

	if _is_overheated:
		var spike_end_threshold = max(0.0, maxCycle - overheatSpikeOffset)
		var fade_end_threshold = max(0.0, spike_end_threshold - overheatSpikeFadeCycles)
		if cycle > spike_end_threshold:
			target_spark_bias = 1.0
			current_visual_multiplier = overheatSparkMultiplier
		elif cycle > fade_end_threshold:
			var fade_duration = spike_end_threshold - fade_end_threshold
			var fade_progress = 0.0
			if fade_duration > 0.0:
				fade_progress = clamp((cycle - fade_end_threshold) / fade_duration, 0.0, 1.0)
			target_spark_bias = lerp(floor_bias, 1.0, fade_progress)
			current_visual_multiplier = lerp(1.0, overheatSparkMultiplier, fade_progress)
		else:
			target_spark_bias = floor_bias
	else:
		var peak_bias = cycle_factor
		if _is_charging and maxCharge > 0.0:
			use_charge_rate_for_lerp = true
			target_spark_bias = floor_bias + (peak_bias - floor_bias) * (charge / maxCharge)
		else:
			target_spark_bias = floor_bias
	
	var lerp_rate = spark_decay_rate if not use_charge_rate_for_lerp else spark_charge_rate
	current_spark_bias = lerp(current_spark_bias, target_spark_bias, 1.0 - exp(-lerp_rate * delta))
	current_spark_bias = clamp(current_spark_bias, 0.0, 1.0)
	
	_final_shader_bias_for_audio = current_spark_bias * current_visual_multiplier
	if material != null:
		material.set_shader_param("sparkBias", _final_shader_bias_for_audio)


func _update_visuals(delta):
	var after_image_active = _time_since_last_fire < afterImageTime
	var fade_progress = 0.0

	if after_image_active:
		if afterImageTime > 0.001:
			fade_progress = 1.0 - (_time_since_last_fire / afterImageTime)
		fade_progress = clamp(fade_progress, 0.0, 1.0)

		beamCore.visible = true
		beamCore.scale = Vector2(1.0, _last_fire_distance / 409.6) # 512 x Parent node scale
		beamCore.modulate.a = fade_progress

		if _last_fire_distance < maxDistance * 0.999:
			flare.visible = true
			flare.energy = _initial_flare_energy * fade_progress
		else:
			flare.visible = false

		var srect = Rect2(initialSparkRect.position, initialSparkRect.size)

		for s in sparks:
			s.visible = true
			s.modulate.a = fade_progress
			
			var s_scale_y = s.scale.y
			
			srect.size.y = (_last_fire_distance / s_scale_y) + s.position.y - s.offset.y
			
			s.region_rect = srect

			if s.material:
				if srect.size.x != 0.0 and srect.size.y != 0.0:
					s.material.set_shader_param("regionScale", initialSparkRect.size / srect.size)
	else:
		flare.visible = false
		beamCore.visible = false
		beamCore.modulate.a = 1.0
		for s in sparks:
			s.visible = false
	
	_shader_time += delta
	var spark_idx = 0
	for s in sparks:
		if s.material:
			if spark_idx < timeOffsets.size():
				s.material.set_shader_param("timeOffset", _shader_time + timeOffsets[spark_idx])
			else:
				s.material.set_shader_param("timeOffset", _shader_time)
		spark_idx += 1

func _update_audio(delta):
	var is_player_controlled = ship.isPlayerControlled()

	if _play_fire_sound:
		if is_player_controlled:
			audioFire.play()
		if audioCharge.is_playing():
			audioCharge.stop()
		_play_fire_sound = false

	var should_audio_charge_be_playing = false
	var target_pitch = 0.1

	if _is_charging and charge < maxCharge :
		should_audio_charge_be_playing = true
		if maxCharge > 0.0:
			target_pitch = 0.1 + sqrt(charge / maxCharge) * (pitchScale - 0.1)
	elif _is_overheated and cycle > 0.01:
		should_audio_charge_be_playing = true
		target_pitch = 0.1 + pow(_final_shader_bias_for_audio, 1.5) * (pitchScale - 0.1)
	elif not _is_charging and not _is_overheated and current_spark_bias > SPARK_AUDIO_STOP_THRESHOLD :
		should_audio_charge_be_playing = true
		target_pitch = 0.1 + pow(current_spark_bias, 1.5) * (pitchScale - 0.1)
	
	target_pitch = max(target_pitch, 0.01)

	if should_audio_charge_be_playing and is_player_controlled:
		if not audioCharge.is_playing():
			audioCharge.play()
		audioCharge.pitch_scale = target_pitch
	elif audioCharge.is_playing():
		audioCharge.stop()


func getShip():
	var c = self
	while not c.has_method("getConfig") and c != null:
		c = c.get_parent()
	return c
