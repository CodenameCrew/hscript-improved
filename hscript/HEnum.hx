package hscript;

import hscript.utils.UnsafeReflect;

/**
 * Wrapper class for enums, both for real and scripted.
 * Use EnumTools and EnumValueTools for enum operations.
 */
@:structInit
class HEnum implements IHScriptCustomBehaviour {
	var enumValues(default, null) = {};

	public function setEnum(name:String, enumValue:Dynamic):Void {
		UnsafeReflect.setField(enumValues, name, enumValue);
	}

	public function getEnum(name:String):Null<Dynamic> {
		if (UnsafeReflect.hasField(enumValues, name))
			return UnsafeReflect.field(enumValues, name);
		return null;
	}

	public function getEnumValues():Dynamic {
		return enumValues;
	}

	public function hget(name:String):Dynamic {
		return getEnum(name);
	}

	public function hset(name:String, val:Dynamic):Dynamic {
		return null;
	}
}

@:nullSafety
@:structInit
class HEnumValue {
	public var enumName:String;
	public var fieldName:String;
	public var index:Int;
	public var args:Array<Dynamic>;

	public function toString():String {
		return '$enumName.$fieldName${args.length > 0 ? '(${[for (a in args) a].join(", ")})' : ''}';
	}

	public inline function getEnumName():String
		return this.enumName;

	public inline function getConstructorArgs():Array<Dynamic>
		return this.args;

	public function compare(other:HEnumValue):Bool {
		if (enumName != other.enumName || fieldName != other.fieldName)
			return false;
		if (args.length == 0 && other.args.length == 0)
			return true;
		if (args.length == 0 || other.args.length == 0)
			return false;
		if (args.length != other.args.length)
			return false;

		for (i in 0...args.length)
			if (args[i] != other.args[i])
				return false;

		return true;
	}
}

@:nullSafety
class EnumTools {
	public static function getConstructors(e:Dynamic):Array<String> {
		if(Std.isOfType(e, HEnum)) {
			var henum:HEnum = cast e;
			return UnsafeReflect.fields(henum.getEnumValues());
		}
		return Type.getEnumConstructs(cast e);
	}

	public static function createByName(e:Dynamic, constr:String, ?params:Array<Dynamic>):Dynamic {
		if(Std.isOfType(e, HEnum)) {
			var henum:HEnum = cast e;
			var constructor = henum.getEnum(constr);
			if(constructor == null)
				throw 'Constructor $constr not found in enum';
			if(Std.isOfType(constructor, HEnumValue))
				return constructor;
			if(Reflect.isFunction(constructor))
				return constructor(params == null ? [] : params);
			throw 'Invalid constructor type';
		}
		return Type.createEnum(cast e, constr, params);
	}

	public static function createByIndex(e:Dynamic, index:Int, ?params:Array<Dynamic>):Dynamic {
		if(Std.isOfType(e, HEnum)) {
			var constructors = getConstructors(e);
			if(index < 0 || index >= constructors.length)
				throw 'Index $index out of bounds for enum';
			return createByName(e, constructors[index], params);
		}
		return Type.createEnumIndex(cast e, index, params);
	}
}

@:nullSafety
class EnumValueTools {
	public static function getType(e:Dynamic):Null<String> {
		if(Std.isOfType(e, HEnumValue)) {
			var hv:HEnumValue = cast e;
			return hv.enumName;
		}
		var en = Type.getEnum(e);
		if(en != null)
			return Type.getEnumName(en);
		return null;
	}

	public static function getName(e:Dynamic):String {
		if(Std.isOfType(e, HEnumValue)) {
			var hv:HEnumValue = cast e;
			return hv.fieldName;
		}
		return Type.enumConstructor(e);
	}

	public static function getParameters(e:Dynamic):Array<Dynamic> {
		if(Std.isOfType(e, HEnumValue)) {
			var hv:HEnumValue = cast e;
			return hv.args.copy();
		}
		return Type.enumParameters(e);
	}

	public static function getIndex(e:Dynamic):Int {
		if(Std.isOfType(e, HEnumValue)) {
			var hv:HEnumValue = cast e;
			return hv.index;
		}
		return Type.enumIndex(e);
	}

	public static function equals(a:Dynamic, b:Dynamic):Bool {
		if(Std.isOfType(a, HEnumValue) && Std.isOfType(b, HEnumValue)) {
			var hva:HEnumValue = cast a;
			var hvb:HEnumValue = cast b;
			return hva.compare(hvb);
		}
		return Type.enumEq(a, b);
	}

	public static function match(e:Dynamic, pattern:Dynamic):Bool {
		if(Std.isOfType(e, HEnumValue)) {
			var hv:HEnumValue = cast e;
			if(Std.isOfType(pattern, HEnumValue)) {
				var hp:HEnumValue = cast pattern;
				if(hv.enumName != hp.enumName || hv.fieldName != hp.fieldName)
					return false;
				if(hp.args.length == 0)
					return true;
				if(hv.args.length != hp.args.length)
					return false;
				for(i in 0...hp.args.length) {
					var pa = hp.args[i];
					if(pa != null && hv.args[i] != pa)
						return false;
				}
				return true;
			}
			if(Reflect.isObject(pattern)) {
				var patternName = UnsafeReflect.hasField(pattern, "name") ? UnsafeReflect.field(pattern, "name") : null;
				if(patternName != null && patternName != hv.fieldName)
					return false;
				return true;
			}
			return false;
		}
		return Type.enumEq(e, pattern);
	}
}
