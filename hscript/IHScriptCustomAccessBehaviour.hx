package hscript;

interface IHScriptCustomAccessBehaviour {
	var __allowSetGet:Bool;
	var __allowPrivateAccess:Bool;

	public function hset(name:String, val:Dynamic):Dynamic;
	public function hget(name:String):Dynamic;

	public function __callGetter(name:String):Dynamic;
	public function __callSetter(name:String, val:Dynamic):Dynamic;
}