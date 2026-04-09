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

typedef Int8 = #if cpp cpp.Int8 #elseif java java.Int8 #elseif cs cs.Int8 #else Int #end;
typedef Int16 = #if cpp cpp.Int16 #elseif java java.Int16 #elseif cs cs.Int16 #else Int #end;
typedef Int32 = #if cpp cpp.Int32 #else Int #end;
typedef Int64 = #if cpp cpp.Int64 #elseif java java.Int64 #elseif cs cs.Int64 #else Int #end;

typedef UInt8 = #if cpp cpp.UInt8 #elseif cs cs.UInt8 #else Int #end;
typedef UInt16 = #if cpp cpp.UInt16 #elseif cs cs.UInt16 #else Int #end;

enum abstract Binop(Int) from Int to Int {
	var OpAdd = 0;
	var OpSub = 1;
	var OpMult = 2;
	var OpDiv = 3;
	var OpMod = 4;
	var OpAnd = 5;
	var OpOr = 6;
	var OpXor = 7;
	var OpShl = 8;
	var OpShr = 9;
	var OpUshr = 10;
	var OpEq = 11;
	var OpNeq = 12;
	var OpGte = 13;
	var OpLte = 14;
	var OpGt = 15;
	var OpLt = 16;
	var OpBoolOr = 17;
	var OpBoolAnd = 18;
	var OpIs = 19;
	var OpAssign = 20;
	var OpNcoal = 21;
	var OpInterval = 22;
	var OpArrow = 23;
	var OpAddAssign = 24;
	var OpSubAssign = 25;
	var OpMultAssign = 26;
	var OpDivAssign = 27;
	var OpModAssign = 28;
	var OpAndAssign = 29;
	var OpOrAssign = 30;
	var OpXorAssign = 31;
	var OpShlAssign = 32;
	var OpShrAssign = 33;
	var OpUshrAssign = 34;
	var OpNcoalAssign = 35;
	var OpArrowFn = 36;

	public static inline function fromString(s:String):Binop {
		return switch(s) {
			case "+": OpAdd;
			case "-": OpSub;
			case "*": OpMult;
			case "/": OpDiv;
			case "%": OpMod;
			case "&": OpAnd;
			case "|": OpOr;
			case "^": OpXor;
			case "<<": OpShl;
			case ">>": OpShr;
			case ">>>": OpUshr;
			case "==": OpEq;
			case "!=": OpNeq;
			case ">=": OpGte;
			case "<=": OpLte;
			case ">": OpGt;
			case "<": OpLt;
			case "||": OpBoolOr;
			case "&&": OpBoolAnd;
			case "is": OpIs;
			case "=": OpAssign;
			case "??": OpNcoal;
			case "...": OpInterval;
			case "->": OpArrow;
			case "=>": OpArrowFn;
			case "+=": OpAddAssign;
			case "-=": OpSubAssign;
			case "*=": OpMultAssign;
			case "/=": OpDivAssign;
			case "%=": OpModAssign;
			case "&=": OpAndAssign;
			case "|=": OpOrAssign;
			case "^=": OpXorAssign;
			case "<<=": OpShlAssign;
			case ">>=": OpShrAssign;
			case ">>>=": OpUshrAssign;
			case "??=": OpNcoalAssign;
			default: -1;
		}
	}

	public inline function toString():String {
		return switch(this) {
			case OpAdd: "+";
			case OpSub: "-";
			case OpMult: "*";
			case OpDiv: "/";
			case OpMod: "%";
			case OpAnd: "&";
			case OpOr: "|";
			case OpXor: "^";
			case OpShl: "<<";
			case OpShr: ">>";
			case OpUshr: ">>>";
			case OpEq: "==";
			case OpNeq: "!=";
			case OpGte: ">=";
			case OpLte: "<=";
			case OpGt: ">";
			case OpLt: "<";
			case OpBoolOr: "||";
			case OpBoolAnd: "&&";
			case OpIs: "is";
			case OpAssign: "=";
			case OpNcoal: "??";
			case OpInterval: "...";
			case OpArrow: "->";
			case OpArrowFn: "=>";
			case OpAddAssign: "+=";
			case OpSubAssign: "-=";
			case OpMultAssign: "*=";
			case OpDivAssign: "/=";
			case OpModAssign: "%=";
			case OpAndAssign: "&=";
			case OpOrAssign: "|=";
			case OpXorAssign: "^=";
			case OpShlAssign: "<<=";
			case OpShrAssign: ">>=";
			case OpUshrAssign: ">>>=";
			case OpNcoalAssign: "??=";
			default: "?";
		}
	}
}

enum abstract Unop(Int) from Int to Int {
	var OpNot = 0;
	var OpNeg = 1;
	var OpIncrement = 2;
	var OpDecrement = 3;
	var OpNegBits = 4;

	public static inline function fromString(s:String):Unop {
		return switch(s) {
			case "!": OpNot;
			case "-": OpNeg;
			case "++": OpIncrement;
			case "--": OpDecrement;
			case "~": OpNegBits;
			default: -1;
		}
	}

	public inline function toString():String {
		return switch(this) {
			case OpNot: "!";
			case OpNeg: "-";
			case OpIncrement: "++";
			case OpDecrement: "--";
			case OpNegBits: "~";
			default: "?";
		}
	}
}

typedef UInt32 = #if cpp cpp.UInt32 #else Int #end;
typedef UInt64 = #if cpp cpp.UInt64 #else Int #end;

enum Const {
	CInt( v : Int );
	CFloat( f : Float );
	CString( s : String, ?i : Bool );
}

#if hscriptPos
@:structInit
final class Expr {
	public var e : ExprDef;
	public var pmin : Int;
	public var pmax : Int;
	public var origin : String;
	public var line : Int;
}
enum ExprDef {
#else
typedef ExprDef = Expr;
enum Expr {
#end
	EConst( c : Const );
	EIdent( v : String );
	EVar( n : String, ?t : CType, ?e : Expr, ?isPublic : Bool, ?isStatic : Bool, ?isPrivate : Bool, ?isFinal : Bool, ?isInline : Bool, ?get : FieldPropertyAccess, ?set : FieldPropertyAccess, ?isVar:Bool );
	EParent( e : Expr );
	EBlock( e : Array<Expr> );
	EField( e : Expr, f : String , ?safe : Bool );
	EBinop( op : Binop, e1 : Expr, e2 : Expr );
	EUnop( op : Unop, prefix : Bool, e : Expr );
	ECall( e : Expr, params : Array<Expr> );
	EIf( cond : Expr, e1 : Expr, ?e2 : Expr );
	EWhile( cond : Expr, e : Expr );
	EFor( v : String, it : Expr, e : Expr, ?ithv: String);
	EBreak;
	EContinue;
	EFunction( args : Array<Argument>, e : Expr, ?name : String, ?ret : CType, ?isPublic : Bool, ?isStatic : Bool, ?isOverride : Bool, ?isPrivate : Bool, ?isFinal : Bool, ?isInline : Bool );
	EReturn( ?e : Expr );
	EArray( e : Expr, index : Expr );
	EArrayDecl( e : Array<Expr>, ?wantedType: CType );
	ENew( cl : String, params : Array<Expr>, ?paramType:Array<CType> );
	EThrow( e : Expr );
	ETry( e : Expr, v : String, t : Null<CType>, ecatch : Expr );
	EObject( fl : Array<ObjectField> );
	ETernary( cond : Expr, e1 : Expr, e2 : Expr );
	ESwitch( e : Expr, cases : Array<SwitchCase>, ?defaultExpr : Expr );
	EDoWhile( cond : Expr, e : Expr);
	EMeta( name : String, args : Array<Expr>, e : Expr );
	ECheckType( e : Expr, t : CType );

	EPackage( ?n:String );
	EImport( c : String, ?asname:String, ?isUsing:Bool );
	EClass( name:String, fields:Array<Expr>, ?extend:String, interfaces:Array<String>, ?isFinal:Bool, ?isPrivate:Bool );
	EEnum( en:EnumDecl, ?isAbstract:Bool );
	ECast(e:Expr, ?t:CType);
	ERegex(e:String, flags:String);
}

@:structInit
final class ObjectField {
	public var name : String;
	public var e : Expr;
}

@:structInit
final class SwitchCase {
	public var values : Array<Expr>;
	public var expr : Expr;
}

@:structInit
final class Argument {
	public var name : String;
	public var t : CType;
	public var opt : Bool;
	public var value : Expr;
}

@:structInit
final class MetadataEntry {
	public var name : String;
	public var params : Array<Expr>;
}

typedef Metadata = Array<MetadataEntry>;

@:structInit
final class EnumDecl {
	public var name : String;
	public var fields : Array<EnumField>;
	public var underlyingType : Null<CType>;
}

@:structInit
final class EnumField {
	public var name : String;
	public var args : Array<Argument>;
	public var value : Null<Expr>;
}

enum CType {
	CTPath( path : Array<String>, ?params : Array<CType> );
	CTFun( args : Array<CType>, ret : CType );
	CTAnon( fields : Array<{ name : String, t : CType, ?meta : Metadata }> );
	CTParent( t : CType );
	CTOpt( t : CType );
	CTNamed( n : String, t : CType );
	CTExpr( e : Expr ); // for type parameters only
}

#if hscriptPos
class Error {
	public var e : ErrorDef;
	public var pmin : Int;
	public var pmax : Int;
	public var origin : String;
	public var line : Int;
	public function new(e, pmin, pmax, origin, line) {
		this.e = e;
		this.pmin = pmin;
		this.pmax = pmax;
		this.origin = origin;
		this.line = line;
	}
	public function toString(): String {
		return Printer.errorToString(this);
	}
}
enum ErrorDef {
#else
enum Error {
#end
	EInvalidChar( c : Int );
	EUnexpected( s : String );
	EUnterminatedString;
	EUnterminatedComment;
	EInvalidPreprocessor( msg : String );
	EUnknownVariable( v : String );
	EInvalidIterator( v : String );
	EInvalidOp( op : String );
	EInvalidAccess( f : String );
	ECustom( msg : String );
	EInvalidClass( className : String);
	EAlreadyExistingClass( className : String);
}


enum ModuleDecl {
	DPackage( path : Array<String> );
	DImport( path : Array<String>, ?everything : Bool );
	DClass( c : ClassDecl );
	DTypedef( c : TypeDecl );
}

typedef ModuleType = {
	var name : String;
	var params : {}; // TODO : not yet parsed
	var meta : Metadata;
	var isPrivate : Bool;
}

typedef ClassDecl = {> ModuleType,
	var extend : Null<CType>;
	var implement : Array<CType>;
	var fields : Array<FieldDecl>;
	var isExtern : Bool;
}

typedef TypeDecl = {> ModuleType,
	var t : CType;
}

typedef FieldDecl = {
	var name : String;
	var meta : Metadata;
	var kind : FieldKind;
	var access : Array<FieldAccess>;
}

enum abstract FieldAccess(UInt8) {
	var APublic;
	var APrivate;
	var AInline;
	var AOverride;
	var AStatic;
	var AMacro;
}

enum abstract FieldPropertyAccess(UInt8) {
	var ADefault;
	var ANull;
	var AGet;
	var ASet;
	var ADynamic;
	var ANever;
}

enum FieldKind {
	KFunction( f : FunctionDecl );
	KVar( v : VarDecl );
}

@:structInit
final class FunctionDecl {
	public var args : Array<Argument>;
	public var body : Expr;
	public var ret : Null<CType>;
}

typedef VarDecl = {
	var get : Null<String>;
	var set : Null<String>;
	var expr : Null<Expr>;
	var type : Null<CType>;
}
