package hscript;

import hscript.utils.UnsafeReflect;
import hscript.Interp;
import hscript.Expr.FieldPropertyAccess;

/**
 * Special variable that handles 'getter/setter' function calls
 * depending of the read/write access combination.
 * 
 * Example:
 * ```haxe
 * public var myvar(get, set):Int;
 * var _myvar:Int = 10;
 * 
 * function get_myvar():Int {
 *   return _myvar;
 * }
 * 
 * function set_myvar(val:Int):Int {
 *   if(val > 10) return _myvar = val;
 *   return val;
 * }
 * ```
 * 
 * @see https://haxe.org/manual/class-field-property.html
 */
@:access(hscript.Interp)
class Property {
	private static inline var GET = 'get_';
	private static inline var SET = 'set_';

	/**
	 * Name of the attached field.
	 */
	public final name:String;

	/**
	 * The current value. If isn't initialized, it's always `null`.
	 */
	public var r:Dynamic;

	/**
	 * The getter property kind
	 */
	public final getter:FieldPropertyAccess;

	/**
	 * The setter property kind
	 */
	public final setter:FieldPropertyAccess;

	/**
	 * If the field is declared as static.
	 */
	public var isStatic(get, never):Bool;
	function get_isStatic() {
		return __isStatic && interp.allowStaticVariables;
	}

	var isVar:Bool;
	var interp:Interp;

	@:allow(hscript.Interp)
	private var getterFunc(get, never):String;
	private inline function get_getterFunc():String {
		return '$GET$name';
	}

	@:allow(hscript.Interp)
	private var setterFunc(get, never):String;
	private inline function get_setterFunc():String {
		return '$SET$name';
	}

	public function new(name:String, r:Dynamic, getter:FieldPropertyAccess, setter:FieldPropertyAccess, isVar:Bool, isStatic:Bool, interp:Interp) {
		this.name = name;
		this.r = r;
		this.getter = getter;
		this.setter = setter;
		this.isVar = isVar;
		this.__isStatic = isStatic;
		this.interp = interp;
	}

	// Internal flags to gain access to the current field value (if isn't a property field)
	var __allowReadAccess:Bool = false;
	var __allowWriteAccess:Bool = false;
	// Internal flag to gain access if the field is accessed with @:bypassAccessor
	var __allowSetGet:Bool = true;

	final __isStatic:Bool = false;

	public function get(isBypassAccessor:Bool) {
		if(isBypassAccessor) __allowSetGet = false;
		var r:Dynamic = callGetter();
		if(isBypassAccessor) __allowSetGet = true;
		return r;
	}

	public function set(value:Dynamic, isBypassAccessor:Bool) {
		if(isBypassAccessor) __allowSetGet = false;
		var r:Dynamic = callSetter(value);
		if(isBypassAccessor) __allowSetGet = true;
		return r;
	}

	private function callGetter():Dynamic {
		switch (getter) {
			case AGet | ADynamic:
				var fName:String = getterFunc;
				if (!__allowReadAccess && __allowSetGet) {
					if (varExists(fName)) {
						return callAccessor(fName);
					} else
						interp.error(ECustom('Method $fName required by property $name is missing'));
				} else {
					if ((setter == ADefault || setter == ANull) || isVar) {
						return r;
					}
					else
						interp.error(ECustom('Field $name cannot be accessed because it is not a real variable${interp.isBypassAccessor ? '. Add @:isVar to enable it' : ''}'));
				}
			case ANever:
				interp.error(ECustom('This expression cannot be accessed for reading'));
			default:
		}

		return r;
	}

	private function callSetter(val:Dynamic):Dynamic {
		switch (setter) {
			case ASet | ADynamic:
				var fName:String = setterFunc;
				if (!__allowWriteAccess && __allowSetGet) {
					if (varExists(fName))
						return callAccessor(fName, val);
					else
						interp.error(ECustom('Method $fName required by property $name is missing'));
				} else {
					if ((getter == ADefault || getter == ANull) || isVar) {
						return r = val;
					}
					else
						interp.error(ECustom('Field $name cannot be accessed because it is not a real variable${interp.isBypassAccessor ? '. Add @:isVar to enable it' : ''}'));
				}
			case ANever:
				interp.error(ECustom('This expression cannot be accessed for writing'));
			default:
		}

		return r = val;
	}

	private function callAccessor(f:String, ?value:Dynamic):Dynamic {
		var fn = isStatic ? interp.staticVariables.get(f) : interp.variables.get(f);
		var rt:Dynamic = null;
		var isWrite:Bool = value != null;
		if (fn != null && Reflect.isFunction(fn)) {
			if (isWrite) __allowWriteAccess = true;
			else __allowReadAccess = true;

			rt = UnsafeReflect.callMethodUnsafe(null, fn, isWrite ? [value] : []);

			if (isWrite) __allowWriteAccess = false;
			else __allowReadAccess = false;

			return rt;
		} else
			interp.error(ECustom('Method $f required by property ${f.substr(3)} is missing'));

		return rt;
	}

	private inline function varExists(n:String) {
		return isStatic ? interp.staticVariables.exists(n) : interp.variables.exists(n);
	}
}
