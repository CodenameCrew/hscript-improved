package hscript.behaviours;

// Soon...
interface IHScriptAbstractBehaviour extends IHScriptCustomBehaviour {
    public var hasOp:Bool;
    public var hasArr:Bool;
    // @:op(A * B), @:op(A++), etc...
    public function hop(kind:String, a:Dynamic, ?b:Dynamic):Dynamic;

    public function harrayget(key:Dynamic):Dynamic;
    public function harrayset(key:Dynamic, val:Dynamic):Dynamic;
}