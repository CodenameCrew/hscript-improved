package hscript;

import haxe.ds.StringMap;
import haxe.ds.IntMap;
import hscript.Expr;
import StringTools;

class Optimizer {
	public var enabled:Bool = true;
	public var optimizeLevel:Int = 4;
	
	public var enableConstantFolding:Bool = true;
	public var enableExpressionSimplification:Bool = true;
	public var enableDeadCodeElimination:Bool = true;
	public var enableBranchOptimization:Bool = true;
	public var enableCSE:Bool = false; // Need to fix a rare case where side effects occur.
	public var enableCache:Bool = false;
	
	public var debug:Bool = false;
	public var debugPrinter:Printer;
	
	private var optimizationCache:StringMap<Expr>;
	private var exprHashes:IntMap<Int>;
	private var stats:OptimizerStats;
	private var finalConstants:Array<Expr>;
	private var finalConstantIds:StringMap<Int>;
	private var cseCounter:Int;
	private var exprIdCounter:Int;
	private var hashCounter:Int;

	public function new() {
		optimizationCache = new StringMap();
		exprHashes = new IntMap();
		if (debug) stats = new OptimizerStats();
		finalConstants = [];
		finalConstantIds = new StringMap();
		cseCounter = 0;
		exprIdCounter = 0;
		hashCounter = 1;
	}

	public function optimize(expr:Expr):Expr {
		if (!enabled) return expr;
		
		if (debug) {
			if (stats == null) stats = new OptimizerStats();
			stats.reset();
		}
		finalConstants = [];
		finalConstantIds = new StringMap();
		cseCounter = 0;
		exprIdCounter = 0;
		hashCounter = 1;
		
		if (debug) {
			debugPrinter = new Printer();
			trace("=== HScript Optimizer Debug ===");
			trace("Optimization Level: " + optimizeLevel);
			trace("Constant Folding: " + enableConstantFolding);
			trace("Expression Simplification: " + enableExpressionSimplification);
			trace("Dead Code Elimination: " + enableDeadCodeElimination);
			trace("Branch Optimization: " + enableBranchOptimization);
			trace("CSE: " + enableCSE);
			trace("\n--- Original Code ---");
			trace(debugPrinter.exprToString(expr));
		}
		
		var result = expr;
		
		for (i in 0...optimizeLevel) {
			optimizationCache = new StringMap();
			exprHashes = new IntMap();
			finalConstants = [];
			finalConstantIds = new StringMap();
			
			var beforeHash = getExprHash(result);
			
			if (debug) {
				var passStart = haxe.Timer.stamp();
				result = optimizeOnce(result);
				var afterHash = getExprHash(result);
				var passTime = (haxe.Timer.stamp() - passStart) * 1000;
				stats.totalPassTime += passTime;
				stats.passTimes.push(passTime);
				var optimizedCount = if (beforeHash != afterHash) "changed" else "unchanged";
				var afterStr = debugPrinter.exprToString(result);
				trace("\n--- Pass " + (i + 1) + " (" + passTime + " ms, " + optimizedCount + ") ---");
				trace(afterStr);
				stats.totalPasses++;
				if (beforeHash == afterHash) {
					stats.skippedPasses++;
					trace("\n--- No changes in pass " + (i + 1) + ", stopping early ---");
					break;
				}
			} else {
				result = optimizeOnce(result);
				if (beforeHash == getExprHash(result)) {
					break;
				}
			}
		}
		
		if (debug) {
			stats.totalTime = stats.totalPassTime;
			trace(stats.getSummary());
			trace("=== End Debug ===\n");
		}
		
		return result;
	}

	private function getExprHash(expr:Expr):Int {
		#if hscriptPos
		var id = expr.pmin;
		#else
		var id = exprIdCounter++;
		#end
		
		if (exprHashes.exists(id)) {
			return exprHashes.get(id);
		}
		
		var hash = computeExprHash(expr);
		exprHashes.set(id, hash);
		return hash;
	}

	private inline function hashCombine(a:Int, b:Int):Int {
		#if cpp
		return untyped __cpp__("({0} * 31 + {1}) & 0x7FFFFFFF", a, b);
		#else
		return ((a * 31) + b) & 0x7FFFFFFF;
		#end
	}

	private inline function hashString(s:String):Int {
		var h:Int = 0;
		for (i in 0...s.length) {
			var c:Int = s.charCodeAt(i);
			#if cpp
			h = untyped __cpp__("(({0} << 5) - {0} + {1}) & 0x7FFFFFFF", h, c);
			#else
			h = ((h << 5) - h + c) & 0x7FFFFFFF;
			#end
		}
		return h;
	}

	private function computeExprHash(expr:Expr):Int {
		var h:Int;
		return switch (Tools.expr(expr)) {
			case EConst(c):
				switch(c) {
					case CInt(v): hashCombine(1, v);
					case CFloat(f): hashCombine(2, Std.int(f * 1000));
					case CString(s, _): hashCombine(3, hashString(s));
				}
			case EIdent(id): hashCombine(4, hashString(id));
			case EPackage(name): hashCombine(5, hashString(name));
			case EImport(c): hashCombine(6, hashString(c));
			case EClass(name, fields, extend, interfaces, isFinal): 
				h = hashCombine(7, hashString(name));
				hashCombine(h, fields.length);
			case EVar(n, t, e, isPublic, isStatic, isPrivate, isFinal, isInline, get, set, isVar):
				h = hashCombine(8, hashString(n));
				e != null ? hashCombine(h, getExprHash(e)) : h;
			case EParent(e): hashCombine(9, getExprHash(e));
			case EBlock(exprs): 
				h = 10;
				for (e in exprs) h = hashCombine(h, getExprHash(e));
				h;
			case EField(e, f, s):
				hashCombine(hashCombine(11, getExprHash(e)), hashString(f));
			case EBinop(op, e1, e2):
				hashCombine(hashCombine(hashCombine(12, hashString(op)), getExprHash(e1)), getExprHash(e2));
			case EUnop(op, prefix, e):
				hashCombine(hashCombine(hashCombine(13, hashString(op)), prefix ? 1 : 0), getExprHash(e));
			case ECall(e, params):
				h = hashCombine(14, getExprHash(e));
				for (p in params) h = hashCombine(h, getExprHash(p));
				h;
			case EIf(cond, e1, e2):
				h = hashCombine(15, getExprHash(cond));
				h = hashCombine(h, getExprHash(e1));
				e2 != null ? hashCombine(h, getExprHash(e2)) : h;
			case EWhile(cond, e):
				hashCombine(hashCombine(16, getExprHash(cond)), getExprHash(e));
			case EDoWhile(cond, e):
				hashCombine(hashCombine(17, getExprHash(cond)), getExprHash(e));
			case EFor(v, it, e, ithv):
				hashCombine(hashCombine(hashCombine(18, hashString(v)), getExprHash(it)), getExprHash(e));
			case EBreak: 19;
			case EContinue: 20;
			case EFunction(args, e, name, ret, isPublic, isStatic, isOverride, isPrivate, isFinal, isInline):
				h = hashCombine(21, name != null ? hashString(name) : 0);
				hashCombine(h, getExprHash(e));
			case EReturn(e):
				e != null ? hashCombine(22, getExprHash(e)) : 22;
			case EArray(e, index):
				hashCombine(hashCombine(23, getExprHash(e)), getExprHash(index));
			case EArrayDecl(exprs):
				h = 24;
				for (e in exprs) h = hashCombine(h, getExprHash(e));
				h;
			case ENew(cl, params, paramType):
				h = hashCombine(25, hashString(cl));
				for (p in params) h = hashCombine(h, getExprHash(p));
				h;
			case EThrow(e): hashCombine(26, getExprHash(e));
			case ETry(e, v, t, ecatch):
				hashCombine(hashCombine(27, getExprHash(e)), getExprHash(ecatch));
			case EObject(fl):
				h = 28;
				for (f in fl) h = hashCombine(hashCombine(h, hashString(f.name)), getExprHash(f.e));
				h;
			case ETernary(cond, e1, e2):
				hashCombine(hashCombine(hashCombine(29, getExprHash(cond)), getExprHash(e1)), getExprHash(e2));
			case ESwitch(e, cases, defaultExpr):
				h = hashCombine(30, getExprHash(e));
				for (c in cases) {
					for (v in c.values) h = hashCombine(h, getExprHash(v));
					h = hashCombine(h, getExprHash(c.expr));
				}
				defaultExpr != null ? hashCombine(h, getExprHash(defaultExpr)) : h;
			case EMeta(name, args, e):
				h = hashCombine(31, hashString(name));
				if (args != null) for (a in args) h = hashCombine(h, getExprHash(a));
				hashCombine(h, getExprHash(e));
			case ECheckType(e, t): hashCombine(32, getExprHash(e));
			case EEnum(en, isAbstract): hashCombine(33, hashString(en.name));
			case ECast(e, t): hashCombine(34, getExprHash(e));
			case ERegex(e, f): hashCombine(hashCombine(35, hashString(e)), hashString(f));
		}
	}

	private function optimizeOnce(expr:Expr):Expr {
		return optimizeWithCache(expr, 0);
	}

	private function optimizeWithCache(expr:Expr, depth:Int):Expr {
		var useCache = enableCache && !debug && depth < 3;
		var cacheKey = getCacheKey(expr);
		
		if (useCache && optimizationCache.exists(cacheKey)) {
			if (debug) stats.cacheHits++;
			return optimizationCache.get(cacheKey);
		}
		
		if (debug) stats.cacheMisses++;
		
		var result = switch (Tools.expr(expr)) {
			case EConst(_): 
				if (debug) stats.constCount++;
				expr;
			case EIdent(_): 
				if (debug) stats.identCount++;
				switch (Tools.expr(expr)) {
					case EIdent(id):
						var constId = finalConstantIds.get(id);
						if (constId != null) {
							if (debug) stats.finalConstantReplacements++;
							return finalConstants[constId];
						}
					default:
				}
				expr;
			case EPackage(_): expr;
			case EImport(_): expr;
			case EClass(name, fields, extend, interfaces, isFinal):
				if (debug) stats.classCount++;
				var changed = false;
				var optimizedFields = [for (f in fields) {
					var opt = optimizeWithCache(f, depth + 1);
					if (opt != f) changed = true;
					opt;
				}];
				changed ? Tools.mk(EClass(name, optimizedFields, extend, interfaces, isFinal), expr) : expr;
			case EVar(n, t, e, isPublic, isStatic, isPrivate, isFinal, isInline, get, set, isVar):
				if (debug) stats.varCount++;
				var optimizedExpr = e != null ? optimizeWithCache(e, depth + 1) : null;
				if (isFinal && optimizedExpr != null && isConstantExpr(optimizedExpr)) {
					var constId = finalConstants.length;
					finalConstants.push(optimizedExpr);
					finalConstantIds.set(n, constId);
				}
				(optimizedExpr != e) ? Tools.mk(EVar(n, t, optimizedExpr, isPublic, isStatic, isPrivate, isFinal, isInline, get, set, isVar), expr) : expr;
			case EParent(e):
				if (debug) stats.parentCount++;
				var optimized = optimizeWithCache(e, depth + 1);
				(optimized != e) ? Tools.mk(EParent(optimized), expr) : expr;
			case EBlock(exprs):
				if (debug) stats.blockCount++;
				var oldConstants = finalConstants.copy();
				var oldConstantIds = finalConstantIds.copy();
				var optimizedExprs = [for (e in exprs) optimizeWithCache(e, depth + 1)];
				finalConstants = oldConstants;
				finalConstantIds = oldConstantIds;
				var cleanedExprs = enableDeadCodeElimination ? removeDeadCode(optimizedExprs) : optimizedExprs;
				cleanedExprs = [for (e in cleanedExprs) switch (Tools.expr(e)) {
					case EVar(n, _, _, _, _, _, true, _, _, _, _):
						if (finalConstantIds.exists(n)) {
							if (debug) stats.deadCodeEliminations++;
							continue;
						}
						e;
					default: e;
				}];
				if (enableCSE) {
					cleanedExprs = performCSE(cleanedExprs);
				}
				if (cleanedExprs.length == 1) {
					cleanedExprs[0];
				} else if (cleanedExprs.length != exprs.length) {
					Tools.mk(EBlock(cleanedExprs), expr);
				} else {
					var changed = false;
					for (i in 0...cleanedExprs.length) {
						if (cleanedExprs[i] != exprs[i]) {
							changed = true;
							break;
						}
					}
					changed ? Tools.mk(EBlock(cleanedExprs), expr) : expr;
				}
			case EField(e, f, s):
				if (debug) stats.fieldCount++;
				var optimized = optimizeWithCache(e, depth + 1);
				(optimized != e) ? Tools.mk(EField(optimized, f, s), expr) : expr;
			case EBinop(op, e1, e2):
				if (debug) stats.binopCount++;
				var optimized1 = optimizeWithCache(e1, depth + 1);
				var optimized2 = optimizeWithCache(e2, depth + 1);
				var hasSideEffect = hasSideEffects(optimized1) || hasSideEffects(optimized2);
				var folded = !hasSideEffect && enableConstantFolding ? tryFoldConstant(op, optimized1, optimized2) : null;
				if (folded != null) {
					if (debug) stats.folds++;
					folded;
				} else {
					var simplified = !hasSideEffect && enableExpressionSimplification ? trySimplifyBinop(op, optimized1, optimized2) : null;
					if (simplified != null) {
						if (debug) stats.simplifications++;
						simplified;
					} else if (optimized1 != e1 || optimized2 != e2) {
						Tools.mk(EBinop(op, optimized1, optimized2), expr);
					} else {
						expr;
					}
				}
			case EUnop(op, prefix, e):
				if (debug) stats.unopCount++;
				var optimized = optimizeWithCache(e, depth + 1);
				var hasSideEffect = hasSideEffects(optimized);
				var folded = !hasSideEffect && enableConstantFolding ? tryFoldUnop(op, prefix, optimized) : null;
				if (folded != null) {
					if (debug) stats.folds++;
					folded;
				} else {
					var simplified = !hasSideEffect && enableExpressionSimplification ? trySimplifyUnop(op, prefix, optimized) : null;
					if (simplified != null) {
						if (debug) stats.simplifications++;
						simplified;
					} else if (optimized != e) {
						Tools.mk(EUnop(op, prefix, optimized), expr);
					} else {
						expr;
					}
				}
			case ECall(e, params):
				if (debug) stats.callCount++;
				var paramsChanged = false;
				var optimizedExpr = optimizeWithCache(e, depth + 1);
				var optimizedParams = [for (p in params) {
					var opt = optimizeWithCache(p, depth + 1);
					if (opt != p) paramsChanged = true;
					opt;
				}];
				
				var callOptimized = tryOptimizeCall(optimizedExpr, optimizedParams);
				if (callOptimized != null) {
					if (debug) stats.simplifications++;
					return callOptimized;
				}
				
				(optimizedExpr != e || paramsChanged) ? Tools.mk(ECall(optimizedExpr, optimizedParams), expr) : expr;
			case EIf(cond, e1, e2):
				if (debug) stats.ifCount++;
				var optimizedCond = optimizeWithCache(cond, depth + 1);
				var oldConstants = finalConstants.copy();
				var oldConstantIds = finalConstantIds.copy();
				var optimizedE1 = optimizeWithCache(e1, depth + 1);
				finalConstants = oldConstants;
				finalConstantIds = oldConstantIds;
				var oldConstants2 = finalConstants.copy();
				var oldConstantIds2 = finalConstantIds.copy();
				var optimizedE2 = e2 != null ? optimizeWithCache(e2, depth + 1) : null;
				finalConstants = oldConstants2;
				finalConstantIds = oldConstantIds2;
				
				var condOptimized = tryOptimizeCondition(optimizedCond);
				if (condOptimized != null) {
					optimizedCond = condOptimized;
				}
				
				if (enableBranchOptimization) {
					var optimized = tryOptimizeIf(optimizedCond, optimizedE1, optimizedE2);
					if (optimized != null) {
						if (debug) stats.branchOptimizations++;
						optimized;
					} else if (optimizedCond != cond || optimizedE1 != e1 || optimizedE2 != e2) {
						Tools.mk(EIf(optimizedCond, optimizedE1, optimizedE2), expr);
					} else {
						expr;
					}
				} else if (optimizedCond != cond || optimizedE1 != e1 || optimizedE2 != e2) {
					Tools.mk(EIf(optimizedCond, optimizedE1, optimizedE2), expr);
				} else {
					expr;
				}
			case EWhile(cond, e):
				if (debug) stats.whileCount++;
				var optimizedCond = optimizeWithCache(cond, depth + 1);
				var oldConstants = finalConstants.copy();
				var oldConstantIds = finalConstantIds.copy();
				var optimizedBody = optimizeWithCache(e, depth + 1);
				finalConstants = oldConstants;
				finalConstantIds = oldConstantIds;
				if (optimizedCond != cond || optimizedBody != e) {
					Tools.mk(EWhile(optimizedCond, optimizedBody), expr);
				} else {
					expr;
				}
			case EDoWhile(cond, e):
				if (debug) stats.doWhileCount++;
				var oldConstants = finalConstants.copy();
				var oldConstantIds = finalConstantIds.copy();
				var optimizedCond = optimizeWithCache(cond, depth + 1);
				var optimizedBody = optimizeWithCache(e, depth + 1);
				finalConstants = oldConstants;
				finalConstantIds = oldConstantIds;
				if (optimizedCond != cond || optimizedBody != e) {
					Tools.mk(EDoWhile(optimizedCond, optimizedBody), expr);
				} else {
					expr;
				}
			case EFor(v, it, e, ithv):
				if (debug) stats.forCount++;
				var optimizedIt = optimizeWithCache(it, depth + 1);
				var oldConstants = finalConstants.copy();
				var oldConstantIds = finalConstantIds.copy();
				var optimizedBody = optimizeWithCache(e, depth + 1);
				finalConstants = oldConstants;
				finalConstantIds = oldConstantIds;
				if (optimizedIt != it || optimizedBody != e) {
					Tools.mk(EFor(v, optimizedIt, optimizedBody, ithv), expr);
				} else {
					expr;
				}
			case EBreak: 
				if (debug) stats.breakCount++;
				expr;
			case EContinue: 
				if (debug) stats.continueCount++;
				expr;
			case EFunction(args, e, name, ret, isPublic, isStatic, isOverride, isPrivate, isFinal, isInline):
				if (debug) stats.functionCount++;
				var oldConstants = finalConstants.copy();
				var oldConstantIds = finalConstantIds.copy();
				var optimizedBody = optimizeWithCache(e, depth + 1);
				finalConstants = oldConstants;
				finalConstantIds = oldConstantIds;
				if (optimizedBody != e) {
					Tools.mk(EFunction(args, optimizedBody, name, ret, isPublic, isStatic, isOverride, isPrivate, isFinal, isInline), expr);
				} else {
					expr;
				}
			case EReturn(e):
				if (debug) stats.returnCount++;
				var optimized = e != null ? optimizeWithCache(e, depth + 1) : null;
				if (optimized != e) {
					Tools.mk(EReturn(optimized), expr);
				} else {
					expr;
				}
			case EArray(e, index):
				if (debug) stats.arrayCount++;
				var optimizedExpr = optimizeWithCache(e, depth + 1);
				var optimizedIndex = optimizeWithCache(index, depth + 1);
				if (optimizedExpr != e || optimizedIndex != index) {
					Tools.mk(EArray(optimizedExpr, optimizedIndex), expr);
				} else {
					expr;
				}
			case EArrayDecl(exprs, wantedType):
				if (debug) stats.arrayDeclCount++;
				var changed = false;
				var optimizedExprs = [for (e in exprs) {
					var opt = optimizeWithCache(e, depth + 1);
					if (opt != e) changed = true;
					opt;
				}];
				changed ? Tools.mk(EArrayDecl(optimizedExprs, wantedType), expr) : expr;
			case ENew(cl, params, paramType):
				if (debug) stats.newCount++;
				var changed = false;
				var optimizedParams = [for (p in params) {
					var opt = optimizeWithCache(p, depth + 1);
					if (opt != p) changed = true;
					opt;
				}];
				changed ? Tools.mk(ENew(cl, optimizedParams, paramType), expr) : expr;
			case EThrow(e):
				if (debug) stats.throwCount++;
				var optimized = optimizeWithCache(e, depth + 1);
				if (optimized != e) {
					Tools.mk(EThrow(optimized), expr);
				} else {
					expr;
				}
			case ETry(e, v, t, ecatch):
				if (debug) stats.tryCount++;
				var oldConstants = finalConstants.copy();
				var oldConstantIds = finalConstantIds.copy();
				var optimizedTry = optimizeWithCache(e, depth + 1);
				finalConstants = oldConstants;
				finalConstantIds = oldConstantIds;
				var oldConstants2 = finalConstants.copy();
				var oldConstantIds2 = finalConstantIds.copy();
				var optimizedCatch = optimizeWithCache(ecatch, depth + 1);
				finalConstants = oldConstants2;
				finalConstantIds = oldConstantIds2;
				if (optimizedTry != e || optimizedCatch != ecatch) {
					Tools.mk(ETry(optimizedTry, v, t, optimizedCatch), expr);
				} else {
					expr;
				}
			case EObject(fl):
				if (debug) stats.objectCount++;
				var changed = false;
				var optimizedFields = [for (f in fl) {
					var opt = optimizeWithCache(f.e, depth + 1);
					if (opt != f.e) changed = true;
					{name: f.name, e: opt};
				}];
				if (changed) {
					var objectFields:Array<ObjectField> = [];
					for (f in optimizedFields) {
						objectFields.push({name: f.name, e: f.e});
					}
					Tools.mk(EObject(objectFields), expr);
				} else {
					expr;
				}
			case ETernary(cond, e1, e2):
				if (debug) stats.ternaryCount++;
				var optimizedCond = optimizeWithCache(cond, depth + 1);
				var oldConstants = finalConstants.copy();
				var oldConstantIds = finalConstantIds.copy();
				var optimizedE1 = optimizeWithCache(e1, depth + 1);
				finalConstants = oldConstants;
				finalConstantIds = oldConstantIds;
				var oldConstants2 = finalConstants.copy();
				var oldConstantIds2 = finalConstantIds.copy();
				var optimizedE2 = optimizeWithCache(e2, depth + 1);
				finalConstants = oldConstants2;
				finalConstantIds = oldConstantIds2;
				
				if (enableBranchOptimization) {
					var optimized = tryOptimizeTernary(optimizedCond, optimizedE1, optimizedE2);
					if (optimized != null) {
						if (debug) stats.branchOptimizations++;
						optimized;
					} else if (optimizedCond != cond || optimizedE1 != e1 || optimizedE2 != e2) {
						Tools.mk(ETernary(optimizedCond, optimizedE1, optimizedE2), expr);
					} else {
						expr;
					}
				} else if (optimizedCond != cond || optimizedE1 != e1 || optimizedE2 != e2) {
					Tools.mk(ETernary(optimizedCond, optimizedE1, optimizedE2), expr);
				} else {
					expr;
				}
			case ESwitch(e, cases, defaultExpr):
				if (debug) stats.switchCount++;
				var optimizedExpr = optimizeWithCache(e, depth + 1);
				var oldConstants = finalConstants.copy();
				var oldConstantIds = finalConstantIds.copy();
				var optimizedCases = [for (c in cases) {
					var caseConstants = finalConstants.copy();
					var caseConstantIds = finalConstantIds.copy();
					var result = {
						values: [for (v in c.values) optimizeWithCache(v, depth + 1)],
						expr: optimizeWithCache(c.expr, depth + 1)
					};
					finalConstants = caseConstants;
					finalConstantIds = caseConstantIds;
					result;
				}];
				finalConstants = oldConstants;
				finalConstantIds = oldConstantIds;
				var switchCases:Array<SwitchCase> = [];
				for (c in optimizedCases) {
					switchCases.push({values: c.values, expr: c.expr});
				}
				var oldConstants2 = finalConstants.copy();
				var oldConstantIds2 = finalConstantIds.copy();
				var optimizedDefault = defaultExpr != null ? optimizeWithCache(defaultExpr, depth + 1) : null;
				finalConstants = oldConstants2;
				finalConstantIds = oldConstantIds2;
				
				var changed = optimizedExpr != e || optimizedDefault != defaultExpr;
				if (!changed) {
					for (i in 0...cases.length) {
						var oldCase = cases[i];
						var newCase = optimizedCases[i];
						if (oldCase.values.length != newCase.values.length || oldCase.expr != newCase.expr) {
							changed = true;
							break;
						}
						for (j in 0...oldCase.values.length) {
							if (oldCase.values[j] != newCase.values[j]) {
								changed = true;
								break;
							}
						}
						if (changed) break;
					}
				}
				
				if (changed) {
					Tools.mk(ESwitch(optimizedExpr, switchCases, optimizedDefault), expr);
				} else {
					expr;
				}
			case EMeta(name, args, e):
				if (debug) stats.metaCount++;
				var optimizedArgs = args != null ? [for (a in args) optimizeWithCache(a, depth + 1)] : null;
				var optimizedExpr = optimizeWithCache(e, depth + 1);
				var argsChanged = args != null && optimizedArgs.length == args.length;
				if (argsChanged) {
					for (i in 0...args.length) {
						if (optimizedArgs[i] != args[i]) {
							argsChanged = false;
							break;
						}
					}
				}
				if (optimizedExpr != e || (args != null && !argsChanged)) {
					Tools.mk(EMeta(name, optimizedArgs, optimizedExpr), expr);
				} else {
					expr;
				}
			case ECheckType(e, t):
				if (debug) stats.checkTypeCount++;
				var optimized = optimizeWithCache(e, depth + 1);
				if (optimized != e) {
					Tools.mk(ECheckType(optimized, t), expr);
				} else {
					expr;
				}
			case EEnum(en, isAbstract): 
				if (debug) stats.enumCount++;
				expr;
			case ECast(e, t):
				if (debug) stats.castCount++;
				var optimized = optimizeWithCache(e, depth + 1);
				if (optimized != e) {
					Tools.mk(ECast(optimized, t), expr);
				} else {
					expr;
				}
			case ERegex(e, f): 
				if (debug) stats.regexCount++;
				expr;
		}
		
		if (useCache) {
			optimizationCache.set(cacheKey, result);
		}
		
		return result;
	}

	private inline function getCacheKey(expr:Expr):String {
		#if hscriptPos
		return expr.pmin + ":" + expr.pmax;
		#else
		return Std.string(exprIdCounter++);
		#end
	}

	public function clearCache():Void {
		optimizationCache = new StringMap();
		exprHashes = new IntMap();
		if (debug) {
			stats.cacheHits = 0;
			stats.cacheMisses = 0;
		}
	}

	public function dispose():Void {
		optimizationCache = null;
		exprHashes = null;
		debugPrinter = null;
		stats = null;
	}

	private function tryFoldConstant(op:String, e1:Expr, e2:Expr):Null<Expr> {
		var c1 = getConstValue(e1);
		var c2 = getConstValue(e2);
		
		if (c1 == null || c2 == null) return null;
		
		var result:Dynamic = null;
		
		try {
			switch (op) {
				case "+": result = c1 + c2;
				case "-": result = c1 - c2;
				case "*": result = c1 * c2;
				case "/": 
					if (c2 == 0) return null;
					result = c1 / c2;
				case "%": 
					if (c2 == 0) return null;
					result = c1 % c2;
				case "&": result = c1 & c2;
				case "|": result = c1 | c2;
				case "^": result = c1 ^ c2;
				case "<<": result = c1 << c2;
				case ">>": result = c1 >> c2;
				case ">>>": result = c1 >>> c2;
				case "==": result = c1 == c2;
				case "!=": result = c1 != c2;
				case ">": result = c1 > c2;
				case "<": result = c1 < c2;
				case ">=": result = c1 >= c2;
				case "<=": result = c1 <= c2;
				case "&&": result = (c1 == true) && (c2 == true);
				case "||": result = (c1 == true) || (c2 == true);
				default: return null;
			}
		} catch (e:Dynamic) {
			return null;
		}
		
		return makeConst(result, e1);
	}

	private function tryFoldUnop(op:String, prefix:Bool, e:Expr):Null<Expr> {
		var c = getConstValue(e);
		if (c == null) return null;
		
		var result:Dynamic = null;
		
		try {
			switch (op) {
				case "!": result = !(c == true);
				case "-": result = -c;
				case "~": result = ~c;
				default: return null;
			}
		} catch (e:Dynamic) {
			return null;
		}
		
		return makeConst(result, e);
	}

	private function trySimplifyBinop(op:String, e1:Expr, e2:Expr):Null<Expr> {
		var c1 = getConstValue(e1);
		var c2 = getConstValue(e2);
		
		switch (op) {
			case "+":
				if (c1 != null && c1 == 0 && !isStringExpr(e1)) return e2;
				if (c2 != null && c2 == 0 && !isStringExpr(e2)) return e1;
				
				if (c1 != null && c2 != null) {
					return makeConst(c1 + c2, e1);
				}
				
				if (c1 != null) {
					switch (Tools.expr(e2)) {
						case EBinop("+", e2_1, e2_2):
							var c2_1 = getConstValue(e2_1);
							var c2_2 = getConstValue(e2_2);
							if (c2_1 != null && c2_2 != null) {
								var combinedConst = c1 + c2_1 + c2_2;
								return Tools.mk(EBinop("+", e2_1, makeConst(c2_2 + c1, e2_2)), e2);
							}
							if (c2_1 != null) {
								var combinedConst = c1 + c2_1;
								return Tools.mk(EBinop("+", makeConst(combinedConst, e2_1), e2_2), e2);
							}
						case EBinop("-", e2_1, e2_2):
							var c2_1 = getConstValue(e2_1);
							var c2_2 = getConstValue(e2_2);
							if (c2_1 != null && c2_2 != null) {
								var combinedConst = c1 - c2_1 + c2_2;
								return Tools.mk(EBinop("+", e2_1, makeConst(c2_2 + c1, e2_2)), e2);
							}
							if (c2_1 != null) {
								var combinedConst = c1 - c2_1;
								return Tools.mk(EBinop("+", makeConst(combinedConst, e2_1), e2_2), e2);
							}
						default:
					}
				}
				
				if (c2 != null) {
					switch (Tools.expr(e1)) {
						case EBinop("+", e1_1, e1_2):
							var c1_1 = getConstValue(e1_1);
							var c1_2 = getConstValue(e1_2);
							if (c1_1 != null && c1_2 != null) {
								var combinedConst = c1_1 + c1_2 + c2;
								return Tools.mk(EBinop("+", e1_1, makeConst(c1_2 + c2, e1_2)), e1);
							}
							if (c1_2 != null) {
								return Tools.mk(EBinop("+", e1, makeConst(c2, e2)), e1);
							}
						case EBinop("-", e1_1, e1_2):
							var c1_1 = getConstValue(e1_1);
							var c1_2 = getConstValue(e1_2);
							if (c1_1 != null && c1_2 != null) {
								var combinedConst = c1_1 - c1_2 + c2;
								return Tools.mk(EBinop("-", e1_1, makeConst(c1_2 - c2, e1_2)), e1);
							}
							if (c1_2 != null) {
								if (op == "+") {
									return Tools.mk(EBinop("-", e1_1, makeConst(c1_2 - c2, e1_2)), e1);
								} else {
									return Tools.mk(EBinop("-", e1_1, makeConst(c1_2 + c2, e1_2)), e1);
								}
							}
						case EBinop("*", e1_1, e1_2):
							var c1_1 = getConstValue(e1_1);
							var c1_2 = getConstValue(e1_2);
							if (c1_1 != null && c1_2 != null) {
								var combinedConst = c1_1 * c1_2;
								return Tools.mk(EBinop("*", e1_1, makeConst(combinedConst, e1_2)), e1);
							}
						case EBinop("/", e1_1, e1_2):
							var c1_1 = getConstValue(e1_1);
							var c1_2 = getConstValue(e1_2);
							if (c1_1 != null && c1_2 != null) {
								var combinedConst = c1_1 / c1_2;
								return Tools.mk(EBinop("/", e1_1, makeConst(combinedConst, e1_2)), e1);
							}
						default:
					}
				}
			case "-":
				if (c2 != null && c2 == 0) return e1;
				
				if (c1 != null && c2 != null) {
					return makeConst(c1 - c2, e1);
				}
				
				if (c1 != null) {
					switch (Tools.expr(e2)) {
						case EBinop("-", e2_1, e2_2):
							var c2_1 = getConstValue(e2_1);
							var c2_2 = getConstValue(e2_2);
							if (c2_1 != null && c2_2 != null) {
								var combinedConst = c1 - c2_1 - c2_2;
								return Tools.mk(EBinop("-", e2_1, makeConst(c2_2 - c1, e2_2)), e2);
							}
							if (c2_1 != null) {
								var combinedConst = c1 - c2_1;
								return Tools.mk(EBinop("-", makeConst(combinedConst, e2_1), e2_2), e2);
							}
						case EBinop("/", e2_1, e2_2):
							var c2_1 = getConstValue(e2_1);
							var c2_2 = getConstValue(e2_2);
							if (c2_1 != null && c2_2 != null) {
								var combinedConst = c1 - c2_1 / c2_2;
								return Tools.mk(EBinop("-", e2_1, makeConst(c2_2, e2_2)), e2);
							}
							if (c2_1 != null) {
								var combinedConst = c1 - c2_1;
								return Tools.mk(EBinop("-", makeConst(combinedConst, e2_1), e2_2), e2);
							}
						default:
					}
				}
				
				if (c2 != null) {
					switch (Tools.expr(e1)) {
						case EBinop("+", e1_1, e1_2):
							var c1_2 = getConstValue(e1_2);
							if (c1_2 != null) {
								var combinedConst = c1_2 - c2;
								return Tools.mk(EBinop("+", e1_1, makeConst(combinedConst, e1_2)), e1);
							}
						case EBinop("-", e1_1, e1_2):
							var c1_2 = getConstValue(e1_2);
							if (c1_2 != null) {
								var combinedConst = c1_2 + c2;
								return Tools.mk(EBinop("-", e1_1, makeConst(combinedConst, e1_2)), e1);
							}
						default:
					}
				}
			case "*":
				if (c1 != null && c1 == 1) return e2;
				if (c2 != null && c2 == 1) return e1;
				if ((c1 != null && c1 == 0) || (c2 != null && c2 == 0)) return makeConst(0, e1);
				
				if (c1 != null && c2 != null) {
					return makeConst(c1 * c2, e1);
				}
				
				if (c1 != null) {
					switch (Tools.expr(e2)) {
						case EBinop("*", e2_1, e2_2):
							var c2_1 = getConstValue(e2_1);
							var c2_2 = getConstValue(e2_2);
							if (c2_1 != null && c2_2 != null) {
								var combinedConst = c1 * c2_1 * c2_2;
								return Tools.mk(EBinop("*", e2_1, makeConst(c2_2 * c1, e2_2)), e2);
							}
							if (c2_1 != null) {
								var combinedConst = c1 * c2_1;
								return Tools.mk(EBinop("*", makeConst(combinedConst, e2_1), e2_2), e2);
							}
						default:
					}
				}
				
				if (c2 != null) {
					switch (Tools.expr(e1)) {
						case EBinop("*", e1_1, e1_2):
							var c1_1 = getConstValue(e1_1);
							var c1_2 = getConstValue(e1_2);
							if (c1_1 != null && c1_2 != null) {
								var combinedConst = c1_1 * c1_2 * c2;
								return Tools.mk(EBinop("*", e1_1, makeConst(c1_2 * c2, e1_2)), e1);
							}
							if (c1_2 != null) {
								var combinedConst = c1_2 * c2;
								return Tools.mk(EBinop("*", e1_1, makeConst(combinedConst, e1_2)), e1);
							}
						default:
					}
				}
			case "/":
				if (c2 != null && c2 == 1) return e1;
				if (c2 != null && c2 != 0) {
					var multiplier = 1.0 / c2;
					return Tools.mk(EBinop("*", e1, makeConst(multiplier, e2)), e2);
				}
				
				if (c1 != null) {
					switch (Tools.expr(e2)) {
						case EBinop("*", e2_1, e2_2):
							var c2_1 = getConstValue(e2_1);
							var c2_2 = getConstValue(e2_2);
							if (c2_1 != null && c2_2 != null) {
								var combinedConst = c2_1 * c2_2;
								var multiplier = 1.0 / combinedConst;
								return Tools.mk(EBinop("*", e1, makeConst(multiplier, e2_1)), e2_2);
							}
							if (c2_1 != null) {
							var multiplier = 1.0 / c2_1;
							return Tools.mk(EBinop("*", e1, makeConst(multiplier, e2_1)), e2_2);
						}
						case EBinop("/", e2_1, e2_2):
							var c2_1 = getConstValue(e2_1);
							var c2_2 = getConstValue(e2_2);
							if (c2_1 != null && c2_2 != null) {
								var combinedConst = c2_1 / c2_2;
								var multiplier = 1.0 / combinedConst;
								return Tools.mk(EBinop("*", e1, makeConst(multiplier, e2_1)), e2_2);
							}
						default:
					}
				}
				
				if (c2 != null) {
					switch (Tools.expr(e1)) {
						case EBinop("*", e1_1, e1_2):
							var c1_1 = getConstValue(e1_1);
							var c1_2 = getConstValue(e1_2);
							if (c1_1 != null && c1_2 != null) {
								var combinedConst = c1_1 * c1_2;
								var multiplier = 1.0 / c2;
								return Tools.mk(EBinop("*", e1_1, makeConst(c1_2 * multiplier, e1_2)), e2);
							}
							if (c1_2 != null) {
								var multiplier = 1.0 / c2;
								return Tools.mk(EBinop("/", e1_1, makeConst(c1_2 / c2, e1_2)), e2);
							}
						case EBinop("/", e1_1, e1_2):
						var c1_1 = getConstValue(e1_1);
						var c1_2 = getConstValue(e1_2);
						if (c1_1 != null && c1_2 != null) {
							var combinedConst = c1_1 / c1_2;
							var multiplier = 1.0 / combinedConst;
							return Tools.mk(EBinop("*", e1_1, makeConst(multiplier, e1_2)), e2);
						}
						if (c1_2 != null) {
							var multiplier = 1.0 / c1_2;
							return Tools.mk(EBinop("/", e1_1, makeConst(multiplier, e1_2)), e2);
						}
						if (c1_1 != null) {
							var multiplier = 1.0 / c1_1;
							return Tools.mk(EBinop("/", e1_1, makeConst(multiplier, e1_2)), e2);
						}
					default:
					}
				}
			case "&&":
				if (c1 != null && c1 == false) return makeConst(false, e1);
				if (c2 != null && c2 == false) return makeConst(false, e2);
				if (c1 != null && c1 == true) return e2;
				if (c2 != null && c2 == true) return e1;
			case "||":
				if (c1 != null && c1 == true) return makeConst(true, e1);
				if (c2 != null && c2 == true) return makeConst(true, e2);
				if (c1 != null && c1 == false) return e2;
				if (c2 != null && c2 == false) return e1;
			case "%":
				if (c2 != null && c2 == 1 && c1 != null && c1 == Math.floor(c1)) return makeConst(0, e1);
				if (c1 != null && c2 != null) {
					return makeConst(c1 % c2, e1);
				}
				if (c2 != null && isPowerOfTwo(c2) && c1 != null && c1 >= 0) {
					var mask = Std.int(c2) - 1;
					return Tools.mk(EBinop("&", e1, makeConst(mask, e2)), e1);
				}
			case "!=":
				if (c1 != null && c2 != null) return makeConst(c1 != c2, e1);
				if (e1 == e2) return makeConst(false, e1);
			case "==":
				if (c1 != null && c2 != null) return makeConst(c1 == c2, e1);
				if (e1 == e2) return makeConst(true, e1);
			case ">":
				if (c1 != null && c2 != null) return makeConst(c1 > c2, e1);
			case "<":
				if (c1 != null && c2 != null) return makeConst(c1 < c2, e1);
			case ">=":
				if (c1 != null && c2 != null) return makeConst(c1 >= c2, e1);
			case "<=":
				if (c1 != null && c2 != null) return makeConst(c1 <= c2, e1);
			case "is":
				if (c1 != null && c2 != null) return makeConst(Std.isOfType(c1, c2), e1);
		}
		
		return null;
	}

	private function trySimplifyUnop(op:String, prefix:Bool, e:Expr):Null<Expr> {
		switch (Tools.expr(e)) {
			case EUnop(op2, prefix2, e2):
				if (op == op2 && prefix != prefix2) {
					return e2;
				}
			default:
		}
		
		if (op == "-") {
			var c = getConstValue(e);
			if (c != null) return makeConst(-c, e);
		}
		
		if (op == "+") return e;
		
		return null;
	}

	private function tryOptimizeIf(cond:Expr, e1:Expr, e2:Expr):Null<Expr> {
		var c = getConstValue(cond);
		
		if (c != null && isPureConstant(cond)) {
			if (c == true) {
				return e1;
			} else {
				return e2 != null ? e2 : makeConst(null, cond);
			}
		}
		
		if (exprEquals(e1, e2)) {
			return e1;
		}
		
		return null;
	}

	private function tryOptimizeTernary(cond:Expr, e1:Expr, e2:Expr):Null<Expr> {
		var c = getConstValue(cond);
		
		if (c != null && isPureConstant(cond)) {
			if (c == true) {
				return e1;
			} else {
				return e2;
			}
		}
		
		if (exprEquals(e1, e2)) {
			return e1;
		}
		
		return null;
	}

	private function tryOptimizeCall(e:Expr, params:Array<Expr>):Null<Expr> {
		return null;
	}

	private function tryOptimizeCondition(cond:Expr):Null<Expr> {
		switch (Tools.expr(cond)) {
			case EIdent(id):
				var constId = finalConstantIds.get(id);
				if (constId != null) {
					return finalConstants[constId];
				}
			case EUnop("!", _, inner):
				switch (Tools.expr(inner)) {
					case EIdent(id):
						var constId = finalConstantIds.get(id);
						if (constId != null) {
							return Tools.mk(EUnop("!", false, finalConstants[constId]), cond);
						}
					case EUnop("!", _, inner2):
						return inner2;
					case EBinop("&&", a, b):
						return Tools.mk(EBinop("||", Tools.mk(EUnop("!", false, a), cond), 
							Tools.mk(EUnop("!", false, b), cond)), cond);
					case EBinop("||", a, b):
						return Tools.mk(EBinop("&&", Tools.mk(EUnop("!", false, a), cond), 
							Tools.mk(EUnop("!", false, b), cond)), cond);
					default:
				}
			default:
		}
		return null;
	}

	private inline function removeDeadCode(exprs:Array<Expr>):Array<Expr> {
		var result:Array<Expr> = [];
		
		for (e in exprs) {
			result.push(e);
			
			if (isUnconditionalTerminator(e)) {
				break;
			}
		}
		
		return result;
	}
	
	private function isUnconditionalTerminator(expr:Expr):Bool {
		return switch (Tools.expr(expr)) {
			case EReturn(_): true;
			case EThrow(_): true;
			case EIf(_, e1, e2):
				if (e2 == null) false;
				else isUnconditionalTerminator(e1) && isUnconditionalTerminator(e2);
			case ETernary(_, e1, e2):
				isUnconditionalTerminator(e1) && isUnconditionalTerminator(e2);
			case ESwitch(_, cases, defaultExpr):
				if (defaultExpr == null) false;
				else {
					var allCasesTerminate = true;
					for (c in cases) {
						if (!isUnconditionalTerminator(c.expr)) {
							allCasesTerminate = false;
							break;
						}
					}
					allCasesTerminate && isUnconditionalTerminator(defaultExpr);
				}
			case EBlock(exprs):
				if (exprs.length == 0) false;
				else isUnconditionalTerminator(exprs[exprs.length - 1]);
			default: false;
		}
	}

	private function isTerminator(expr:Expr):Bool {
		return switch (Tools.expr(expr)) {
			case EBreak, EContinue, EReturn(_): true;
			default: false;
		}
	}

	private inline function getConstValue(expr:Expr):Null<Dynamic> {
		return switch (Tools.expr(expr)) {
			case EConst(CInt(v)): v;
			case EConst(CFloat(v)): v;
			case EConst(CString(v)): v;
			default: null;
		}
	}

	private function makeConst(value:Dynamic, original:Expr):Expr {
		if (Std.isOfType(value, Int)) {
			return Tools.mk(EConst(CInt(value)), original);
		} else if (Std.isOfType(value, Float)) {
			return Tools.mk(EConst(CFloat(value)), original);
		} else if (Std.isOfType(value, String)) {
			return Tools.mk(EConst(CString(value)), original);
		} else if (value == null) {
			return Tools.mk(EConst(CInt(0)), original);
		} else {
			return Tools.mk(EConst(CFloat(value)), original);
		}
	}

	private inline function exprEquals(e1:Expr, e2:Expr):Bool {
		if (e1 == e2) return true;
		if (e1 == null || e2 == null) return false;
		
		return switch ([Tools.expr(e1), Tools.expr(e2)]) {
			case [EConst(c1), EConst(c2)]:
				switch ([c1, c2]) {
					case [CInt(v1), CInt(v2)]: v1 == v2;
					case [CFloat(v1), CFloat(v2)]: v1 == v2;
					case [CString(v1), CString(v2)]: v1 == v2;
					default: false;
				}
			case [EIdent(v1), EIdent(v2)]: v1 == v2;
			default: false;
		}
	}

	private function hasSideEffects(expr:Expr):Bool {
		return switch (Tools.expr(expr)) {
			case ECall(_, _): true;
			case EBinop("=", _, _): true;
			case EBinop(op, _, _) if (StringTools.endsWith(op, "=")): true;
			case EUnop("++", _, _) | EUnop("--", _, _): true;
			case EField(e, _, _): true;
			case EArray(e, index): hasSideEffects(e) || hasSideEffects(index);
			case ENew(_, _, _): true;
			case EThrow(_): true;
			case EVar(_, _, e, _, _, _, _, _, _, _, _):
				e != null ? hasSideEffects(e) : false;
			case EObject(fields):
				for (f in fields) {
					if (hasSideEffects(f.e)) return true;
				}
				false;
			case EArrayDecl(exprs):
				for (e in exprs) {
					if (hasSideEffects(e)) return true;
				}
				false;
			case ESwitch(e, cases, defaultExpr):
				if (hasSideEffects(e)) return true;
				for (c in cases) {
					for (v in c.values) {
						if (hasSideEffects(v)) return true;
					}
					if (hasSideEffects(c.expr)) return true;
				}
				if (defaultExpr != null && hasSideEffects(defaultExpr)) return true;
				false;
			case EIf(cond, e1, e2):
				hasSideEffects(cond) || hasSideEffects(e1) || (e2 != null && hasSideEffects(e2));
			case EWhile(cond, e) | EDoWhile(cond, e):
				hasSideEffects(cond) || hasSideEffects(e);
			case EFor(_, it, e, _):
				hasSideEffects(it) || hasSideEffects(e);
			case ETernary(cond, e1, e2):
				hasSideEffects(cond) || hasSideEffects(e1) || hasSideEffects(e2);
			case EFunction(_, _, _, _, _, _, _, _, _, _): false;
			case EConst(_): false;
			case EIdent(_): false;
			case EParent(e): hasSideEffects(e);
			case EBlock(exprs):
				for (e in exprs) {
					if (hasSideEffects(e)) return true;
				}
				false;
			case EReturn(e):
				e != null ? hasSideEffects(e) : false;
			case EBreak, EContinue: false;
			case ECheckType(e, _): hasSideEffects(e);
			case ECast(e, _): hasSideEffects(e);
			case EMeta(_, _, e): hasSideEffects(e);
			case EPackage(_): false;
			case EImport(_): false;
			case EClass(_, _, _, _, _): false;
			case EEnum(_, _): false;
			default: true;
		}
	}

	private inline function isPureConstant(expr:Expr):Bool {
		return switch (Tools.expr(expr)) {
			case EConst(_): true;
			case EParent(e): isPureConstant(e);
			default: false;
		}
	}

	private inline function isConstantExpr(expr:Expr):Bool {
		return switch (Tools.expr(expr)) {
			case EConst(_): true;
			case EParent(e): isConstantExpr(e);
			case EBinop(op, e1, e2): 
				var c1 = getConstValue(e1);
				var c2 = getConstValue(e2);
				c1 != null && c2 != null;
			case EUnop(op, prefix, e):
				getConstValue(e) != null;
			default: false;
		}
	}

	private inline function isStringExpr(expr:Expr):Bool {
		return switch (Tools.expr(expr)) {
			case EConst(CString(_)): true;
			case EParent(e): isStringExpr(e);
			case EBinop("+", e1, e2): isStringExpr(e1) || isStringExpr(e2);
			default: false;
		}
	}
	
	private inline function isPowerOfTwo(n:Float):Bool {
		if (n != Math.floor(n)) return false;
		var i = Std.int(n);
		if (i <= 0) return false;
		return (i & (i - 1)) == 0;
	}

	private function isPureCSEExpr(expr:Expr):Bool {
		return switch (Tools.expr(expr)) {
			case EConst(_): true;
			case EIdent(_): true;
			case EParent(e): isPureCSEExpr(e);
			case EBinop(op, e1, e2):
				if (op == "=" || StringTools.endsWith(op, "=")) false;
				else isPureCSEExpr(e1) && isPureCSEExpr(e2);
			case EUnop(op, _, e):
				if (op == "++" || op == "--") false;
				else isPureCSEExpr(e);
			default: false;
		}
	}

	private function isCSECandidate(expr:Expr):Bool {
		return switch (Tools.expr(expr)) {
			case EBinop(op, _, _) if (op != "=" && !StringTools.endsWith(op, "=")): true;
			case EUnop(_, _, _): true;
			default: false;
		}
	}

	private function getCSEHash(expr:Expr):String {
		return switch (Tools.expr(expr)) {
			case EConst(c):
				"C:" + switch(c) {
					case CInt(v): "i" + v;
					case CFloat(f): "f" + f;
					case CString(s): "s" + s;
				}
			case EIdent(id): "I:" + id;
			case EParent(e): "PR:" + getCSEHash(e);
			case EBinop(op, e1, e2): "OP:" + op + ":" + getCSEHash(e1) + ":" + getCSEHash(e2);
			case EUnop(op, prefix, e): "UN:" + op + ":" + prefix + ":" + getCSEHash(e);
			default: "";
		}
	}

	private function collectCSEInExpr(expr:Expr, map:StringMap<{expr:Expr, count:Int, varName:String, firstUseIndex:Int, vars:StringMap<Bool>}>, exprIndex:Int):Void {
		switch (Tools.expr(expr)) {
			case EBinop(_, e1, e2):
				collectCSEInExpr(e1, map, exprIndex);
				collectCSEInExpr(e2, map, exprIndex);
				if (isPureCSEExpr(expr) && isCSECandidate(expr)) {
					var key = getCSEHash(expr);
					if (map.exists(key)) {
						map.get(key).count++;
					} else {
						map.set(key, {expr: expr, count: 1, varName: "", firstUseIndex: exprIndex, vars: null});
					}
				}
			case EUnop(_, _, e):
				collectCSEInExpr(e, map, exprIndex);
				if (isPureCSEExpr(expr) && isCSECandidate(expr)) {
					var key = getCSEHash(expr);
					if (map.exists(key)) {
						map.get(key).count++;
					} else {
						map.set(key, {expr: expr, count: 1, varName: "", firstUseIndex: exprIndex, vars: null});
					}
				}
			case EField(e, _, _):
				collectCSEInExpr(e, map, exprIndex);
			case EParent(e):
				collectCSEInExpr(e, map, exprIndex);
			case EArray(e, idx):
				collectCSEInExpr(e, map, exprIndex);
				collectCSEInExpr(idx, map, exprIndex);
			case ECall(e, params):
				collectCSEInExpr(e, map, exprIndex);
				for (p in params) collectCSEInExpr(p, map, exprIndex);
			case EIf(cond, e1, e2):
				collectCSEInExpr(cond, map, exprIndex);
			case EWhile(cond, e):
				collectCSEInExpr(cond, map, exprIndex);
			case EVar(_, _, e, _, _, _, _, _, _, _, _):
				if (e != null) collectCSEInExpr(e, map, exprIndex);
			case EReturn(e):
				if (e != null) collectCSEInExpr(e, map, exprIndex);
			case ETernary(cond, e1, e2):
				collectCSEInExpr(cond, map, exprIndex);
			default:
		}
	}

	private function applyCSEToExpr(expr:Expr, cseMap:StringMap<{expr:Expr, count:Int, varName:String, firstUseIndex:Int, vars:StringMap<Bool>}>):Expr {
		if (isPureCSEExpr(expr) && isCSECandidate(expr)) {
			var key = getCSEHash(expr);
			if (cseMap.exists(key)) {
				var entry = cseMap.get(key);
				if (entry.count > 1 && entry.varName != "") {
					if (debug) stats.cseEliminations++;
					return Tools.mk(EIdent(entry.varName), expr);
				}
			}
		}
		
		return switch (Tools.expr(expr)) {
			case EBinop(op, e1, e2):
				var te1 = applyCSEToExpr(e1, cseMap);
				var te2 = applyCSEToExpr(e2, cseMap);
				if (te1 != e1 || te2 != e2) Tools.mk(EBinop(op, te1, te2), expr) else expr;
			case EUnop(op, prefix, e):
				var te = applyCSEToExpr(e, cseMap);
				if (te != e) Tools.mk(EUnop(op, prefix, te), expr) else expr;
			case EField(e, f, s):
				var te = applyCSEToExpr(e, cseMap);
				if (te != e) Tools.mk(EField(te, f, s), expr) else expr;
			case EParent(e):
				var te = applyCSEToExpr(e, cseMap);
				if (te != e) Tools.mk(EParent(te), expr) else expr;
			case EArray(e, idx):
				var te = applyCSEToExpr(e, cseMap);
				var tidx = applyCSEToExpr(idx, cseMap);
				if (te != e || tidx != idx) Tools.mk(EArray(te, tidx), expr) else expr;
			case ECall(e, params):
				var te = applyCSEToExpr(e, cseMap);
				var tparams = [for (p in params) applyCSEToExpr(p, cseMap)];
				var changed = te != e;
				if (!changed) for (i in 0...params.length) if (tparams[i] != params[i]) { changed = true; break; }
				if (changed) Tools.mk(ECall(te, tparams), expr) else expr;
			case EIf(cond, e1, e2):
				var tcond = applyCSEToExpr(cond, cseMap);
				if (tcond != cond) Tools.mk(EIf(tcond, e1, e2), expr) else expr;
			case EWhile(cond, e):
				var tcond = applyCSEToExpr(cond, cseMap);
				if (tcond != cond) Tools.mk(EWhile(tcond, e), expr) else expr;
			case EVar(n, t, e, isPublic, isStatic, isPrivate, isFinal, isInline, get, set, isVar):
				var te = e != null ? applyCSEToExpr(e, cseMap) : null;
				if (te != e) Tools.mk(EVar(n, t, te, isPublic, isStatic, isPrivate, isFinal, isInline, get, set, isVar), expr) else expr;
			case EReturn(e):
				var te = e != null ? applyCSEToExpr(e, cseMap) : null;
				if (te != e) Tools.mk(EReturn(te), expr) else expr;
			case ETernary(cond, e1, e2):
				var tcond = applyCSEToExpr(cond, cseMap);
				if (tcond != cond) Tools.mk(ETernary(tcond, e1, e2), expr) else expr;
			default: expr;
		}
	}

	private function getExprVars(expr:Expr, vars:StringMap<Bool>):Void {
		switch (Tools.expr(expr)) {
			case EIdent(id):
				vars.set(id, true);
			case EBinop(_, e1, e2):
				getExprVars(e1, vars);
				getExprVars(e2, vars);
			case EUnop(_, _, e):
				getExprVars(e, vars);
			case EParent(e):
				getExprVars(e, vars);
			case EField(e, _, _):
				getExprVars(e, vars);
			case EArray(e, idx):
				getExprVars(e, vars);
				getExprVars(idx, vars);
			case ECall(e, params):
				getExprVars(e, vars);
				for (p in params) getExprVars(p, vars);
			case EIf(cond, e1, e2):
				getExprVars(cond, vars);
				getExprVars(e1, vars);
				if (e2 != null) getExprVars(e2, vars);
			case ETernary(cond, e1, e2):
				getExprVars(cond, vars);
				getExprVars(e1, vars);
				getExprVars(e2, vars);
			default:
		}
	}

	private function getAssignedVar(expr:Expr):String {
		return switch (Tools.expr(expr)) {
			case EBinop("=", e1, _):
				switch (Tools.expr(e1)) {
					case EIdent(id): id;
					default: null;
				}
			case EBinop(op, e1, _) if (StringTools.endsWith(op, "=")):
				switch (Tools.expr(e1)) {
					case EIdent(id): id;
					default: null;
				}
			case EUnop("++", _, e) | EUnop("--", _, e):
				switch (Tools.expr(e)) {
					case EIdent(id): id;
					default: null;
				}
			default: null;
		}
	}

	private function performCSE(exprs:Array<Expr>):Array<Expr> {
		var cseMap = new StringMap<{expr:Expr, count:Int, varName:String, firstUseIndex:Int, vars:StringMap<Bool>}>();
		
		for (i in 0...exprs.length) {
			collectCSEInExpr(exprs[i], cseMap, i);
		}
		
		for (key in cseMap.keys()) {
			var entry = cseMap.get(key);
			entry.vars = new StringMap<Bool>();
			getExprVars(entry.expr, entry.vars);
		}
		
		for (key in cseMap.keys()) {
			var entry = cseMap.get(key);
			if (entry.count > 1) {
				var invalidated = false;
				for (i in (entry.firstUseIndex + 1)...exprs.length) {
					var assignedVar = getAssignedVar(exprs[i]);
					if (assignedVar != null && entry.vars.exists(assignedVar)) {
						invalidated = true;
						break;
					}
				}
				if (invalidated) {
					entry.count = 1;
				}
			}
		}
		
		var hasCSE = false;
		for (key in cseMap.keys()) {
			var entry = cseMap.get(key);
			if (entry.count > 1) {
				entry.varName = "__cse_" + (cseCounter++);
				hasCSE = true;
			}
		}
		
		if (!hasCSE) return exprs;
		
		var cseDeclarations = new StringMap<Expr>();
		for (key in cseMap.keys()) {
			var entry = cseMap.get(key);
			if (entry.count > 1) {
				cseDeclarations.set(key, Tools.mk(EVar(entry.varName, null, entry.expr, false, false, false, true, false, null, null, true), entry.expr));
			}
		}
		
		var result:Array<Expr> = [];
		var insertedKeys = new StringMap<Bool>();
		
		for (i in 0...exprs.length) {
			for (key in cseMap.keys()) {
				var entry = cseMap.get(key);
				if (entry.count > 1 && entry.firstUseIndex == i && !insertedKeys.exists(key)) {
					result.push(cseDeclarations.get(key));
					insertedKeys.set(key, true);
				}
			}
			
			var transformed = applyCSEToExpr(exprs[i], cseMap);
			result.push(transformed);
		}
		
		return result;
	}

}