package hscript.utils;

class FieldsUtil {
    /**
     * Maps an array of field names into a lookup map (for `O(1)` time complexity membership checks).
    **/
    public static function setFields(map:Map<String, Bool>, fields:Array<String>) {
        for (f in fields) map.set(f, true);
    }
}
