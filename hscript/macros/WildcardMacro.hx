package hscript.macros;

#if !hscriptNoWildcardImports
import haxe.ds.StringMap;
import haxe.rtti.Meta;

#if macro
import haxe.macro.Context;
import haxe.macro.Expr;
#end

using StringTools;

/** @author hackx2 **/
@:keep
final class WildcardMacro { // uses rtti to store type names
	static final INDEX_META_NAME= "__indexed_types";
	static final SEPARATOR = '~';
	#if macro
	static var __has_gen = false;
	#end

	public static macro function getTypes() {
		#if macro
		if(!__has_gen) {
			__has_gen = true;
			Context.onGenerate(_ -> {
				switch Context.getType('hscript.macros.WildcardMacro') {
					case TInst(t, _):
						final meta = t.get().meta;
						if(!meta.has(INDEX_META_NAME)) {
							final arr:Array<Expr> = [
								macro $v {
									[
										for(i in Context.getAllModuleTypes()) {
											final typeName = switch i {
												case TClassDecl(cls):
													cls.toString();
												case TEnumDecl(enum_):
													enum_.toString();
												case _: null;
											}

											if(typeName != null && !typeName.endsWith('_Fields_') && !typeName.endsWith('_Impl_') && !typeName.endsWith(ClassExtendMacro.CLASS_SUFFIX)) {
												typeName;
											}
										}
									].join(SEPARATOR)
								}
							];

							meta.add(INDEX_META_NAME, arr,Context.currentPos());
						}
					case _: // nothin
				}
			});
		}
		#end

		return macro {
			final types = new haxe.ds.StringMap<Array<String>>();

			final rttiType = haxe.rtti.Meta.getType(hscript.macros.WildcardMacro);
			final raw:Dynamic = Reflect.field(rttiType, $v{INDEX_META_NAME});

			if(raw != null) {
				for (t in (raw[0] : String).split($v{SEPARATOR})) {
					final dot = t.lastIndexOf('.');
					final pack = dot == -1 ? '' : t.substr(0, dot);
					final name = t.substr(dot + 1); 

					final type_pack = types.get(pack);
					if (type_pack == null) types.set(pack, [name]) else type_pack.push(name);
				}
			}
			
			types;
		}
	}
}
#end