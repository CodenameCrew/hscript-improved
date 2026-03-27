package hscript;

class OptimizerStats {
	public var totalPasses:Int = 0;
	public var skippedPasses:Int = 0;
	public var totalTime:Float = 0.0;
	public var totalPassTime:Float = 0.0;
	public var passTimes:Array<Float> = [];
	
	public var cacheHits:Int = 0;
	public var cacheMisses:Int = 0;
	
	public var constCount:Int = 0;
	public var identCount:Int = 0;
	public var varCount:Int = 0;
	public var blockCount:Int = 0;
	public var parentCount:Int = 0;
	public var fieldCount:Int = 0;
	public var binopCount:Int = 0;
	public var unopCount:Int = 0;
	public var callCount:Int = 0;
	public var ifCount:Int = 0;
	public var whileCount:Int = 0;
	public var doWhileCount:Int = 0;
	public var forCount:Int = 0;
	public var breakCount:Int = 0;
	public var continueCount:Int = 0;
	public var functionCount:Int = 0;
	public var returnCount:Int = 0;
	public var arrayCount:Int = 0;
	public var arrayDeclCount:Int = 0;
	public var newCount:Int = 0;
	public var throwCount:Int = 0;
	public var tryCount:Int = 0;
	public var objectCount:Int = 0;
	public var ternaryCount:Int = 0;
	public var switchCount:Int = 0;
	public var metaCount:Int = 0;
	public var checkTypeCount:Int = 0;
	public var enumCount:Int = 0;
	public var castCount:Int = 0;
	public var regexCount:Int = 0;
	public var classCount:Int = 0;
	
	public var folds:Int = 0;
	public var simplifications:Int = 0;
	public var branchOptimizations:Int = 0;
	public var deadCodeEliminations:Int = 0;
	public var finalConstantReplacements:Int = 0;
	public var cseEliminations:Int = 0;

	public function new() {}

	public function reset():Void {
		totalPasses = 0;
		skippedPasses = 0;
		totalTime = 0.0;
		totalPassTime = 0.0;
		passTimes = [];
		cacheHits = 0;
		cacheMisses = 0;
		
		constCount = 0;
		identCount = 0;
		varCount = 0;
		blockCount = 0;
		parentCount = 0;
		fieldCount = 0;
		binopCount = 0;
		unopCount = 0;
		callCount = 0;
		ifCount = 0;
		whileCount = 0;
		doWhileCount = 0;
		forCount = 0;
		breakCount = 0;
		continueCount = 0;
		functionCount = 0;
		returnCount = 0;
		arrayCount = 0;
		arrayDeclCount = 0;
		newCount = 0;
		throwCount = 0;
		tryCount = 0;
		objectCount = 0;
		ternaryCount = 0;
		switchCount = 0;
		metaCount = 0;
		checkTypeCount = 0;
		enumCount = 0;
		castCount = 0;
		regexCount = 0;
		classCount = 0;
		
		folds = 0;
		simplifications = 0;
		branchOptimizations = 0;
		deadCodeEliminations = 0;
		finalConstantReplacements = 0;
		cseEliminations = 0;
	}

	public function getSummary():String {
		var totalExprs = constCount + identCount + varCount + blockCount + parentCount + 
			fieldCount + binopCount + unopCount + callCount + ifCount + whileCount + 
			doWhileCount + forCount + functionCount + arrayCount + arrayDeclCount + 
			newCount + throwCount + tryCount + objectCount + ternaryCount + switchCount + 
			metaCount + checkTypeCount + enumCount + castCount + regexCount + classCount;
		
		return 'Optimizer Stats:
  Passes: $totalPasses (skipped: $skippedPasses)
  Time: ${totalTime}ms
  Cache: $cacheHits hits, $cacheMisses misses
  Expressions processed: $totalExprs
  Folds: $folds
  Simplifications: $simplifications
  Branch optimizations: $branchOptimizations
  Dead code eliminations: $deadCodeEliminations
  Final constant replacements: $finalConstantReplacements
  CSE eliminations: $cseEliminations';
	}
}
