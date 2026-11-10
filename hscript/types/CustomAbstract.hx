package hscript.types;

class CustomAbstract implements IHScriptAbstractBehaviour {

    public final name:String;
    public var v:Dynamic;

	public var hasOp:Bool;
    public final ops:Map<String, String> = [];
	public var hasArr:Bool;

    public function new(name:String, v:Dynamic) {
        this.name = name;
        this.v = v;
    }

    public function hget(name:String):Dynamic {
        throw new haxe.exceptions.NotImplementedException();
    }

    public function hset(name:String, val:Dynamic):Dynamic {
        throw new haxe.exceptions.NotImplementedException();
    }

    public function harrayset(key:Dynamic, val:Dynamic):Dynamic {
        throw new haxe.exceptions.NotImplementedException();
    }

    public function harrayget(key:Dynamic):Dynamic {
        throw new haxe.exceptions.NotImplementedException();
    }

    public function hop(kind:String, a:Dynamic, ?b:Dynamic):Dynamic {
        throw new haxe.exceptions.NotImplementedException();
    }

    
}