package hscript.utils;

#if !hscriptNoWildcardImports
import haxe.ds.StringMap;
import hscript.macros.WildcardMacro;

class TypeListRegistry {
    static var list(default, null):StringMap<Array<String>>;
    public static function get(pkg:String) {
        final map = list ??= WildcardMacro.getTypes();
        return map != null ? map.get(pkg) : null;
    }
}
#end