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

class Bytes {

	public var storeTypes : Bool = false;

	var bin : haxe.io.Bytes;
	var bout : haxe.io.BytesBuffer;
	var pin : Int;
	var hstrings : Map<String,Int>;
	var strings : Array<String>;
	var nstrings : Int;

	function new( ?bin ) {
		this.bin = bin;
		pin = 0;
		bout = new haxe.io.BytesBuffer();
		hstrings = new Map();
		strings = [null];
		nstrings = 1;
	}

	inline function getByte() {
		return bin.get(pin++);
	}

	inline function doEncodeNull() {
		bout.addByte(255);
	}

	function doEncodeString( v : String ) {
		var vid = hstrings.get(v);
		if( vid == null ) {
			if( nstrings == 256 ) {
				hstrings = new Map();
				nstrings = 1;
			}
			hstrings.set(v,nstrings);
			bout.addByte(0);
			var vb = haxe.io.Bytes.ofString(v);
			bout.addByte(vb.length);
			bout.add(vb);
			nstrings++;
		} else
			bout.addByte(vid);
	}

	function doDecodeString() {
		var id = bin.get(pin++);
		if( id == 0 ) {
			var len = bin.get(pin);
			var str = #if (haxe_ver < 3.103) bin.readString(pin+1,len); #else bin.getString(pin+1,len); #end
			pin += len + 1;
			if( strings.length == 255 )
				strings = [null];
			strings.push(str);
			return str;
		}
		return strings[id];
	}

	function doEncodeInt(v: Int) {
		bout.addInt32(v);
	}

	function doEncodeConst( c : Const ) {
		switch( c ) {
		case CInt(v):
			if( v >= 0 && v <= 255 ) {
				bout.addByte(0);
				bout.addByte(v);
			} else {
				bout.addByte(1);
				doEncodeInt(v);
			}
		case CFloat(f):
			bout.addByte(2);
			doEncodeString(Std.string(f));
		case CString(s):
			bout.addByte(3);
			doEncodeString(s);
		}
	}

	function doDecodeInt() {
		var i = bin.getInt32(pin);
		pin += 4;
		return i;
	}

	function doDecodeConst() {
		return switch( bin.get(pin++) ) {
		case 0:
			CInt(bin.get(pin++));
		case 1:
			var i = doDecodeInt();
			CInt(i);
		case 2:
			CFloat( Std.parseFloat(doDecodeString()) );
		case 3:
			CString( doDecodeString() );
		default:
			throw "Invalid code "+bin.get(pin-1);
		}
	}

	function doEncodeArguments(params:Array<Argument>, enumArgs:Bool = false) {
		bout.addByte(params.length);
		for(p in params) {
			doEncodeString(p.name);
			doEncodeBoolean(p.opt);
			if(!enumArgs) {
				if (p.value == null)
					doEncodeNull();
				else
					doEncode(p.value);
			}
			encodeType(p.t);
		}
	}

	function doDecodeArguments(enumArgs:Bool = false):Array<Argument> {
		var params:Array<Argument> = [];
		for(i in 0...getByte()) {
			final name:String = doDecodeString();
			final opt:Bool = doDecodeBoolean();
			final value:Null<Expr> = !enumArgs ? doDecode() : null;
			final t:Null<CType> = decodeType();
			params.push({
				name: name,
				t: t,
				opt: opt,
				value: value
			});
		}
		return params;
	}

	function doEncodeBoolean(b:Bool) {
		bout.addByte(b ? 1 : 0);
	}

	function doDecodeBoolean():Bool {
		return getByte() == 1;
	}

	function doEncode( e : Expr ) {
		#if hscriptPos
		doEncodeString(e.origin);
		doEncodeInt(e.line);
		var e = e.e;
		#end
		bout.addByte(Type.enumIndex(e));
		switch( e ) {
		case EPackage(n):
			doEncodeString(n == null ? "" : n);
		case EImport(c, asName, isUsing):
			doEncodeBoolean(isUsing ?? false);
			doEncodeString(c);
			doEncodeString(asName == null ? "" : asName);
		case EClass(name, fields, extend, interfaces, isFinal, _):
			doEncodeString(name);
			doEncodeString(extend == null ? "" : extend);
			doEncodeBoolean(isFinal ?? false);
			// interfaces
			if( interfaces.length >= 255 ) throw "assert";
			bout.addByte(interfaces.length);
			for( i in interfaces )
				doEncodeString(i);
			// class body
			if( fields.length >= 255 ) throw "assert";
			bout.addByte(fields.length);
			for( e in fields )
				doEncode(e);
		case EEnum(en, abs):
			final isAbstract:Bool = abs ?? false;
			doEncodeBoolean(isAbstract);
			encodeType(en.underlyingType);
			doEncodeString(en.name);
			bout.addByte(en.fields.length);
			for(e in en.fields) {
				doEncodeString(e.name);

				if(!isAbstract) 
					doEncodeArguments(e.args, true);
				else 
					if(e.value == null)
						doEncodeNull();
					else
						doEncode(e.value);
			}
		case ERegex(e, f):
			doEncodeString(e);
			doEncodeString(f);
		case EConst(c):
			doEncodeConst(c);
		case EIdent(v):
			doEncodeString(v);
		case EVar(n,t,e, pub, st, prv, fn, inl, g, s, iv):
			doEncodeString(n);
			encodeType(t);
			if( e == null )
				bout.addByte(255);
			else
				doEncode(e);

			doEncodeBoolean(pub ?? false);
			doEncodeBoolean(st ?? false);
			doEncodeBoolean(prv ?? false);
			doEncodeBoolean(fn ?? false);
			doEncodeBoolean(inl ?? false);

			if(g == null) doEncodeNull();
			else bout.addByte(g);
			if(s == null) doEncodeNull();
			else bout.addByte(s);

			doEncodeBoolean(iv ?? false);
		case EParent(e):
			doEncode(e);
		case EBlock(el):
			bout.addByte(el.length);
			for( e in el )
				doEncode(e);
		case EField(e,f,s):
			doEncode(e);
			doEncodeString(f);
			doEncodeBoolean(s ?? false);
		case EBinop(op,e1,e2):
			doEncodeString(op.toString());
			doEncode(e1);
			doEncode(e2);
		case EUnop(op,prefix,e):
			doEncodeString(op.toString()); // maybe doEncodeInt
			bout.addByte(prefix?1:0);
			doEncode(e);
		case ECall(e,el):
			doEncode(e);
			bout.addByte(el.length);
			for( e in el )
				doEncode(e);
		case EIf(cond,e1,e2):
			doEncode(cond);
			doEncode(e1);
			if( e2 == null )
				bout.addByte(255);
			else
				doEncode(e2);
		case EWhile(cond,e):
			doEncode(cond);
			doEncode(e);
		case EDoWhile(cond,e):
			doEncode(cond);
			doEncode(e);
		case EFor(v,it,e):
			doEncodeString(v);
			doEncode(it);
			doEncode(e);
		case EBreak, EContinue:
		case EFunction(params,e,name,t, pub, st, ov, prv, fn, inl):
			// bout.addByte(params.length);
			// for( p in params )
			// 	doEncodeString(p.name);
			doEncodeArguments(params);
			doEncode(e);
			doEncodeString(name == null?"":name);
			encodeType(t);

			doEncodeBoolean(pub ?? false);
			doEncodeBoolean(st ?? false);
			doEncodeBoolean(ov ?? false);
			doEncodeBoolean(prv ?? false);
			doEncodeBoolean(fn ?? false);
			doEncodeBoolean(inl ?? false);
		case EReturn(e):
			if( e == null )
				bout.addByte(255);
			else
				doEncode(e);
		case EArray(e,index):
			doEncode(e);
			doEncode(index);
		case EArrayDecl(el):
			if( el.length >= 255 ) throw "assert";
			bout.addByte(el.length);
			for( e in el )
				doEncode(e);
		case ENew(cl,params, args):
			doEncodeString(cl);
			bout.addByte(params.length);
			for( e in params )
				doEncode(e);
			if(storeTypes) {
				if( args == null )
					bout.addByte(0);
				else {
					bout.addByte(args.length);
					for( a in args )
						encodeType(a);
				}
			}
		case EThrow(e):
			doEncode(e);
		case ETry(e,v,t,ecatch):
			doEncode(e);
			doEncodeString(v);
			encodeType(t);
			doEncode(ecatch);
		case EObject(fl):
			bout.addByte(fl.length);
			for( f in fl ) {
				doEncodeString(f.name);
				doEncode(f.e);
			}
		case ETernary(cond, e1, e2):
			doEncode(cond);
			doEncode(e1);
			doEncode(e2);
		case ESwitch(e, cases, def):
			doEncode(e);
			for( c in cases ) {
				if( c.values.length == 0 ) throw "assert";
				for( v in c.values )
					doEncode(v);
				bout.addByte(255);
				doEncode(c.expr);
			}
			bout.addByte(255);
			if( def == null ) bout.addByte(255) else doEncode(def);
		case EMeta(name,args,e):
			doEncodeString(name);
			bout.addByte(args == null ? 0 : args.length + 1);
			if( args != null ) for( e in args ) doEncode(e);
			doEncode(e);
		case ECheckType(e,t):
			doEncode(e);
			encodeType(t);
		case ECast(e, t):
			doEncode(e);
			encodeType(t);
		}
	}

	function encodeType(t:CType) {
		if(!storeTypes) return;
		if(t == null) {
			bout.addByte(255);
			return;
		}

		bout.addByte(t.getIndex());
		switch (t) {
			case CTPath(path, params):
				doEncodeString(path.join("."));
				if (params == null)
					bout.addByte(255);
				else {
					bout.addByte(params.length);
					for (p in params)
						encodeType(p);
				}
			case CTFun(args, ret):
				bout.addByte(args.length);
				for (a in args)
					encodeType(a);
				encodeType(ret);
			case CTAnon(fields):
				doEncodeInt(fields.length);
				for (f in fields) {
					doEncodeString(f.name);
					encodeType(f.t);
					if (f.meta == null)
						bout.addByte(255);
					else {
						bout.addByte(f.meta.length);
						for (m in f.meta) {
							doEncodeString(m.name);
							doEncodeInt(m.params.length);
							for (p in m.params)
								doEncode(p);
						}
					}
				}
			case CTParent(t):
				encodeType(t);
			case CTOpt(t):
				encodeType(t);
			case CTNamed(n, t):
				doEncodeString(n);
				encodeType(t);
			case CTExpr(e):
				doEncode(e);
		}
	}

	function doDecode() : Expr {
	#if hscriptPos
		if (bin.get(pin) == 255) {
			pin++;
			return null;
		}
		var origin = doDecodeString();
		var line = doDecodeInt();
		return { e : _doDecode(), pmin : 0, pmax : 0, origin : origin, line : line };
	}
	function _doDecode() : ExprDef {
	#end
		return switch( getByte() ) {
		case BCONST:
			EConst( doDecodeConst() );
		case BIDENT:
			EIdent( doDecodeString() );
		case BVAR:
			final v = doDecodeString();
			final t = decodeType();
			final e = doDecode();

			final isPublic = doDecodeBoolean();
			final isStatic = doDecodeBoolean();
			final isPrivate = doDecodeBoolean();
			final isFinal = doDecodeBoolean();
			final isInline = doDecodeBoolean();

			final getter = getByte();
			final setter = getByte();

			final isVar = doDecodeBoolean();

			EVar(v, t, e, isPublic, isStatic, isPrivate, isFinal, isInline, getter == 255 ? null : getter, setter == 255 ? null : setter, isVar );
		case BPARENT:
			EParent(doDecode());
		case BBLOCK:
			var a = [];
			for( i in 0...getByte() )
				a.push(doDecode());
			EBlock(a);
		case BFIELD:
			final e = doDecode();
			final f = doDecodeString();
			final s = doDecodeBoolean();
			EField(e,f,s);
		case BBINOP:
			var op = Binop.fromString(doDecodeString());
			var e1 = doDecode();
			EBinop(op,e1,doDecode());
		case BUNOP:
			var op = Unop.fromString(doDecodeString());
			var prefix = getByte() != 0;
			EUnop(op,prefix,doDecode());
		case BCALL:
			var e = doDecode();
			var params = [];
			for( i in 0...getByte() )
				params.push(doDecode());
			ECall(e,params);
		case BIF:
			var cond = doDecode();
			var e1 = doDecode();
			EIf(cond,e1,doDecode());
		case BWHILE:
			var cond = doDecode();
			EWhile(cond,doDecode());
		case BFOR:
			var v = doDecodeString();
			var it = doDecode();
			EFor(v,it,doDecode());
		case BBREAK:
			EBreak;
		case BCONTINUE:
			EContinue;
		case BFUNCTION:
			// var params = new Array<Argument>();
			// for( i in 0...getByte() )
			// 	params.push({ name : doDecodeString(), opt: false, value: null, t: null });
			var params:Array<Argument> = doDecodeArguments();
			var e = doDecode();
			var name = doDecodeString();
			var t = decodeType();

			final isPublic = doDecodeBoolean();
			final isStatic = doDecodeBoolean();
			final isOverride = doDecodeBoolean();
			final isPrivate = doDecodeBoolean();
			final isFinal = doDecodeBoolean();
			final isInline = doDecodeBoolean();

			EFunction(params,e,(name == "") ? null: name, t, isPublic, isStatic, isOverride, isPrivate, isFinal, isInline);
		case BRETURN:
			EReturn(doDecode());
		case BARRAY:
			var e = doDecode();
			EArray(e,doDecode());
		case BARRAYDECL:
			var el = [];
			for( i in 0...getByte() )
				el.push(doDecode());
			EArrayDecl(el);
		case BNEW:
			var cl = doDecodeString();
			var el:Array<Expr> = new Array();
			for( i in 0...getByte() )
				el.push(doDecode());
			var targs:Array<CType> = null;
			if( storeTypes ) {
				var len = getByte();
				if( len > 0 )
					targs = [for( i in 0...len ) decodeType()];
			}
			ENew(cl,el,targs);
		case BTHROW:
			EThrow(doDecode());
		case BTRY:
			var e = doDecode();
			var v = doDecodeString();
			ETry(e,v,decodeType(),doDecode());
		case BOBJECT:
			var fl:Array<ObjectField> = [];
			for( i in 0...bin.get(pin++) ) {
				var name = doDecodeString();
				var e = doDecode();
				fl.push({ name : name, e : e });
			}
			EObject(fl);
		case BTERNARY:
			var cond = doDecode();
			var e1 = doDecode();
			var e2 = doDecode();
			ETernary(cond, e1, e2);
		case BSWITCH:
			var e = doDecode();
			var cases:Array<SwitchCase> = [];
			while( true ) {
				var v = doDecode();
				if( v == null ) break;
				var values = [v];
				while( true ) {
					v = doDecode();
					if( v == null ) break;
					values.push(v);
				}
				cases.push( { values : values, expr : doDecode() } );
			}
			var def = doDecode();
			ESwitch(e, cases, def);
		case BDOWHILE:
			var cond = doDecode();
			EDoWhile(cond,doDecode());
		case BMETA:
			var name = doDecodeString();
			var count = getByte();
			var args = count == 0 ? null : [for( i in 0...count - 1 ) doDecode()];
			EMeta(name, args, doDecode());
		case BCHECKTYPE:
			ECheckType(doDecode(), decodeType());
		case BPACKAGE:
			final pkg:String = doDecodeString();
			EPackage(pkg == "" ? null : pkg);
		case BIMPORT:
			final isUsing:Bool = doDecodeBoolean();
			final cls = doDecodeString();
			final asName = doDecodeString();
			EImport(cls, asName == "" ? null : asName, isUsing);
		case BCLASS:
			final name:String = doDecodeString();
			final extend:String = doDecodeString();
			final isFinal:Bool = doDecodeBoolean();
			final interfaces:Array<String> = [];
			var count:Int = getByte();
			if(count > 0) {
				for( i in 0...count )
					interfaces.push(doDecodeString());
			}
			
			final fields:Array<Expr> = [];
			count = getByte();
			if(count > 0) {
				for( i in 0...count )
					fields.push(doDecode());
			}
			
			EClass(name, fields, extend == "" ? null : extend, interfaces, isFinal);
		case BENUM:
			final isAbstract:Bool = doDecodeBoolean();
			final underlyingType:Null<CType> = decodeType();
			final name = doDecodeString();
			final enumFields:Array<EnumField> = [];
			final count = getByte();
			for(i in 0...count) {
				final fieldName = doDecodeString();

				if(!isAbstract) {
					final args:Array<Argument> = doDecodeArguments(true);
					enumFields.push({
						name: fieldName,
						args: args,
						value: null
					});
				}
				else {
					enumFields.push({
						name: fieldName,
						args: [], // TODO: make it null
						value: doDecode()
					});
				}
			}
			EEnum({name: name, fields: enumFields, underlyingType: underlyingType}, isAbstract);
		case BCAST:
			ECast(doDecode(), decodeType());
		case BREGEX:
			final r = doDecodeString();
			final f = doDecodeString();
			ERegex(r, f);
		case 255:
			null;
		default:
			throw "Invalid code "+bin.get(pin - 1);
		}
	}

	function decodeType() : CType {
		if( !storeTypes )
			return null;
		return switch( getByte() ) {
		case 255: null;
		case BTPATH:
			var path = doDecodeString().split(".");
			var plen = getByte();
			var params = plen == 255 ? null : [for( i in 0...plen ) decodeType()];
			CTPath(path, params);
		case BTFUN:
			CTFun([for( v in 0...getByte() ) decodeType()], decodeType());
		case BTANON:
			CTAnon([for( v in 0...doDecodeInt() ) { name : doDecodeString(), t : decodeType(), meta : {
				var v = getByte();
				if( v == 255 ) null else [for( i in 0...v ) { name : doDecodeString(), params : [for( i in 0...getByte() ) doDecode()] }];
			}}]);
		case BTPARENT:
			CTParent(decodeType());
		case BTOPT:
			CTOpt(decodeType());
		case BTNAMED:
			CTNamed(doDecodeString(),decodeType());
		case BTEXPR:
			CTExpr(doDecode());
		default:
			throw "Invalid code "+bin.get(pin - 1);
		}
	}

	public static function encode( e : Expr, allowTypes:Bool = false ) : haxe.io.Bytes {
		var b = new Bytes();
		b.storeTypes = allowTypes;
		b.doEncode(e);
		return b.bout.getBytes();
	}

	public static function decode( bytes : haxe.io.Bytes, allowTypes:Bool = false ) : Expr {
		var b = new Bytes(bytes);
		b.storeTypes = allowTypes;
		return b.doDecode();
	}

}

enum abstract ByteExpr(Int) from Int to Int {
	var BCONST = 0x00;
	var BIDENT;
	var BVAR;
	var BPARENT;
	var BBLOCK;
	var BFIELD;
	var BBINOP;
	var BUNOP;
	var BCALL;
	var BIF;
	var BWHILE;
	var BFOR;
	var BBREAK;
	var BCONTINUE;
	var BFUNCTION;
	var BRETURN;
	var BARRAY;
	var BARRAYDECL;
	var BNEW;
	var BTHROW;
	var BTRY;
	var BOBJECT;
	var BTERNARY;
	var BSWITCH;
	var BDOWHILE;
	var BMETA;
	var BCHECKTYPE;

	var BPACKAGE = 0x1B;
	var BIMPORT;
	var BCLASS;
	var BENUM;
	var BCAST;
	var BREGEX;
}

enum abstract ByteType(Int) from Int to Int {
	var BTPATH = 0x00;
	var BTFUN;
	var BTANON;
	var BTPARENT;
	var BTOPT;
	var BTNAMED;
	var BTEXPR;
}
