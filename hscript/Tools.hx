/*
 * Copyright (C)2008-2017 Haxe Foundation
 *
 * Permission is hereby granted, free of charge, to any person obtaining a
 * copy of this software and associated documentation files (the "Software"),
 * to deal in the Software without restriction, including without limitation
 * the rights to use, copy, modify, merge, publish, distribute, sublicense,
 * and/or sell copies of the Software, and to permit persons to whom the
 * Software is furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
 * FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
 * DEALINGS IN THE SOFTWARE.
 */
package hscript;
import hscript.Expr;

class Tools {

	public static function iter( e : Expr, f : Expr -> Void ):Void {
		switch( expr(e) ) {
		case EConst(_), EIdent(_):
		case EImport(c): f(e);
		case EClass(_, e, _, _): for( a in e ) f(a);
		case EVar(_, _, e): if( e != null ) f(e);
		case EParent(e): f(e);
		case EBlock(el): for( e in el ) f(e);
		case EField(e, _): f(e);
		case EBinop(_, e1, e2): f(e1); f(e2);
		case EUnop(_, _, e): f(e);
		case ECall(e, args): f(e); for( a in args ) f(a);
		case EIf(c, e1, e2): f(c); f(e1); if( e2 != null ) f(e2);
		case EWhile(c, e): f(c); f(e);
		case EDoWhile(c, e): f(c); f(e);
		case EFor(_, it, e): f(it); f(e);
		case EBreak,EContinue:
		case EFunction(_, e, _, _): f(e);
		case EReturn(e): if( e != null ) f(e);
		case EArray(e, i): f(e); f(i);
		case EArrayDecl(el): for( e in el ) f(e);
		case ENew(_,el): for( e in el ) f(e);
		case EThrow(e): f(e);
		case ETry(e, _, _, c): f(e); f(c);
		case EObject(fl): for( fi in fl ) f(fi.e);
		case ETernary(c, e1, e2): f(c); f(e1); f(e2);
		case ESwitch(e, cases, def):
			f(e);
			for( c in cases ) {
				for( v in c.values ) f(v);
				f(c.expr);
			}
			if( def != null ) f(def);
		case EMeta(name, args, e): if( args != null ) for( a in args ) f(a); f(e);
		case ECheckType(e,_): f(e);
		default:
		}
	}

	public static function map( e : Expr, f : Expr -> Expr ):Expr {
		var edef = switch( expr(e) ) {
		case EConst(_), EIdent(_), EBreak, EContinue: expr(e);
		case EVar(n, t, e, isPublic, isStatic, isPrivate): EVar(n, t, if( e != null ) f(e) else null, isPublic, isStatic, isPrivate);
		case EParent(e): EParent(f(e));
		case EBlock(el): EBlock([for( e in el ) f(e)]);
		case EField(e, fi): EField(f(e),fi);
		case EBinop(op, e1, e2): EBinop(op, f(e1), f(e2));
		case EUnop(op, pre, e): EUnop(op, pre, f(e));
		case ECall(e, args): ECall(f(e),[for( a in args ) f(a)]);
		case EIf(c, e1, e2): EIf(f(c),f(e1),if( e2 != null ) f(e2) else null);
		case EWhile(c, e): EWhile(f(c),f(e));
		case EDoWhile(c, e): EDoWhile(f(c),f(e));
		case EFor(v, it, e): EFor(v, f(it), f(e));
		case EFunction(args, e, name, t, isPublic, isStatic, isOverride, isPrivate): EFunction(args, f(e), name, t, isPublic, isStatic, isOverride, isPrivate);
		case EReturn(e): EReturn(if( e != null ) f(e) else null);
		case EArray(e, i): EArray(f(e),f(i));
		case EArrayDecl(el): EArrayDecl([for( e in el ) f(e)]);
		case ENew(cl,el): ENew(cl,[for( e in el ) f(e)]);
		case EThrow(e): EThrow(f(e));
		case ETry(e, v, t, c): ETry(f(e), v, t, f(c));
		case EObject(fl): EObject([for( fi in fl ) { name : fi.name, e : f(fi.e) }]);
		case ETernary(c, e1, e2): ETernary(f(c), f(e1), f(e2));
		case ESwitch(e, cases, def): ESwitch(f(e), [for( c in cases ) { values : [for( v in c.values ) f(v)], expr : f(c.expr) } ], def == null ? null : f(def));
		case EMeta(name, args, e): EMeta(name, args == null ? null : [for( a in args ) f(a)], f(e));
		case ECheckType(e,t): ECheckType(f(e), t);
		case EImport(c): EImport(c);
		case EClass(name, el, extend, interfaces): EClass(name, [for( e in el ) f(e)], extend, interfaces);
		default: expr(e);
		}
		return mk(edef, e);
	}

	public static inline function expr( e : Expr ) : ExprDef {
		#if hscriptPos
		return e.e;
		#else
		return e;
		#end
	}

	public static inline function mk( e : ExprDef, p : Expr ):Expr {
		#if hscriptPos
		return { e : e, pmin : p.pmin, pmax : p.pmax, origin : p.origin, line : p.line };
		#else
		return e;
		#end
	}

	/**
	 * DO NOT USE INLINE ON THIS FUNCTION
	**/
	public static function argCount(func: haxe.Constraints.Function): Int {
		// https://github.com/pisayesiwsi/hscript-iris/blob/dev/crowplexus/hscript/Tools.hx#L206
		#if cpp
		return untyped __cpp__("{0}->__ArgCount()", func);
		#elseif js
		return untyped js.Syntax.code("{0}.length", func);
		#elseif hl
		var ft = hl.Type.getDynamic(func);
		if (ft.kind != HFun)
			return -1;
		return ft.getArgsCount();
		#else
		return -1;
		#end
	}

	public static function isUppercase(s:String) {
		if(s.length == 0) return false;
		var c:Int = StringTools.fastCodeAt(s, 0);
		if(StringTools.isEof(c)) return false; // Just in case :3
		return c >= 65 && c <= 90; // A-Z
	}

	public static inline function isCustomAbstract(obj:Dynamic):Bool
		return obj != null && obj is IHScriptAbstractBehaviour;

}