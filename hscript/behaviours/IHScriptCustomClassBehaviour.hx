package hscript.behaviours;

/**
 * Special Interface to make a class usable for Custom Classes.
 */
interface IHScriptCustomClassBehaviour extends IHScriptCustomAccessBehaviour{
	public var __interp:Interp;
	public var __real_fields:Array<String>;
	public var __class__fields:Array<String>;

}