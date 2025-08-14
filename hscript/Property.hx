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
@:structInit
class Property {
	private static inline var GET = 'get_';
	private static inline var SET = 'set_';

	public var r:Dynamic;
	public var getter:FieldPropertyAccess;
	public var setter:FieldPropertyAccess;

	public var isStatic(get, never):Bool;
	function get_isStatic() {
		return __isStatic && interp.allowStaticVariables;
	}

	var isVar:Bool;
	var interp:Interp;

	public function new(r:Dynamic, getter:FieldPropertyAccess, setter:FieldPropertyAccess, isVar:Bool, isStatic:Bool, interp:Interp) {
		this.r = r;
		this.getter = getter;
		this.setter = setter;
		this.isVar = isVar;
		this.__isStatic = isStatic;
		this.interp = interp;
	}

	var __allowReadAccess:Bool = false;
	var __allowWriteAccess:Bool = false;
	var __allowSetGet:Null<Bool> = null;
	final __isStatic:Bool = false;

	public function callGetter(name:String) {
		switch (getter) {
			case AGet | ADynamic:
				var fName:String = '$GET$name';
				if (!__allowReadAccess && (__allowSetGet != null && __allowSetGet || !interp.isBypassAccessor)) {
					if (varExists(fName)) {
						return callAccessor(fName);
					} else
						interp.error(ECustom('Method $fName required by property $name is missing'));
				} else {
					if ((setter == ADefault || setter == ANull) || isVar)
						return r;
					else
						interp.error(ECustom('Field $name cannot be accessed because it is not a real variable${interp.isBypassAccessor ? '. Add @:isVar to enable it' : ''}'));
				}
			case ANever:
				interp.error(ECustom('This expression cannot be accessed for reading'));
			default:
		}

		return r;
	}

	public function callSetter(name:String, val:Dynamic) {
		switch (setter) {
			case ASet | ADynamic:
				var fName:String = '$SET$name';
				if (!__allowWriteAccess && (__allowSetGet != null && __allowSetGet || !interp.isBypassAccessor)) {
					if (varExists(fName))
						return callAccessor(fName, [val], true);
					else
						interp.error(ECustom('Method $fName required by property $name is missing'));
				} else {
					if ((getter == ADefault || getter == ANull) || isVar)
						return r = val;
					else
						interp.error(ECustom('Field $name cannot be accessed because it is not a real variable${interp.isBypassAccessor ? '. Add @:isVar to enable it' : ''}'));
				}
			case ANever:
				interp.error(ECustom('This expression cannot be accessed for writing'));
			default:
		}

		return r = val;
	}

	private function callAccessor(f:String, ?args:Array<Dynamic>, isWrite:Bool = false):Dynamic {
		var fn = isStatic ? interp.staticVariables.get(f) : interp.variables.get(f);
		var rt:Dynamic = null;
		if (fn != null && Reflect.isFunction(fn)) {
			if (isWrite) __allowWriteAccess = true;
			else __allowReadAccess = true;

			rt = UnsafeReflect.callMethodUnsafe(null, fn, args == null ? [] : args);

			if (isWrite) __allowWriteAccess = false;
			else __allowReadAccess = false;

			return rt;
		} else
			interp.error(ECustom('Method $f required by property ${f.substr(3)} is missing'));

		return rt;
	}

	private function varExists(n:String) {
		return isStatic ? interp.staticVariables.exists(n) : interp.variables.exists(n);
	}
}
