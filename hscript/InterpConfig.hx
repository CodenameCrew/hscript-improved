package hscript;

class InterpConfig {
    // Automatic import redirect for certain classes
	public static var IMPORT_REDIRECTS(default, never) = [
		"Type" => "hscript.proxy.ProxyType"
	];
	
	// Incase an import fails
	// These are the module names
	@:unreflective public static var DISALLOW_IMPORT(default, never) = [
		"Type"
	];
}