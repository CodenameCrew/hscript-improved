package hscript.macros;

#if macro
import Type.ValueType;
import haxe.macro.ComplexTypeTools;
import haxe.macro.Expr;
import haxe.macro.Context;
import haxe.macro.Printer;
import haxe.macro.Compiler;

import hscript.Config;

using StringTools;

class AbstractHandler {
	public static function init() {
		#if HSCRIPT_ABSTRACT_SUPPORT
		#if !display
		if(Context.defined("display")) return;
		for(apply in Config.ALLOWED_ABSTRACT_AND_ENUM) {
			Compiler.addGlobalMetadata(apply, '@:build(hscript.macros.AbstractHandler.build())');
		}
		#end
		#end
	}

	public static function build():Array<Field> {
		var fields = Context.getBuildFields();
		var clRef = Context.getLocalClass();
		if (clRef == null) return fields;
		var cl = clRef.get();

		if (/* cl.name.startsWith("Flx") && */ cl.name.endsWith("_Impl_") && cl.params.length <= 0 && !cl.meta.has(":multiType") && !cl.name.contains("_HSC")) {
			var metas = cl.meta.get();

			var trimEnum = cl.name.substr(0, cl.name.length - 6);

			var key = cl.module;
			var fkey = cl.module + "." + trimEnum;
			if(key == "lime.system.Locale") return fields; // Error: Unknown identifier : currentLocale, Due to Func
			if(key == "cpp.Function") return fields; // Error: Unknown identifier : nativeGetProcAddress, Due to Func
			if(key == "haxe.ds.Vector") return fields; // Error: haxe.ds._Vector.VectorData<blit.T> has no field blit, Due to Func
			if(key == "haxe.display.Display") return fields; // Error: haxe.display.DisplayItemKind<haxe.display.DisplayLiteral<Dynamic>> has no field Null, Due to Func
			if(key == "cpp.Callable") return fields; // Error: cpp.Function.fromStaticFunction must be called on static function, Due to Func
			if(key == "haxe.display.JsonAnonStatusKind") return fields; // Error: cannot initialize a variable of type 'char *' with an rvalue of type 'const char *', Due to Func
			if(key == "cpp.CharStar") return fields; // Error: cannot initialize a variable of type 'char *' with an rvalue of type 'const char *', Due to Func
			if(Config.DISALLOW_ABSTRACT_AND_ENUM.contains(cl.module) || Config.DISALLOW_ABSTRACT_AND_ENUM.contains(fkey)) return fields;
			if(cl.module.contains("_")) return fields; // Weird issue, sorry

			var shadowClass = macro class {

			};
			shadowClass.kind = TDClass();
			shadowClass.params = switch(cl.params.length) {
				case 0:
					null;
				case 1:
					[{
						name: "T",
					}];
				default:
					[for(k=>e in cl.params) {
						name: "T" + Std.int(k+1)
					}];
			};
			shadowClass.name = '${cl.name.substr(0, cl.name.length - 6)}_HSC';

			var imports = Context.getLocalImports().copy();
			Utils.setupMetas(shadowClass, imports);
			//trace(cl.module);

			for(f in fields)
				switch(f.kind) {
					case FFun(fun):
						if (f.access.contains(AStatic)) {
							if (fun.expr != null) {
								fun.expr = macro @:privateAccess $e{fun.expr};
								shadowClass.fields.push(f);

								/*var trimEnum = cl.name.substr(0, cl.name.length - 6);

								var returns:Bool = !fun.ret.match(TPath({name: "Void"}));

								var name = f.name;

								var arguments = fun.args == null ? [] : [for(a in fun.args) macro $i{a.name}];

								var expr:Expr = Context.parse('${returns?"return " : ""} $trimEnum.$name(${[for(a in fun.args) a.name].join(", ")})', f.pos);

								var func:Function = {
									ret: fun.ret,
									params: fun.params.copy(),
									expr: expr,
									args: fun.args.copy()
								};

								var field:Field = {
									pos: f.pos,
									name: f.name,
									meta: f.meta,
									kind: FFun(func),
									doc: null,//f.doc,
									access: [APublic, AStatic]
								}
								shadowClass.fields.push(field);*/
							}
						}
					case FProp(get, set, t, e):
						if (get == "default" && (set == "never" || set == "null")) {
							shadowClass.fields.push(f);
						}
					case FVar(t, e):
						if (f.access.contains(AStatic) || cl.meta.has(":enum") || f.name.toUpperCase() == f.name) {
							var name:String = f.name;
							var enumType:String = cl.name;
							var pack = cl.module.split(".");

							//trace(pack, cl.name, name, cl.module);

							if(pack[pack.length - 1] == trimEnum)
								pack.pop();

							var complexType:ComplexType = t;
							if(complexType == null && e != null) {
								complexType = switch(e.expr) {
									case EConst(CRegexp(_)): TPath({ name: "EReg", pack: [] });

									default: null;
								}
							}
							if(complexType == null) {
								complexType = TPath({
									name: trimEnum,
									pack: [],//pack
								});
							}

							var code = Context.parse('@:privateAccess ($trimEnum.$name)', f.pos); // '${pack.join(".")}.${trimEnum}.$name'

							var field:Field = {
								pos: f.pos,
								name: f.name,
								meta: f.meta,
								kind: FVar(null, code),
								doc: f.doc,
								access: [APublic, AStatic]
							}

							shadowClass.fields.push(field);
						}
					default:
				}

			//var printer = new Printer();
			//for(field in shadowClass.fields)
			//	trace(printer.printField(field));

			Context.defineModule(cl.module, [shadowClass], imports);
		}

		return fields;
	}
}
#end