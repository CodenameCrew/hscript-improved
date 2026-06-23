package hscript.behaviours;

/**
 * Same Interface as IHScriptCustomBehaviour but for Property.
 */
interface IHScriptCustomAccessBehaviour extends IHScriptCustomBehaviour {
	var __allowSetGet:Bool;

	public function __callGetter(name:String):Dynamic;
	public function __callSetter(name:String, val:Dynamic):Dynamic;
}