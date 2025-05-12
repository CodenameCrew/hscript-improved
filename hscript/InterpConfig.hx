package hscript;

class InterpConfig {
    // Automatic import redirect for certain classes
	public static final IMPORT_REDIRECTS = [
		"Type" => "hscript.proxy.ProxyType"
	];
	
	// Incase an import fails
	// These are the module names
	@:unreflective 
	public static final DISALLOW_IMPORT = [
		"Type"
	];
}