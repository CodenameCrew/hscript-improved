package hscript;

/**
 * Provides handlers for static custom class fields and instantiation.
 */
@:access(hscript.Property)
class CustomClassHandler implements IHScriptCustomConstructor implements IHScriptCustomAccessBehaviour{
	public var ogInterp:Interp;
	public var name:String;
	public var fields:Array<Expr>;
	public var extend:Null<String>;
	public var interfaces:Array<String>;

	public var cl:Dynamic;

	private var __interp:Interp;
	private var __staticFields:Array<String> = [];

	public var __allowSetGet:Bool = true;

	public function new(ogInterp:Interp, name:String, fields:Array<Expr>, ?extend:String, ?interfaces:Array<String>) {
		this.ogInterp = ogInterp;
		this.name = name;
		this.fields = fields;
		this.extend = extend;
		this.interfaces = interfaces;

		if(extend != null) {
			if(ogInterp.customClasses.exists(extend))
				this.cl = ogInterp.customClasses.get(extend);
			else 
				this.cl = Type.resolveClass('${extend}_HSX');

			if(cl == null)
				ogInterp.error(EInvalidClass(extend));
		}
		//this.cl = extend == null ? CustomTemplateClass : Type.resolveClass('${extend}_HSX');

		initStatic();
	}

	@:access(hscript.Interp)
	function initStatic() {
		__interp = new Interp();
		__interp.errorHandler = ogInterp.errorHandler;
		__interp.importFailedCallback = ogInterp.importFailedCallback;

		__interp.variables = ogInterp.variables;
		__interp.publicVariables = ogInterp.publicVariables;
		__interp.staticVariables = ogInterp.staticVariables;
		__interp.customClasses = ogInterp.customClasses;

		var validField:Bool = false;
		var staticField:Bool = false;
		var fieldName:String = "";
		for(ex in fields) {
			switch (Tools.expr(ex)) {
				case EVar(n, _, _, _, isStatic, _, _, _, _, _, _):
					validField = true;
					staticField = isStatic;
					fieldName = n;
				case EFunction(_, _, n, _, _, isStatic, _, _, _, _):
					validField = true;
					staticField = isStatic;
					fieldName = n;
				default:
					validField = false;
					staticField = false;
					fieldName = "";
			}

			if(staticField && validField) {
				__interp.exprReturn(ex);
				__staticFields.push(fieldName);
				fields.remove(ex);
			}
		}
	}

	public function hnew(args:Array<Dynamic>):Dynamic 
		return new CustomClass(this, args);

	@:allow(hscript.Interp)
	function hasField(name:String) {
        return __staticFields.contains(name);
    }

    function getField(name:String, allowProperty:Bool = true):Dynamic {
        var f = __interp.variables.get(name);
        if(f is Property && allowProperty) {
            var prop:Property = cast f;
            prop.__allowSetGet = this.__allowSetGet;
            var r = prop.callGetter(name);
            prop.__allowSetGet = null;
            return r;
        }
        return f;
    }

    function setField(name:String, val:Dynamic):Dynamic {
        var f = getField(name, false);
        if(f is Property) {
            var prop:Property = cast f;
            prop.__allowSetGet = this.__allowSetGet;
            var r = prop.callSetter(name, val);
            prop.__allowSetGet = null;
            return r;
        }
        __interp.variables.set(name, val);
        return val;
    }

	public function hget(name:String):Dynamic {
		if(hasField(name)) {
            return getField(name);
        }
		throw "field '"+ name+ "' does not exist in class '"+ this.name+ "'";
		return null;
	}

	public function hset(name:String, val:Dynamic):Dynamic {
		if(hasField(name))
			return setField(name, val);

		throw "field '"+ name+ "' does not exist in class '"+ this.name+ "'";
		return null;
	}

	// UNUSED
	public function __callGetter(name:String):Dynamic {
		return null;
	}

	public function __callSetter(name:String, val:Dynamic):Dynamic {
		return null;
	}

	public function toString():String {
		return name;
	}
}
/*
class CustomTemplateClass implements IHScriptCustomClassBehaviour {
	public var __interp:Interp;
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
*/

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
