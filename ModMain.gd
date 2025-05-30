extends Node

# Set mod priority if you want it to load before/after other mods
# Mods are loaded from lowest to highest priority, default is 0
const MOD_PRIORITY = -10000 #Needs to load before ship mods
# Name of the mod, used for writing to the logs
const MOD_NAME = "RapidSynchro"
# Path of the mod folder, automatically generated on runtime
var modPath:String = get_script().resource_path.get_base_dir() + "/"
# Required var for the replaceScene() func to work
var _savedObjects := []

# Instances the equipment pointer for use with addEquipment. 
# Adding it here means it won't need to be loaded multiple times
# This saves on both loading speed and on memory usage 
var Equipment = preload("res://HevLib/pointers/Equipment.gd")

var ADD_EQUIPMENT_ITEMS = [] # Variable detected by HevLib to add equipment. Any properly added item will be added to slots via the set values

# Helper function to make the adding of multiple equipment items more streamlined
func addEquipment(item_data: Dictionary):
	#var item = Equipment.__make_equipment(equipment_dictionary)
	ADD_EQUIPMENT_ITEMS.append(item_data)


var Rapid_Synchro_L = {
	"system": "SYSTEM_SYNCHRO_RAPID_L",
	"name_override": "SYSTEM_SYNCHRO_RAPID", 
	"description": "SYSTEM_SYNCHRO_RAPID_DESC",
	"specs": "SYSTEM_SYNCHRO_RAPID_SPEC",
	"manual": "SYSTEM_SYNCHRO_RAPID_MANUAL",
	"warn_if_electric_below":469,
	"price": 472999,
	"slot_type": "HARDPOINT",
	"alignment": "ALIGNMENT_LEFT",
	"equipment_type": "EQUIPMENT_SYNCHROTRONS"
}

var Rapid_Synchro_R = {
	"system": "SYSTEM_SYNCHRO_RAPID_R",
	"name_override": "SYSTEM_SYNCHRO_RAPID", 
	"description": "SYSTEM_SYNCHRO_RAPID_DESC",
	"specs": "SYSTEM_SYNCHRO_RAPID_SPEC",
	"manual": "SYSTEM_SYNCHRO_RAPID_MANUAL",
	"warn_if_electric_below":469,
	"price": 472999,
	"slot_type": "HARDPOINT",
	"alignment": "ALIGNMENT_RIGHT",
	"equipment_type": "EQUIPMENT_SYNCHROTRONS"
}
#	"control":"ship_weapon_fire",
#	"restriction": "HARDPOINT_LOW_STRESS"
# Initialize the mod
# This function is executed before the majority of the game is loaded
# Only the Tool and Debug AutoLoads are available
# Script and scene replacements should be done here, before the originals are loaded
func _init(modLoader = ModLoader):

	l("Initializing")
	#loadDLC()
	#addEquipment(Rapid_Synchro_L)
	#addEquipment(Rapid_Synchro_R)
	#replaceScene("weapons/rapid_synchro.gd")
	#replaceScene("weapons/rapid_synchro.tscn")
	#replaceScene("weapons/rapid_synchro_r.tscn")
	replaceScene("weapons/WeaponSlot.tscn")
	addEquipment(Rapid_Synchro_L)
	addEquipment(Rapid_Synchro_R)
	updateTL("i18n/en.txt", "|")
	l("Initialized")


# Do stuff on ready
# At this point all AutoLoads are available and the game is loaded
func _ready():
	l("Readying")
	
	l("Ready")
	
# Helper script to load translations using csv format
# `path` is the path to the transalation file
# `delim` is the symbol used to seperate the values
# example usage: updateTL("i18n/translation.txt", "|")
func updateTL(path:String, delim:String = ","):
	path = str(modPath + path)
	l("Adding translations from: %s" % path)
	var tlFile:File = File.new()
	tlFile.open(path, File.READ)

	var translations := []

	var csvLine := tlFile.get_line().split(delim)
	l("Adding translations as: %s" % csvLine)
	for i in range(1, csvLine.size()):
		var translationObject := Translation.new()
		translationObject.locale = csvLine[i]
		translations.append(translationObject)

	while not tlFile.eof_reached():
		csvLine = tlFile.get_csv_line(delim)

		if csvLine.size() > 1:
			var translationID := csvLine[0]
			for i in range(1, csvLine.size()):
				translations[i - 1].add_message(translationID, csvLine[i].c_unescape())
			l("Added translation: %s" % csvLine)

	tlFile.close()

	for translationObject in translations:
		TranslationServer.add_translation(translationObject)

	l("Translations Updated")


# Helper function to extend scripts
# Loads the script you pass, checks what script is extended, and overrides it
func installScriptExtension(path:String):
	var childPath:String = str(modPath + path)
	var childScript:Script = ResourceLoader.load(childPath)

	childScript.new()

	var parentScript:Script = childScript.get_base_script()
	var parentPath:String = parentScript.resource_path

	l("Installing script extension: %s <- %s" % [parentPath, childPath])

	childScript.take_over_path(parentPath)


# Helper function to replace scenes
# Can either be passed a single path, or two paths
# With a single path, it will replace the vanilla scene in the same relative position
func replaceScene(newPath:String, oldPath:String = ""):
	l("Updating scene: %s" % newPath)

	if oldPath.empty():
		oldPath = str("res://" + newPath)

	newPath = str(modPath + newPath)

	var scene := load(newPath)
	scene.take_over_path(oldPath)
	_savedObjects.append(scene)
	l("Finished updating: %s" % oldPath)


# Instances Settings.gd, loads DLC, then frees the script.
func loadDLC():
	l("Preloading DLC as workaround")
	var DLCLoader:Settings = preload("res://Settings.gd").new()
	DLCLoader.loadDLC()
	DLCLoader.queue_free()
	l("Finished loading DLC")


# Func to print messages to the logs
func l(msg:String, title:String = MOD_NAME):
	Debug.l("[%s]: %s" % [title, msg])
