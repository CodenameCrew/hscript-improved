package hscript.behaviours;

/**
 * Special Interface for handling field access behaviour.
 * Basically works like the operator overload `@:op(a.b)`
 * for an abstract.
 */
interface IHScriptCustomBehaviour {
	/**
	 * Field Write Access
	 * @param name - Field Name
	 * @param val - Value to assign
	 * @return Dynamic - The assigned value
	 */
	public function hset(name:String, val:Dynamic):Dynamic;
	
	/**
	 * Field Read Access
	 * @param name - Field Name
	 * @return Dynamic - The returned field
	 */
	public function hget(name:String):Dynamic;
}