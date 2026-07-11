package hscript.utils;

@:structInit
class UsingEntry  {
	public var call:Dynamic->String->Array<Dynamic>->Dynamic;
	public var fields:Array<String>;

	public function hasField(name:String) {
		return fields.contains(name);
	}
}

/**
 * Special class that handles static extension function calls. 
 * 
 * A static extension allows pseudo-extending 
 * existing types without modifying their source.
 * In Haxe this is achieved by declaring a static method with a first argument 
 * of the extending type and then bringing the defining class into context through `using`.
 * 
 * Example:
 * ```haxe
 * class IntExtender {
 * 	static public function triple(i:Int) {
 * 	 	return i * 3;
 * 	}
 * }
 * 
 * using IntExtender;
 * 
 * trace(12.triple()); // 36
 * ```
 * 
 * @see https://haxe.org/manual/lf-static-extension.html
 */
class UsingHandler { 
	// Predefined static extension classes
	public static final defaultExtension:Map<String, UsingEntry> = [
		"StringTools" => { // https://github.com/pisayesiwsi/hscript-iris/blob/dev/crowplexus/iris/Iris.hx#L45
			fields: Type.getClassFields(StringTools),
			call: function(o:Dynamic, f:String, args:Array<Dynamic>):Dynamic {
				if (f == "isEof") // has @:noUsing
					return null;
				return switch (Type.typeof(o)) {
					case TInt if (f == 'hex'):
						StringTools.hex(o, args[0]);
					case TClass(String):
						var field = UnsafeReflect.field(StringTools, f);
						if (UnsafeReflect.isFunction(field)) UnsafeReflect.callMethodUnsafe(StringTools, field, [o].concat(args)); else null;
					default:
						null;
				}
			}
		},
		"Lambda" => { // https://github.com/pisayesiwsi/hscript-iris/blob/dev/crowplexus/iris/Iris.hx#L62
			fields: Type.getClassFields(Lambda),
			call: function(o:Dynamic, f:String, args:Array<Dynamic>):Dynamic {
				if (o != null && o.iterator != null) {
					var field = UnsafeReflect.field(Lambda, f);
					if (UnsafeReflect.isFunction(field)) {
						return UnsafeReflect.callMethodUnsafe(Lambda, field, [o].concat(args));
					}
				}
				return null;
			}
		}
	];

	@:allow(hscript.expr.CustomClass)
	@:allow(hscript.expr.CustomClassHandler)
	public var usingEntries(default, null):Map<String, UsingEntry> = [];

	public function new() {}

	public function registerEntry(name:String, entry:Dynamic->String->Array<Dynamic>->Dynamic, fields:Array<String>) {
		usingEntries.set(name, {call: entry, fields: fields});
	}

	public inline function entryExists(name:String):Bool {
		return usingEntries.exists(name);
	}
}
