package hscript;

/**
 * Color Scheme to use for colorize. Make a class that extends this to customize it.
 */
class ColorScheme {
	public var keyword:Int = 0x8080FF;
	public var specialIdent:Int = 0xC0C0FF;
	public var comment:Int = 0x80E080;
	public var braces:Int = 0xC08080;
	public var parents:Int = 0xC0B0B0;
	public var string:Int = 0xFFA0A0;
	public var constant:Int = 0xB0F0B0;
	public var operand:Int = 0xC0B0B0;

	public function new() {}
}

class Colorizer extends Parser {

	private static final KEYWORDS = [
		for (k in "for|if|else|switch|case|var|final|while|do|function|return|break|continue|inline|new|throw|try|catch|default|cast|in|override|static|public|private|package|import|using|class|enum|abstract".split("|"))
			k => true
	];
	private static final IDENTS = [for (k in "true|false|null|this|super".split("|")) k => true];

	public var color:ColorScheme;

	var segs:Array<Int>;
	var startPos:Int;
	var defaultColor:Int;
	var inComment:Bool;
	var lastPos:Int;

	public function new(?color:ColorScheme) {
		this.color = color ?? new ColorScheme();
		super();
	}

	public function getColorSegments(code:String, defaultColor:Int) {
		resumeErrors = true;
		this.defaultColor = defaultColor;
		segs = [];
		parseString(code);
		var prev = segs;
		segs.resize(0);
		segs = null;
		return prev;
	}

	function addSeg(color:Int) {
		var prev = segs.length == 0 ? -1 : segs[segs.length - 2];
		if (prev == startPos) {
			segs.pop();
			segs.pop();
			prev = segs[segs.length - 2];
		}
		if (prev >= startPos)
			return;
		segs.push(startPos);
		segs.push(color);
		segs.push(getPos());
		segs.push(defaultColor);
	}

	inline function getPos() {
		return readPos - (this.char == -1 ? 0 : 1);
	}

	override function tokenComment(op, char) {
		inComment = true;
		var tk = super.tokenComment(op, char);
		inComment = false;
		return tk;
	}
	#if hscriptPos
	override function _token():hscript.Parser.Token
	#else
	override function token():hscript.Parser.Token
	#end
	{
		if (inComment) {
			addSeg(color.comment);
			inComment = false;
		}
		startPos = getPos();
		final tk = #if hscriptPos super._token() #else super.token() #end;
		switch (tk) {
			case TId(id) if (KEYWORDS.exists(id)):
				addSeg(color.keyword);
			case TId(id) if (IDENTS.exists(id)):
				addSeg(color.specialIdent);
			case TBrOpen, TBrClose:
				addSeg(color.braces);
			case TPOpen, TPClose:
				addSeg(color.parents);
			case TConst(c):
				switch (c) {
					case CString(_): addSeg(color.string);
					default: addSeg(color.constant);
				}
			case TOp(_):
				addSeg(color.operand);
			default:
		}
		return tk;
	}
}