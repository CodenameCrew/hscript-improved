package hscript;

import hscript.behaviours.IHScriptCustomAccessBehaviour;
import hscript.behaviours.IHScriptCustomBehaviour;
import hscript.Interp;

/**
 * This is for backwards compatibility with old hscript-improved, since some scripts use it
**/
@:dox(hide)
@:keep
class TemplateClass implements IHScriptCustomBehaviour implements IHScriptCustomAccessBehaviour {
	public var __interp:Interp;
	public var __allowSetGet:Bool = true;

	public function hset(name:String, val:Dynamic):Dynamic {
		var variables = __interp.variables;
		if(__allowSetGet && variables.exists("set_" + name))
			return __callSetter(name, val);
		variables.set(name, val);
		return val;
	}
	public function hget(name:String):Dynamic {
		var variables = __interp.variables;
		if(__allowSetGet && variables.exists("get_" + name))
			return __callGetter(name);
		return variables.get(name);
	}

	public function __callGetter(name:String):Dynamic {
		__allowSetGet = false;
		var v = __interp.variables.get("get_" + name)();
		__allowSetGet = true;
		return v;
	}

	public function __callSetter(name:String, val:Dynamic):Dynamic {
		__allowSetGet = false;
		var v = __interp.variables.get("set_" + name)(val);
		__allowSetGet = true;
		return v;
	}
}
