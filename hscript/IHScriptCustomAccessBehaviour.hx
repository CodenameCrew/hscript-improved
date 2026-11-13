package hscript;

/**
 * Same Interface as IHScriptCustomBehaviour but for Property.
 */
interface IHScriptCustomAccessBehaviour extends IHScriptCustomBehaviour {
	var __allowSetGet:Bool;
	// TODO: remove those since accessors calls are handled by `Property`
	public function __callGetter(name:String):Dynamic;
	public function __callSetter(name:String, val:Dynamic):Dynamic;
}