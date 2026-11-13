package hscript;

/**
 * Special Interface to make a class usable for Custom Classes.
 */
interface IHScriptCustomClassBehaviour extends IHScriptCustomAccessBehaviour{
	public var __interp:Interp;
	// TODO: use Map instead of Arrays
	public var __real_fields:Array<String>;
	public var __class__fields:Array<String>;

}