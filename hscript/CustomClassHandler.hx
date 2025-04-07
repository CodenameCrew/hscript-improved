package hscript;

import hscript.Interp.DeclaredVar;
import hscript.utils.UnsafeReflect;
using StringTools;

@:deprecated('Switch to new Custom Class instead')
class CustomClassHandler implements IHScriptCustomConstructor {
	public static var staticHandler = new StaticHandler();

	public var ogInterp:Interp;
	public var name:String;
	public var fields:Array<Expr>;
	public var extend:String;
	public var interfaces:Array<String>;

	public var cl:Class<Dynamic>;

	public function new(ogInterp:Interp, name:String, fields:Array<Expr>, ?extend:String, ?interfaces:Array<String>) {
		this.ogInterp = ogInterp;
		this.name = name;
		this.fields = fields;
		this.extend = extend;
		this.interfaces = interfaces;

		this.cl = extend == null ? CustomTemplateClass : Type.resolveClass('${extend}_HSX');
		if(cl == null)
			ogInterp.error(EInvalidClass(extend));
	}

	public function hnew(args:Array<Dynamic>):Dynamic {
		// TODO: clean this up, it sucks, i hate it
		// TODO: make static vars work correctly
		var interp = new Interp();

		interp.errorHandler = ogInterp.errorHandler;

		var _class:IHScriptCustomClassBehaviour = Type.createInstance(cl, args);

		//var __capturedLocals = ogInterp.duplicate(ogInterp.locals);
		//var capturedLocals:Map<String, DeclaredVar> = [];
		//for(k=>e in __capturedLocals)
		//	if (e != null && e.depth <= 0)
		//		capturedLocals.set(k, e);

		var disallowCopy = Type.getInstanceFields(cl);

		_class.__real_fields = disallowCopy;

		// todo: make it so you can use variables from the same scope as where the class was defined

		//for (key => value in capturedLocals) {
		//	if(!disallowCopy.contains(key)) {
		//		interp.locals.set(key, {r: value, depth: -1});
		//	}
		//}
		for (key => value in ogInterp.variables) {
			if(!disallowCopy.contains(key)) {
				interp.variables.set(key, value);
			}
		}
		for(key => value in ogInterp.customClasses) {
			if(!disallowCopy.contains(key)) {
				interp.customClasses.set(key, value);
			}
		}
		// todo: clone static vars, but make it so setting it only sets it on the class
		// todo: clone public vars

		//trace("Before: " + [for(key => value in interp.variables) key]);

		interp.variables.set("super", staticHandler);

		var comparisonMap:Map<String, Dynamic> = [];
		for(key => value in interp.variables) {
			comparisonMap.set(key, value);
		}

		_class.__custom__variables = interp.variables;

		//trace(fields);
		for(expr in fields) {
			@:privateAccess
			interp.exprReturn(expr);
		}

		//trace("After: " + [for(key => value in interp.variables) key]);

		// get only variables that were not set before
		var classVariables = [
			for(key => value in interp.variables)
				if(!comparisonMap.exists(key) || comparisonMap[key] != value)
					key => value
		];
		//for(variable => value in classVariables) {
		//	if(variable == "this" || variable == "super" || variable == "new") continue;
		//	@:privateAccess
		//	if(!interp.__instanceFields.contains(variable)) {
		//		interp.__instanceFields.push(variable);
		//	}
		//}

		_class.__class__fields = [for(key => value in classVariables) key];

		//trace(_class.__class__fields);
		//@:privateAccess
		//trace(interp.__instanceFields);

		_class.__interp = interp;
		_class.__allowSetGet = false;
		interp.scriptObject = _class;

		for(variable => value in interp.variables) {
			if(variable == "this" || variable == "super" || variable == "new") continue;

			if(variable.startsWith("set_") || variable.startsWith("get_")) {
				_class.__allowSetGet = true;
			}
		}

		var newFunc = interp.variables.get("new");
		if(newFunc != null) {
			var comparisonMap:Map<String, Dynamic> = [];
			for(key => value in interp.variables) {
				comparisonMap.set(key, value);
			}

			UnsafeReflect.callMethodUnsafe(null, newFunc, args);

			// get only variables that were not set before
			var classVariables = [
				for(key => value in interp.variables)
					if(!comparisonMap.exists(key) || comparisonMap[key] != value)
						key => value
			];
			for(variable => value in classVariables) {
				if(variable == "this" || variable == "super" || variable == "new") continue;
				@:privateAccess
				if(!interp.__instanceFields.contains(variable)) {
					interp.__instanceFields.push(variable);
				}
				if(!_class.__class__fields.contains(variable)) {
					_class.__class__fields.push(variable);
				}
			}
		}


		return _class;
	}

	public function toString():String {
		return name;
	}
}

class CustomTemplateClass implements IHScriptCustomClassBehaviour implements IHScriptCustomAccessBehaviour {
	public var __interp:Interp;
	public var __customClass:hscript.customclass.CustomClass;
	public var __allowSetGet:Bool = true;
	public var __custom__variables:Map<String, Dynamic>;
	public var __real_fields:Array<String>;
	public var __class__fields:Array<String>;

	public function hset(name:String, val:Dynamic):Dynamic {
		if(__allowSetGet && __custom__variables.exists("set_" + name))
			return __callSetter(name, val);
		if (__custom__variables.exists(name)) {
			__custom__variables.set(name, val);
			return val;
		}
		if(__real_fields.contains(name)) {
			UnsafeReflect.setProperty(this, name, val);
			return UnsafeReflect.field(this, name);
		}
		__custom__variables.set(name, val);
		return val;
	}
	public function hget(name:String):Dynamic {
		if(__allowSetGet && __custom__variables.exists("get_" + name))
			return __callGetter(name);
		if (__custom__variables.exists(name))
			return __custom__variables.get(name);

		return UnsafeReflect.getProperty(this, name);
	}

	public function __callGetter(name:String):Dynamic {
		__allowSetGet = false;
		var v = __custom__variables.get("get_" + name)();
		__allowSetGet = true;
		return v;
	}

	public function __callSetter(name:String, val:Dynamic):Dynamic {
		__allowSetGet = false;
		var v = __custom__variables.get("set_" + name)(val);
		__allowSetGet = true;
		return v;
	}
}


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

final class StaticHandler {
	public function new() {}
}