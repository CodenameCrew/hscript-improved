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

/*
 * YoshiCrafter Engine fixes:
 * - Added Error handler
 * - Added Imports
 * - Added @:bypassAccessor
 */
package hscript;

import hscript.proxy.ProxyType;
import hscript.Tools.EnumValue;
import hscript.Tools.HScriptEnum;
import haxe.Constraints.Function;
import hscript.utils.UsingHandler;
import hscript.customclass.CustomClassDecl;
import hscript.customclass.CustomClass;
import hscript.utils.UsingEntry;
import haxe.CallStack;
import hscript.utils.UnsafeReflect;
import haxe.PosInfos;
import hscript.Expr;
import haxe.Constraints.IMap;
import Type.ValueType;

using StringTools;

private enum Stop {
	SBreak;
	SContinue;
	SReturn;
}

enum abstract ScriptObjectType(UInt8) {
	var SClass;
	var SObject;
	var SStaticClass;
	//var SCustomClass; // custom classes
	var SBehaviourClass; // hget and hset
	var SAccessBehaviourObject; // hget and hset with __allowSetGet
	var SNull;
}

@:structInit
class DeclaredVar {
	public var r:Dynamic;
	public var depth:Int;
}

@:structInit
class RedeclaredVar {
	public var n:String;
	public var old:DeclaredVar;
	public var depth:Int;
}

@:access(hscript.customclass.CustomClass)
@:access(hscript.customclass.CustomClassDecl)
@:analyzer(optimize, local_dce, fusion, user_var_fusion)
class Interp {
	private static var _customClasses:Map<String, CustomClassDecl> = new Map<String, CustomClassDecl>();
	private static var _customClassAliases:Map<String, String> = new Map<String, String>();

	public static function getCustomClass(name:String) {
		// Retrieves the real class name
		var realName = _customClassAliases.get(name);
		if(realName != null) name = realName;
		return _customClasses.get(name);
	}

	public static function customClassExist(name:String):Bool {
		return _customClassAliases.exists(name) || _customClasses.exists(name);
	}

	private static function registerCustomClass(c:CustomClassDecl, ?as:String, ?inCustomClass:Bool) {
		#if CUSTOM_CLASSES
		var name = c.classDecl.name;
		if (c.pkg != null && (inCustomClass != null && inCustomClass)) {
			name = '${c.pkg.join(".")}.$name';//c.pkg.join(".") + "." + name;
		}
		if (as != null) _customClassAliases.set(as, name);
		_customClasses.set(name, c);
		#end
	}

	public var scriptObject(default, set):Dynamic;
	private var _hasScriptObject(default, null):Bool = false;
	private var _scriptObjectType(default, null):ScriptObjectType = SNull;
	public function set_scriptObject(v:Dynamic) {
		switch(Type.typeof(v)) {
			case TClass(c): // Class Access
				__instanceFields = Type.getInstanceFields(c);
				if(v is IHScriptCustomAccessBehaviour) {
					_scriptObjectType = SAccessBehaviourObject;
				} else if(v is IHScriptCustomBehaviour) {
					_scriptObjectType = SBehaviourClass;
				} else {
					_scriptObjectType = SClass;
				}
			case TObject: // Object Access or Static Class Access
				var cls = Type.getClass(v);
				switch(Type.typeof(cls)) {
					case TClass(c): // Static Class Access
						__instanceFields = Type.getInstanceFields(c);
						_scriptObjectType = SStaticClass;
					default: // Object Access
						__instanceFields = Reflect.fields(v);
						_scriptObjectType = SObject;
				}
			default: // Null or other
				__instanceFields = [];
				_scriptObjectType = SNull;
		}
		_hasScriptObject = v != null;
		return scriptObject = v;
	}
	public var errorHandler:Error->Void;
	public var importFailedCallback:Array<String> -> ?Null<String> -> Bool;

	public var customClasses:Map<String, Dynamic>;
	public var variables:Map<String, Dynamic>;
	public var publicVariables:Map<String, Dynamic>;
	public var staticVariables:Map<String, Dynamic>;

	// warning can be null
	public var locals:Map<String, DeclaredVar>;
	var binops:Map<String, Expr->Expr->Dynamic>;

	var depth:Int = 0;
	var inTry:Bool;
	var declared:Array<RedeclaredVar>;
	var returnValue:Dynamic;

	var isBypassAccessor:Bool = false;
	var isPrivateAccess:Bool = false;

	public var importEnabled:Bool = true;

	public var allowStaticVariables:Bool = false;
	public var allowPublicVariables:Bool = false;

	public var importBlocklist:Array<String> = [
		// "flixel.FlxG"
	];

	var __instanceFields:Array<String> = [];
	#if hscriptPos
	var curExpr:Expr;
	#end

	var _proxy(default, null):Null<CustomClass> = null;
	var _nextCallObject(default, null):Dynamic = null;
	var _inCustomClass(get, never):Bool;

	private function get__inCustomClass():Bool {
		return _proxy != null;
	}

	public function new(?proxy:CustomClass) {
		locals = new Map();
		declared = [];
		resetVariables();
		initOps();
		
		this._proxy = proxy;
	}

	private function resetVariables():Void {
		//customClasses = new Map<String, Dynamic>();
		variables = new Map<String, Dynamic>();
		publicVariables = new Map<String, Dynamic>();
		staticVariables = new Map<String, Dynamic>();
		variables.set("null", null);
		variables.set("true", true);
		variables.set("false", false);
		variables.set("trace", Reflect.makeVarArgs(function(el) {
			var inf = posInfos();
			var v = el.shift();
			if (el.length > 0)
				inf.customParams = el;
			haxe.Log.trace(Std.string(v), inf);
		}));
	}

	public function posInfos():PosInfos {
		#if hscriptPos
		if (curExpr != null)
			return cast {fileName: curExpr.origin, lineNumber: curExpr.line};
		#end
		return cast {fileName: "hscript", lineNumber: 0};
	}

	function initOps():Void {
		var me = this;
		binops = new Map();
		binops.set("+", function(e1, e2) return me.expr(e1) + me.expr(e2));
		binops.set("-", function(e1, e2) return me.expr(e1) - me.expr(e2));
		binops.set("*", function(e1, e2) return me.expr(e1) * me.expr(e2));
		binops.set("/", function(e1, e2) return me.expr(e1) / me.expr(e2));
		binops.set("%", function(e1, e2) return me.expr(e1) % me.expr(e2));
		binops.set("&", function(e1, e2) return me.expr(e1) & me.expr(e2));
		binops.set("|", function(e1, e2) return me.expr(e1) | me.expr(e2));
		binops.set("^", function(e1, e2) return me.expr(e1) ^ me.expr(e2));
		binops.set("<<", function(e1, e2) return me.expr(e1) << me.expr(e2));
		binops.set(">>", function(e1, e2) return me.expr(e1) >> me.expr(e2));
		binops.set(">>>", function(e1, e2) return me.expr(e1) >>> me.expr(e2));
		binops.set("==", function(e1, e2) return me.expr(e1) == me.expr(e2));
		binops.set("!=", function(e1, e2) return me.expr(e1) != me.expr(e2));
		binops.set(">=", function(e1, e2) return me.expr(e1) >= me.expr(e2));
		binops.set("<=", function(e1, e2) return me.expr(e1) <= me.expr(e2));
		binops.set(">", function(e1, e2) return me.expr(e1) > me.expr(e2));
		binops.set("<", function(e1, e2) return me.expr(e1) < me.expr(e2));
		binops.set("||", function(e1, e2) return me.expr(e1) == true || me.expr(e2) == true);
		binops.set("&&", function(e1, e2) return me.expr(e1) == true && me.expr(e2) == true);
		binops.set("is", checkIsType);
		binops.set("=", assign);
		binops.set("??", function(e1, e2) {
			var expr1:Dynamic = me.expr(e1);
			return expr1 == null ? me.expr(e2) : expr1;
		});
		binops.set("...", function(e1, e2) return new IntIterator(me.expr(e1), me.expr(e2)));
		assignOp("+=", function(v1:Dynamic, v2:Dynamic) return v1 + v2);
		assignOp("-=", function(v1:Float, v2:Float) return v1 - v2);
		assignOp("*=", function(v1:Float, v2:Float) return v1 * v2);
		assignOp("/=", function(v1:Float, v2:Float) return v1 / v2);
		assignOp("%=", function(v1:Float, v2:Float) return v1 % v2);
		assignOp("&=", function(v1, v2) return v1 & v2);
		assignOp("|=", function(v1, v2) return v1 | v2);
		assignOp("^=", function(v1, v2) return v1 ^ v2);
		assignOp("<<=", function(v1, v2) return v1 << v2);
		assignOp(">>=", function(v1, v2) return v1 >> v2);
		assignOp(">>>=", function(v1, v2) return v1 >>> v2);
		assignOp("??" + "=", function(v1, v2) return v1 == null ? v2 : v1);
	}

	function checkIsType(e1:Expr,e2:Expr): Bool {
		var expr1:Dynamic = expr(e1);

		return switch(Tools.expr(e2))
		{
			// TODO: type check for custom classes
			case EIdent("Class"):
				Std.isOfType(expr1, Class);
			case EIdent("Map") | EIdent("IMap"):
				Std.isOfType(expr1, IMap);
			default:
				var expr2:Dynamic = expr(e2);
				expr2 != null ? Std.isOfType(expr1, expr2) : false;
		}
	}

	public function varExists(name:String):Bool {
		return allowStaticVariables && staticVariables.exists(name) || allowPublicVariables && publicVariables.exists(name) || variables.exists(name);
	}

	public function setVar(name:String, v:Dynamic):Void {
		if (_inCustomClass && _proxy.superClass != null) {
			if (_proxy.superIsCustomClass) {
				var oldPrivate = _proxy.__allowPrivateAccess;
				_proxy.__allowPrivateAccess = true;
				cast(_proxy.superClass, CustomClass).hset(name, v);
				_proxy.__allowPrivateAccess = oldPrivate;
				return;
			}
			else if (_proxy.superHasField(name)) {
				Reflect.setProperty(_proxy.superClass, name, v);
				return;
			}
		}

		if (allowStaticVariables && staticVariables.exists(name))
			staticVariables.set(name, v);
		else if (allowPublicVariables && publicVariables.exists(name))
			publicVariables.set(name, v);
		else
			variables.set(name, v);
	}

	function assign(e1:Expr, e2:Expr):Dynamic {
		var v = expr(e2);
		switch (Tools.expr(e1)) {
			case EIdent(id):
				// TODO: redo field check
				// Make sure setting superclass/static fields directly works.
				// Also ensures property functions are accounted for.
				if (_inCustomClass) {
					if (_proxy.__class.hasField(id)) {
						var v = expr(e2);
						var oldPrivate = _proxy.__class.__allowPrivateAccess;
						_proxy.__class.__allowPrivateAccess = true;
						_proxy.__class.hset(id, v);
						_proxy.__class.__allowPrivateAccess = oldPrivate;
						return v;
					} 
					if (_proxy.superClass == null && _proxy.__class.classDecl.extend != null && !_proxy.hasVar(id)) {
						// Caches the declaration to set it once superClass is created
						var v = expr(e2);
						_proxy.cacheSuperField(id, v);
						return v;
					}
					else {
						var oldPrivate = _proxy.__allowPrivateAccess;
						try {
							var v = expr(e2);
							_proxy.__allowPrivateAccess = true;
							_proxy.hset(id, v); // superClass check already handled in Custom Class
							_proxy.__allowPrivateAccess = oldPrivate;
							return v;
						}
						catch(e) {
							_proxy.__allowPrivateAccess = oldPrivate;
							// TODO: throw an error
						}
					}
				}
				var l = locals.get(id);
				if (l == null) {
					if (_hasScriptObject && !varExists(id)) {
						var instanceHasField = __instanceFields.contains(id);

						if (_scriptObjectType == SObject && instanceHasField) {
							UnsafeReflect.setField(scriptObject, id, v);
							return v;
						} 
						else if(_scriptObjectType == SAccessBehaviourObject) {
							var obj:IHScriptCustomAccessBehaviour = cast scriptObject;
							var oldAccessor = obj.__allowSetGet;
							var oldPrivate = obj.__allowPrivateAccess;

							if (isBypassAccessor)
								obj.__allowSetGet = false;
							if (isPrivateAccess)
								obj.__allowPrivateAccess = true;

							var res = obj.hset(id, v);

							obj.__allowSetGet = oldAccessor;
							obj.__allowPrivateAccess = oldPrivate;

							return res;
						}
						else if (_scriptObjectType == SBehaviourClass) {
							var obj:IHScriptCustomBehaviour = cast scriptObject;
							return obj.hset(id, v);
						}

						if (instanceHasField) {
							if(isBypassAccessor) {
								UnsafeReflect.setField(scriptObject, id, v);
								return v;
							} else {
								UnsafeReflect.setProperty(scriptObject, id, v);
								return UnsafeReflect.field(scriptObject, id);
							}
						} else if (__instanceFields.contains('set_$id')) { // setter
							return UnsafeReflect.getProperty(scriptObject, 'set_$id')(v);
						} else {
							setVar(id, v);
						}
					} else {
						setVar(id, v);
					}
				} else {
					l.r = v;
					if (l.depth == 0) {
						setVar(id, v);
					}
				}
				// TODO
			case EField(e, f, s):
				if(_inCustomClass) {
					switch (Tools.expr(e)) {
						case EIdent(id0):
							if (id0 == "this") {
								if(_proxy.superClass == null && _proxy.__class.classDecl.extend != null && !_proxy.hasVar(f)){
									// Caches the declaration to set it once superClass is created
									var v = expr(e2);
									_proxy.cacheSuperField(f, v);
									return v;
								}
								else {
									var oldPrivate = _proxy.__allowPrivateAccess;
									try {
										var v = expr(e2);
										_proxy.__allowPrivateAccess = true;
										_proxy.hset(f, v);
										_proxy.__allowPrivateAccess = oldPrivate;
										return v;
									}
									catch(e){
										_proxy.__allowPrivateAccess = oldPrivate;
									}
								}
							}
						default:
							// Do nothing
					}
				}
				// Fallback, which calls set()
				var obj = expr(e);
				if(s && obj == null) return null;
				v = set(obj, f, v);
			case EArray(e, index):
				var arr:Dynamic = expr(e);
				var index:Dynamic = expr(index);
				if (isMap(arr)) {
					setMapValue(arr, index, v);
				} else {
					arr[index] = v;
				}

			default:
				error(EInvalidOp("="));
		}
		return v;
	}

	function assignOp(op:String, fop:Dynamic->Dynamic->Dynamic):Void {
		var me = this;
		binops.set(op, function(e1, e2) return me.evalAssignOp(op, fop, e1, e2));
	}

	function evalAssignOp(op:String, fop:Dynamic->Dynamic->Dynamic, e1:Expr, e2:Expr):Dynamic {
		var v;
		switch (Tools.expr(e1)) {
			case EIdent(id):
				v = fop(expr(e1), expr(e2));
				// Make sure setting superclass/static fields directly works.
				// Also ensures property functions are accounted for.
				if(_inCustomClass) {
					if (_proxy.__class.hasField(id)) {
						var oldPrivate = _proxy.__class.__allowPrivateAccess;
						_proxy.__class.__allowPrivateAccess = true;
						_proxy.__class.hset(id, v);
						_proxy.__class.__allowPrivateAccess = oldPrivate;
						return v;
					}
					/*
					else if (_proxy.superClass != null && _proxy.superHasField(id)) {
						Reflect.setProperty(_proxy.superClass, id, v);
						return v;
					}
					else if (_proxy.hasVar(id)) {
						_proxy.hset(id, v);
						return v;
					}
					*/
					else if ((_proxy.superClass == null && _proxy.__class.classDecl.extend != null && !_proxy.hasVar(id))) {
						_proxy.cacheSuperField(id, v);
						return v;
					}
					else {
						var oldPrivate = _proxy.__allowPrivateAccess;
						try {
							_proxy.__allowPrivateAccess = true;
							_proxy.hset(id, v); // superClass check already handled in Custom Class
							_proxy.__allowPrivateAccess = oldPrivate;
							return v;
						}
						catch(e) {
							_proxy.__allowPrivateAccess = oldPrivate;
						}
					}
				}
				var l = locals.get(id);
				if (l == null) {
					if(_hasScriptObject && !varExists(id)) {
						var instanceHasField = __instanceFields.contains(id);

						if (_scriptObjectType == SObject && instanceHasField) {
							UnsafeReflect.setField(scriptObject, id, v);
							return v;
						} 
						else if(_scriptObjectType == SAccessBehaviourObject) {
							var obj:IHScriptCustomAccessBehaviour = cast scriptObject;

							var oldAccessor = obj.__allowSetGet;
							var oldPrivate = obj.__allowPrivateAccess;

							if (isBypassAccessor)
								obj.__allowSetGet = false;
							if (isPrivateAccess)
								obj.__allowPrivateAccess = true;

							var res = obj.hset(id, v);

							obj.__allowSetGet = oldAccessor;
							obj.__allowPrivateAccess = oldPrivate;

							return res;
						}
						else if (_scriptObjectType == SBehaviourClass) {
							var obj:IHScriptCustomBehaviour = cast scriptObject;
							return obj.hset(id, v);
						}

						if (instanceHasField) {
							if(isBypassAccessor) {
								UnsafeReflect.setField(scriptObject, id, v);
								return v;
							} else {
								UnsafeReflect.setProperty(scriptObject, id, v);
								return UnsafeReflect.field(scriptObject, id);
							}
						} else if (__instanceFields.contains('set_$id')) { // setter
							return UnsafeReflect.getProperty(scriptObject, 'set_$id')(v);
						} else {
							setVar(id, v);
						}
					} else {
						setVar(id, v);
					}
				}
				else {
					var l = locals.get(id);
					l.r = v;
					if (l.depth == 0) {
						setVar(id, v);
					}
				}
			case EField(e, f, s):
				var obj = expr(e);
				if(s && obj == null) return null;

				if(_inCustomClass) {
					switch(Tools.expr(e)) {
						case EIdent(_id):
							if (_id == 'this') {
								if(_proxy.superClass == null && _proxy.__class.classDecl.extend != null && !_proxy.hasVar(f)){
									// Caches the declaration to set it once superClass is created
									v = fop(get(obj, f), expr(e2));
									_proxy.cacheSuperField(f, v);
									return v;
								}
								else {
									var oldPrivate = _proxy.__allowPrivateAccess;
									try {
										v = fop(get(obj, f), expr(e2));
										_proxy.__allowPrivateAccess = true;
										_proxy.hset(f, v); // superClass check already handled in Custom Class
										_proxy.__allowPrivateAccess = oldPrivate;
										return v;
									}
									catch(e) {
										_proxy.__allowPrivateAccess = oldPrivate;
									}
								}
							}
						default:
					}
				}
				v = fop(get(obj, f), expr(e2));
				v = set(obj, f, v);
			case EArray(e, index):
				var arr:Dynamic = expr(e);
				var index:Dynamic = expr(index);
				if (isMap(arr)) {
					var map = getMap(arr);

					v = fop(map.get(index), expr(e2));
					map.set(index, v);
				} else {
					v = fop(arr[index], expr(e2));
					arr[index] = v;
				}
			default:
				return error(EInvalidOp(op));
		}
		return v;
	}

	function increment(e:Expr, prefix:Bool, delta:Int):Dynamic {
		#if hscriptPos
		curExpr = e;
		var e = e.e;
		#end
		switch (e) {
			case EIdent(id):
				var l = locals.get(id);
				if(l != null) {
					var v:Dynamic = l.r;
					if (prefix) {
						v += delta;
						l.r = v;
					} else
						l.r = v + delta;
					return v;
				} else {
					var v:Dynamic = resolve(id);
					if (prefix) {
						v += delta;
						setVar(id, v);
					} else
						setVar(id, v + delta);
					return v;
				}
			case EField(e, f, s):
				var obj = expr(e);
				if(s && obj == null) return null;
				var v:Dynamic = get(obj, f);
				if (prefix) {
					v += delta;
					set(obj, f, v);
				} else
					set(obj, f, v + delta);
				return v;
			case EArray(e, index):
				var arr:Dynamic = expr(e);
				var index:Dynamic = expr(index);
				if (isMap(arr)) {
					var map = getMap(arr);

					var v = map.get(index);
					if (prefix) {
						v += delta;
						map.set(index, v);
					} else {
						map.set(index, v + delta);
					}
					return v;
				} else {
					var v = arr[index];
					if (prefix) {
						v += delta;
						arr[index] = v;
					} else
						arr[index] = v + delta;
					return v;
				}
			default:
				return error(EInvalidOp((delta > 0) ? "++" : "--"));
		}
	}

	public function execute(expr:Expr):Dynamic {
		depth = 0;
		locals = new Map();
		declared = [];
		return exprReturn(expr);
	}

	public var printCallStack:Bool = false;

	function exprReturn(e):Dynamic {
		try {
			try {
				return expr(e);
			} catch (e:Stop) {
				switch (e) {
					case SBreak:
						throw "Invalid break";
					case SContinue:
						throw "Invalid continue";
					case SReturn:
						var v = returnValue;
						returnValue = null;
						return v;
				}
			} catch(e) {
				if(printCallStack)
					error(ECustom('${e.toString()}\n${CallStack.toString(CallStack.exceptionStack(true))}'));
				else
					error(ECustom(e.toString()));
				return null;
			}
		} catch(e:Error) {
			if (errorHandler != null)
				errorHandler(e);
			else
				throw e;
			return null;
		} catch(e) {
			trace(e);
		}
		return null;
	}

	public function duplicate<T>(h:Map<String, T>) {
		var h2 = new Map();
		var keys = h.keys();
		var _hasNext = keys.hasNext;
		var _next = keys.next;
		while (_hasNext()) {
			var k = _next();
			h2.set(k, h.get(k));
		}
		return h2;
	}

	function restore(old:Int):Void {
		while (declared.length > old) {
			var d = declared.pop();
			locals.set(d.n, d.old);
		}
	}

	public inline function error(e:#if hscriptPos ErrorDef #else Error #end, rethrow = false):Dynamic {
		#if hscriptPos var e = new Error(e, curExpr.pmin, curExpr.pmax, curExpr.origin, curExpr.line); #end

		if (rethrow) {
			this.rethrow(e);
		} else {
			throw e;
		}
		return null;
	}

	inline function rethrow(e:Dynamic):Void {
		#if hl
		hl.Api.rethrow(e);
		#else
		throw e;
		#end
	}

	public function resolve(id:String, doException:Bool = true):Dynamic {
		if (id == null)
			return null;
		id = StringTools.trim(id);

		// Custom Class
		if (_inCustomClass) {
			_nextCallObject = null;
			if (id == "super") {
				if (_proxy.superClass == null) {
					return _proxy.superConstructor;
				} else {
					return _proxy.superClass;
				}
			} 
			else if (id == "this") 
				return _proxy;
		}

		if (locals.exists(id)) {
			var l = locals.get(id);
			if(l != null)
				return l.r;
		}

		if(variables.exists(id))
			return variables.get(id);
		if(publicVariables.exists(id))
			return publicVariables.get(id);
		if(staticVariables.exists(id))
			return staticVariables.get(id);
		if(customClassExist(id))
			return getCustomClass(id);

		// Custom Class
		if (_inCustomClass) {
			// Static access
			if (_proxy.__class.hasField(id))  {
				var oldPrivate = _proxy.__class.__allowPrivateAccess;
				_proxy.__class.__allowPrivateAccess = true;
				var r = _proxy.__class.hget(id);
				_proxy.__class.__allowPrivateAccess = oldPrivate;
				return r;
			}
			
			
			if (_proxy.hasVar(id))  {
				var oldPrivate = _proxy.__allowPrivateAccess;
				_proxy.__allowPrivateAccess = true;
				var r = _proxy.hget(id);
				_proxy.__allowPrivateAccess = oldPrivate;
				return r;
			}
			// We are calling a LOCAL function from the same module.
			if (_proxy.hasFunction(id)) {
				_nextCallObject = _proxy;
				return _proxy.hget(id);
			}
			if (_proxy.superHasField(id)) {
				_nextCallObject = _proxy.superClass;
				return Reflect.getProperty(_proxy.superClass, id);
			} else {
				var oldPrivate = _proxy.__allowPrivateAccess;
				try {
					_proxy.__allowPrivateAccess = true;
					var r = _proxy.hget(id);
					_nextCallObject = _proxy;
					_proxy.__allowPrivateAccess = oldPrivate;
					return r;
				} catch (e:Dynamic) {
					if(doException)
						error(EUnknownVariable(id));
					_proxy.__allowPrivateAccess = oldPrivate;
				}
			}
		}

		if (_hasScriptObject) {
			// search in object
			if (id == "this") {
				return scriptObject;
			}
			var instanceHasField = __instanceFields.contains(id);

			if (_scriptObjectType == SObject && instanceHasField) {
				return UnsafeReflect.field(scriptObject, id);
			}
			else if(_scriptObjectType == SAccessBehaviourObject) {
				var obj:IHScriptCustomAccessBehaviour = cast scriptObject;

				var oldAccessor = obj.__allowSetGet;
				var oldPrivate = obj.__allowPrivateAccess;

				if (isBypassAccessor)
					obj.__allowSetGet = false;
				if (isPrivateAccess)
					obj.__allowPrivateAccess = true;

				var res = obj.hget(id);

				obj.__allowSetGet = oldAccessor;
				obj.__allowPrivateAccess = oldPrivate;

				return res;
			} else if(_scriptObjectType == SBehaviourClass) {
				var obj:IHScriptCustomBehaviour = cast scriptObject;
				return obj.hget(id);
			}

			if (instanceHasField) {
				if(isBypassAccessor) {
					return UnsafeReflect.field(scriptObject, id);
				} else {
					return UnsafeReflect.getProperty(scriptObject, id);
				}
			} else if (__instanceFields.contains('get_$id')) { // getter
				return UnsafeReflect.getProperty(scriptObject, 'get_$id')();
			}
		}
		if (doException)
			error(EUnknownVariable(id));
		return null;
	}

	// backwards compatibility
	public static var importRedirects:Map<String, String> = new Map();
	public static function getImportRedirect(className:String):String {
		return importRedirects.exists(className) ? importRedirects.get(className) : className;
	}

	public var localImportRedirects:Map<String, String> = new Map();
	public function getLocalImportRedirect(className:String):String {
		var className = className;
		if (InterpConfig.IMPORT_REDIRECTS.exists(className))
			className = InterpConfig.IMPORT_REDIRECTS.get(className);
		if (importRedirects.exists(className))
			className = importRedirects.get(className);
		if (localImportRedirects.exists(className))
			className = localImportRedirects.get(className);
		return className;
	}

	// Workaround for parsing custom classes if made inside of a script file
	public var localImports:Map<String, CustomClassImport> = new Map();
	public var localParsedClasses:Array<String> = []; // Prevents duplicated classes
	public var newCustomClass:Bool = true; // Temporary

	public function expr(e:Expr):Dynamic {
		#if hscriptPos
		curExpr = e;
		var e = e.e;
		#end
		switch (e) {
			case EIgnore(_):
			case EClass(name, fields, extend, interfaces):
				inline function importVar(thing:String):String {
					if (thing == null)
						return null;
					final variable:Class<Any> = variables.exists(thing) ? cast variables.get(thing) : null;
					return variable == null ? thing : Type.getClassName(variable);
				}
			
				if (localParsedClasses.contains(name))
					error(EAlreadyExistingClass(name));

				var customClassFields:Array<FieldDecl> = [];
				for (f in fields) {
					switch (Tools.expr(f)) {
						case EFunction(args, e, name, ret, isPublic, isStatic, isOverride, isPrivate, isFinal, isInline):
							var fnAcc:Array<FieldAccess> = [];
							if (isPublic) fnAcc.push(APublic);
							if (isStatic) fnAcc.push(AStatic);
							if (isOverride) fnAcc.push(AOverride);

							var fnd:FunctionDecl = {
								args: args,
								body: e,
								ret: ret
							};
							var fd:FieldDecl = {
								name: name,
								meta: [],
								kind: KFunction(fnd),
								access: fnAcc
							};

							customClassFields.push(fd);
						case EVar(n, t, e, isPublic, isStatic, isPrivate, isFinal, isInline, getter, setter):
							var varAcc:Array<FieldAccess> = [];
							if (isPublic) varAcc.push(APublic);
							if (isStatic) varAcc.push(AStatic);

							var vrd:VarDecl = {
								get: getter,
								set: setter,
								expr: e,
								type: t,
								isFinal: isFinal
							};
							var fd:FieldDecl = {
								name: n,
								meta: [],
								kind: KVar(vrd),
								access: varAcc
							};

							customClassFields.push(fd);
						default:
					}
				}

				var extendPath:Null<CType> = extend != null ? CTPath(importVar(extend).split(".")) : null;
				var interfacesPaths:Array<CType> = [for (i in interfaces) CTPath(importVar(i).split("."))];

				var classDecl:ClassDecl = {
					name: name,
					params: {}, // TODO: make it parse and ignore it
					meta: [],
					isPrivate: false,
					extend: extendPath,
					implement: interfacesPaths,
					fields: customClassFields,
					isExtern: false,
				};

				var customClassDecl:CustomClassDecl = {
					classDecl: classDecl,
					imports: localImports, // TODO: better way to reuse imported classes 
					usings: [for(u in this.usings) u.name],
					pkg: null,
					ogInterp: this,
					isInline: true
				};

				registerCustomClass(customClassDecl, null);
				localParsedClasses.push(customClassDecl.classDecl.name);
			case EImport(c, n):
				if (!importEnabled)
					return null;
				var splitClassName = [for (e in c.split(".")) e.trim()];
				var realClassName = splitClassName.join(".");
				var claVarName = splitClassName[splitClassName.length - 1];
				var toSetName = n != null ? n : claVarName;
				var oldClassName = realClassName;
				var oldSplitName = splitClassName.copy();

				var customImport:CustomClassImport = {
					name: claVarName,
					pkg: splitClassName,
					fullPath: realClassName
				};
				localImports.set(customImport.name, customImport);

				if (variables.exists(toSetName)) // class is already imported
					return null;

				var realClassName = getLocalImportRedirect(realClassName);

				if (importBlocklist.contains(realClassName))
					return null;
				if (InterpConfig.DISALLOW_IMPORT.contains(realClassName))
					return null;
				var cl = Type.resolveClass(realClassName);
				if (cl == null)
					cl = Type.resolveClass('${realClassName}_HSC');

				var en = Type.resolveEnum(realClassName);

				//trace(realClassName, cl, en, splitClassName);

				// Allow for flixel.ui.FlxBar.FlxBarFillDirection;
				if (cl == null && en == null) {
					if(splitClassName.length > 1) {
						splitClassName.splice(-2, 1); // Remove the last last item
						realClassName = splitClassName.join(".");

						var realClassName = getLocalImportRedirect(realClassName);

						if (importBlocklist.contains(realClassName))
							return null;

						cl = Type.resolveClass(realClassName);
						if (cl == null)
							cl = Type.resolveClass('${realClassName}_HSC');

						en = Type.resolveEnum(realClassName);

						//trace(realClassName, cl, en, splitClassName);
					}
				}

				if (cl == null && en == null) {
					if (importFailedCallback == null || !importFailedCallback(oldSplitName, n))
						error(EInvalidClass(oldClassName));
				} else {
					if (en != null) {
						// ENUM!!!!
						var enumThingy = {};
						for (c in en.getConstructors()) {
							try {
								UnsafeReflect.setField(enumThingy, c, en.createByName(c));
							} catch(e) {
								try {
									UnsafeReflect.setField(enumThingy, c, UnsafeReflect.field(en, c));
								} catch(ex) {
									throw e;
								}
							}
						}
						variables.set(toSetName, enumThingy);
					} else {
						variables.set(toSetName, cl);
					}
				}

				return null;
			case ERedirect(n, cln, cl):
				if(cl != null) {
					setVar(n, cl);
				}
				localImportRedirects.set(n, cln);
			case EConst(c):
				switch (c) {
					case CInt(v): return v;
					case CFloat(f): return f;
					case CString(s): return s;
				}
			case EIdent(id):
				return resolve(id);
			case EVar(n, _, e, isPublic, isStatic):
				declared.push({n: n, old: locals.get(n), depth: depth});
				locals.set(n, {r: (e == null) ? null : expr(e), depth: depth});
				if (depth == 0) {
					if(allowStaticVariables && isStatic == true) {
						if(!staticVariables.exists(n)) // make it so it only sets it once
							staticVariables.set(n, locals[n].r);
					} else if(allowPublicVariables && isPublic == true) {
						publicVariables.set(n, locals[n].r);
					} else {
						variables.set(n, locals[n].r);
					}
				}
				return null;
			case EParent(e):
				return expr(e);
			case EBlock(exprs):
				var old = declared.length;
				var v = null;
				for (e in exprs)
					v = expr(e);
				restore(old);
				return v;
			case EField(e, f, s):
				var field = expr(e);
				if(s && field == null)
					return null;
				return get(field, f);
			case EBinop(op, e1, e2):
				var fop = binops.get(op);
				if (fop == null)
					error(EInvalidOp(op));
				return fop(e1, e2);
			case EUnop(op, prefix, e):
				switch (op) {
					case "!":
						return expr(e) != true;
					case "-":
						return -expr(e);
					case "++":
						return increment(e, prefix, 1);
					case "--":
						return increment(e, prefix, -1);
					case "~":
						return ~expr(e);
					default:
						error(EInvalidOp(op));
				}
			case ECall(e, params):
				switch (Tools.expr(e)) {
					case EField(e, f, s):
						var obj:Dynamic = expr(e);
						if (obj == null) {
							if(s) return null;
							error(EInvalidAccess(f));
						}

						if (f == "bind" && Reflect.isFunction(obj)) {
							var obj: Function = obj;
							if (params.length == 0) { // Special case for function.bind()
								return Reflect.makeVarArgs(function(ar: Array<Dynamic>) {
									return obj();
								});
							}

							// bind(_, false) => function(a1) return obj(a1, false);
							// bind(false, _) => function(a2) return obj(false, a2);
							// bind(_, _) => function(a1, a2) return obj(a1, a2);

							var totalNeeded = 0;
							var bArgs = [];
							for (p in params) {
								switch (Tools.expr(p)) {
									case EIdent(_):
										bArgs.push(null);
										totalNeeded++;
									default:
										bArgs.push(p);
								}
							}
							var me = this;
							// TODO: make it increment the depth?
							return Reflect.makeVarArgs(function(ar: Array<Dynamic>) {
								if (ar.length < totalNeeded)
									error(ECustom("Too few arguments")); // TODO: make it say like "Not enough arguments, expected a:Int"
								var i = 0;
								var actualArgs = [];//[for (a in bArgs) if (a != null) me.expr(a) else ar[i++]];
								for(a in bArgs) {
									if(a != null) {
										switch(Tools.expr(a)) {
											case EIdent(id0):
												var ident = resolve(id0);
												if (ident is CustomClass) {
													// Pass the underlying superclass if exist
													var customClass:CustomClass = cast ident;
													var objectToPush = customClass.superClass != null ? customClass.getSuperclass() : customClass;
													actualArgs.push(objectToPush);
												} else {
													actualArgs.push(ident);
												}
											default:
												actualArgs.push(me.expr(a));
										}
									}
									else 
										actualArgs.push(ar[i++]);
								}
								return Reflect.callMethod(null, obj, actualArgs);
							});
						}
						
						return fcall(obj, f, makeArgs(params));
					default:
						return call(null, expr(e), makeArgs(params));
				}
			case EIf(econd, e1, e2):
				return if (expr(econd) == true) expr(e1) else if (e2 == null) null else expr(e2);
			case EWhile(econd, e):
				whileLoop(econd, e);
				return null;
			case EDoWhile(econd, e):
				doWhileLoop(econd, e);
				return null;
			case EFor(v, it, e, ithv):
				forLoop(v, it, e, ithv);
				return null;
			case EBreak:
				throw SBreak;
			case EContinue:
				throw SContinue;
			case EReturn(e):
				returnValue = e == null ? null : expr(e);
				throw SReturn;
			case EFunction(params, fexpr, name, _, isPublic, isStatic, isOverride, isPrivate, isFinal, isInline):
				var __capturedLocals = duplicate(locals);
				var capturedLocals:Map<String, DeclaredVar> = [];

				var keys = __capturedLocals.keys();
				var _hasNext = keys.hasNext;
				var _next = keys.next;
				while (_hasNext()) {
					var k = _next();
					var e = __capturedLocals.get(k);
					if (e != null && e.depth > 0)
						capturedLocals.set(k, e);
				}

				var me = this;
				var hasOpt = false, minParams = 0;
				for (p in params)
					if (p.opt)
						hasOpt = true;
					else
						minParams++;
				var f = function(args:Array<Dynamic>) {
					if (me.locals == null || me.variables == null) return null;

					if (((args == null) ? 0 : args.length) != params.length) {
						if (args.length < minParams) {
							var str = "Invalid number of parameters. Got " + args.length + ", required " + minParams;
							if (name != null)
								str += " for function '" + name + "'";
							error(ECustom(str));
						}
						// make sure mandatory args are forced
						var args2 = [];
						var extraParams = args.length - minParams;
						var pos = 0;
						for (p in params)
							if (p.opt) {
								if (extraParams > 0) {
									args2.push(args[pos++]);
									extraParams--;
								} else
									args2.push(null);
							} else
								args2.push(args[pos++]);
						args = args2;
					}
					var old = me.locals, depth = me.depth;
					me.depth++;
					me.locals = me.duplicate(capturedLocals);
					for (i in 0...params.length)
						me.locals.set(params[i].name, {r: args[i], depth: depth});
					var r = null;
					var oldDecl = declared.length;
					if (inTry)
						try {
							r = me.exprReturn(fexpr);
						} catch (e:Dynamic) {
							me.locals = old;
							me.depth = depth;
							#if neko
							neko.Lib.rethrow(e);
							#else
							throw e;
							#end
						}
					else
						r = me.exprReturn(fexpr);
					restore(oldDecl);
					me.locals = old;
					me.depth = depth;
					return r;
				};
				var fn:Function = Reflect.makeVarArgs(f);
				if (name != null) {
					if (depth == 0) {
						// global function
						if(isStatic && allowStaticVariables) {
							staticVariables.set(name, fn);
						} else if(isPublic && allowPublicVariables) {
							publicVariables.set(name, fn);
						} else {
							variables.set(name, fn);
						}
					} else {
						// function-in-function is a local function
						declared.push({n: name, old: locals.get(name), depth: depth});
						var ref:DeclaredVar = {r: fn, depth: depth};
						locals.set(name, ref);
						capturedLocals.set(name, ref); // allow self-recursion
					}
				}
				return fn;
			case EArrayDecl(arr, wantedType):
				var isMap = false;

				if (wantedType != null) {
					isMap = switch (wantedType) {
						case CTPath(["Map"], [_, _]): true;
						case CTPath(["StringMap"], [_]): true;
						case CTPath(["IntMap"], [_]): true;
						case CTPath(["ObjectMap"], [_]): true;
						case CTPath(["EnumMap"], [_]): true;
						default: false;
					};
				}

				if (!isMap && arr.length > 0) {
					isMap = Tools.expr(arr[0]).match(EBinop("=>", _));
				}

				if (isMap) {
					var isAllString:Bool = true;
					var isAllInt:Bool = true;
					var isAllObject:Bool = true;
					var isAllEnum:Bool = true;
					var keys:Array<Dynamic> = [];
					var values:Array<Dynamic> = [];

					for (e in arr) {
						switch (Tools.expr(e)) {
							case EBinop("=>", eKey, eValue):
								var key:Dynamic = expr(eKey);
								var value:Dynamic = expr(eValue);
								isAllString = isAllString && (key is String);
								isAllInt = isAllInt && (key is Int);
								isAllObject = isAllObject && Reflect.isObject(key);
								isAllEnum = isAllEnum && Reflect.isEnumValue(key);
								keys.push(key);
								values.push(value);
							default:
								throw "=> expected";
						}
					}

					if (wantedType != null) {
						isAllString = isAllString && (
							wantedType.match(CTPath(["Map"], [CTPath(["String"], _), _])) || wantedType.match(CTPath(["StringMap"], [_]))
						);
						isAllInt = isAllInt && (
							wantedType.match(CTPath(["Map"], [CTPath(["Int"], _), _])) || wantedType.match(CTPath(["IntMap"], [_]))
						);
						isAllObject = isAllObject && (
							wantedType.match(CTPath(["Map"], [CTPath(["Dynamic"], _), _])) || wantedType.match(CTPath(["ObjectMap"], [_, _]))
						);
						isAllEnum = isAllEnum && (
							wantedType.match(CTPath(["Map"], [CTPath(["Enum"], _), _])) || wantedType.match(CTPath(["EnumMap"], [_, _]))
						);

						if (!isAllString && !isAllInt && !isAllObject && !isAllEnum) {
							isAllObject = true; // Assume dynamic
							//throw "Unknown Type Key";
						}
					}

					var map:Dynamic = {
						if (isAllInt)
							new haxe.ds.IntMap<Dynamic>();
						else if (isAllString)
							new haxe.ds.StringMap<Dynamic>();
						else if (isAllEnum)
							new haxe.ds.EnumValueMap<Dynamic, Dynamic>();
						else if (isAllObject)
							new haxe.ds.ObjectMap<Dynamic, Dynamic>();
						else
							throw 'Unknown Type Key';
					}
					for (n in 0...keys.length) {
						setMapValue(map, keys[n], values[n]);
					}
					return map;
				} else {
					var a = [];
					for (e in arr) {
						a.push(expr(e));
					}
					return a;
				}
			case EArray(e, index):
				var arr:Dynamic = expr(e);
				var index:Dynamic = expr(index);
				if (isMap(arr)) {
					return getMapValue(arr, index);
				} else {
					return arr[index];
				}
			case ENew(cl, params):
				return cnew(cl, makeArgs(params));
			case EThrow(e):
				throw expr(e);
			case ETry(e, n, _, ecatch):
				var old = declared.length;
				var oldTry = inTry;
				try {
					inTry = true;
					var v:Dynamic = expr(e);
					restore(old);
					inTry = oldTry;
					return v;
				} catch (err:Stop) {
					inTry = oldTry;
					throw err;
				} catch (err:Dynamic) {
					// restore vars
					restore(old);
					inTry = oldTry;
					// declare 'v'
					declared.push({n: n, old: locals.get(n), depth: depth});
					locals.set(n, {r: err, depth: depth});
					var v:Dynamic = expr(ecatch);
					restore(old);
					return v;
				}
			case EObject(fl):
				var o = {};
				for (f in fl)
					UnsafeReflect.setField(o, f.name, expr(f.e));
				return o;
			case ETernary(econd, e1, e2):
				return if (expr(econd) == true) expr(e1) else expr(e2);
			case ESwitch(e, cases, def):
				var val:Dynamic = expr(e);
				var match = false;
				for (c in cases) {
					for (v in c.values)
						if (expr(v) == val) {
							match = true;
							break;
						}
					if (match) {
						val = expr(c.expr);
						break;
					}
				}
				if (!match)
					val = def == null ? null : expr(def);
				return val;
			case EMeta(a, b, e):
				var val:Dynamic = null;
				switch(a) {
					case ":bypassAccessor":
						var oldAccessor = isBypassAccessor;
						isBypassAccessor = true;
						val = expr(e);
						isBypassAccessor = oldAccessor;
						return val;
					case ":privateAccess":
						var oldPrivate = isPrivateAccess;
						isPrivateAccess = true;
						val = expr(e);
						isPrivateAccess = oldPrivate;
						return val;
				}
				/*
				var oldAccessor = isBypassAccessor;
				if(a == ":bypassAccessor") {
					isBypassAccessor = true;
				}
				var val = expr(e);

				isBypassAccessor = oldAccessor;
				return val;
				*/
				return val;
			case ECheckType(e, _):
				return expr(e);
			case EUsing(name):
				useUsing(name);
			case EEnum(enumName, fields):
				var obj:HScriptEnum = new HScriptEnum();
				for (index => field in fields) {
					switch (field) {
						case ESimple(name):
							obj.setEnum(name, new EnumValue(enumName, name, index, obj, null));
						case EConstructor(name, params):
							var hasOpt = false, minParams = 0;
							for (p in params)
								if (p.opt)
									hasOpt = true;
								else
									minParams++;
							var f = function(args: Array<Dynamic>) {
								if (((args == null) ? 0 : args.length) != params.length) {
									if (args.length < minParams) {
										var str = "Invalid number of parameters. Got " + args.length + ", required " + minParams;
										if (enumName != null)
											str += " for enum '" + enumName + "'";
										error(ECustom(str));
									}
									// make sure mandatory args are forced
									var args2 = [];
									var extraParams = args.length - minParams;
									var pos = 0;
									for (p in params)
										if (p.opt) {
											if (extraParams > 0) {
												args2.push(args[pos++]);
												extraParams--;
											} else
												args2.push(null);
										} else
											args2.push(args[pos++]);
									args = args2;
								}
								return new Tools.EnumValue(enumName, name, index, obj, args);
							};
							var f = Reflect.makeVarArgs(f);

							obj.setEnum(name, f);
					}
				}
				variables.set(enumName, obj);
		}
		return null;
	}

	function doWhileLoop(econd:Expr, e:Expr):Void {
		var old = declared.length;
		do {
			try {
				expr(e);
			} catch (err:Stop) {
				switch (err) {
					case SContinue:
					case SBreak:
						break;
					case SReturn:
						throw err;
				}
			}
		} while (expr(econd) == true);
		restore(old);
	}

	function whileLoop(econd:Expr, e:Expr):Void {
		var old = declared.length;
		while (expr(econd) == true) {
			try {
				expr(e);
			} catch (err:Stop) {
				switch (err) {
					case SContinue:
					case SBreak:
						break;
					case SReturn:
						throw err;
				}
			}
		}
		restore(old);
	}

	function makeIterator(v:Dynamic, ?allowKeyValue = false):Iterator<Dynamic> {
		#if ((flash && !flash9) || (php && !php7 && haxe_ver < '4.0.0'))
		if (v.iterator != null)
			v = v.iterator();
		#else
		if(allowKeyValue) {
			try
				v = v.keyValueIterator()
			catch (e:Dynamic) {};
		}

		if(v.hasNext == null || v.next == null) {
			try
				v = v.iterator()
			catch (e:Dynamic) {};
		}
		#end
		if (v.hasNext == null || v.next == null)
			error(EInvalidIterator(v));
		return v;
	}

	function makeArgs(params:Array<Expr>):Array<Dynamic> {
		var args:Array<Dynamic> = [];
		for (p in params) {
			switch (Tools.expr(p)) {
				case EIdent(id):
					var ident = resolve(id);
					if (ident is CustomClass) {
						var customClass:CustomClass = cast ident; // Pass the underlying superclass if exist
						args.push(customClass.superClass != null ? customClass.getSuperclass() : customClass);
					} else {
						args.push(ident);
					}
				default:
					args.push(expr(p));
			}
		}

		return args;
	}

	function forLoop(n:String, it:Expr, e:Expr, ?ithv:String):Void {
		var isKeyValue = ithv != null;
		var old = declared.length;
		if(isKeyValue)
			declared.push({n: ithv, old: locals.get(ithv), depth: depth});
		declared.push({n: n, old: locals.get(n), depth: depth});
		var it = makeIterator(expr(it), isKeyValue);
		var _hasNext = it.hasNext;
		var _next = it.next;
		while (_hasNext()) {
			var next = _next();
			if(isKeyValue)
				locals.set(ithv, {r: next.key, depth: depth});
			locals.set(n, {r: isKeyValue ? next.value : next, depth: depth});
			try {
				expr(e);
			} catch (err:Stop) {
				switch (err) {
					case SContinue:
					case SBreak:
						break;
					case SReturn:
						throw err;
				}
			}
		}
		restore(old);
	}

	inline function isMap(o:Dynamic):Bool {
		return (o is IMap);
	}

	inline function getMap(map:Dynamic):IMap<Dynamic, Dynamic> {
		var map:IMap<Dynamic, Dynamic> = cast map;
		return map;
	}

	inline function getMapValue(map:Dynamic, key:Dynamic):Dynamic {
		var map:IMap<Dynamic, Dynamic> = cast map;
		return map.get(key);
	}

	inline function setMapValue(map:Dynamic, key:Dynamic, value:Dynamic):Void {
		var map:IMap<Dynamic, Dynamic> = cast map;
		map.set(key, value);
	}

	public static var getRedirects:Map<String, Dynamic->String->Dynamic> = [];
	public static var setRedirects:Map<String, Dynamic->String->Dynamic->Dynamic> = [];

	private static var _getRedirect:Dynamic->String->Dynamic;
	private static var _setRedirect:Dynamic->String->Dynamic->Dynamic;

	public var useRedirects:Bool = false;

	static function getClassType(o:Dynamic, ?cls:Class<Any>):Null<String> {
		return switch (Type.typeof(o)) {
			case TNull: "Null";
			case TInt: "Int";
			case TFloat: "Float";
			case TBool: "Bool";
			case _:
				if (cls == null)
					cls = Type.getClass(o);
				cls != null ? Type.getClassName(cls) : null;
		};
	}

	function get(o:Dynamic, f:String):Dynamic {
		if (o == null)
			error(EInvalidAccess(f));

		if (o is CustomClass) { 
			if (cast(o, CustomClass).__class.hasField(f)) {
				var clsName:String = cast(o, CustomClass).className;
				error(ECustom('The field ${clsName}.${f} should be accessed in a static way.'));
			}
		}

		var cls = Type.getClass(o);
		if (useRedirects && {
			var cl:Null<String> = getClassType(o, cls);
			cl != null && getRedirects.exists(cl) && (_getRedirect = getRedirects[cl]) != null;
		}) {
			return _getRedirect(o, f);
		}
		if (o is IHScriptCustomAccessBehaviour) {
			var obj:IHScriptCustomAccessBehaviour = cast o;

			var oldAccessor = obj.__allowSetGet;
			var oldPrivate = obj.__allowPrivateAccess;

			if(isBypassAccessor)
				obj.__allowSetGet = false;
			if(isPrivateAccess)
				obj.__allowPrivateAccess = true;

			var res = obj.hget(f);

			obj.__allowSetGet = oldAccessor;
			obj.__allowPrivateAccess = oldPrivate;
			
			return res;
		}

		if (o is IHScriptCustomBehaviour) {
			var obj:IHScriptCustomBehaviour = cast o;
			return obj.hget(f);
		}
		var v = null;
		if(isBypassAccessor) {
			if ((v = UnsafeReflect.field(o, f)) == null)
				v = Reflect.field(cls, f);
		}

		if(v == null) {
			if ((v = UnsafeReflect.getProperty(o, f)) == null)
				v = Reflect.getProperty(cls, f);
		}
		return v;
	}

	function set(o:Dynamic, f:String, v:Dynamic):Dynamic {
		if (o == null)
			error(EInvalidAccess(f));

		if (o is CustomClass) { 
			if (cast(o, CustomClass).__class.hasField(f)) {
				var clsName:String = cast(o, CustomClass).className;
				error(ECustom('The field ${clsName}.${f} should be accessed in a static way.'));
			}
		}

		if (useRedirects && {
			var cl:Null<String> = getClassType(o);
			cl != null && setRedirects.exists(cl) && (_setRedirect = setRedirects[cl]) != null;
		})
			return _setRedirect(o, f, v);
		if (o is IHScriptCustomAccessBehaviour) {
			var obj:IHScriptCustomAccessBehaviour = cast o;
			if(isBypassAccessor) {
				obj.__allowSetGet = false;
				var res = obj.hset(f, v);
				obj.__allowSetGet = true;
				return res;
			}
			return obj.hset(f, v);
		}

		if (o is IHScriptCustomBehaviour) {
			var obj:IHScriptCustomBehaviour = cast o;
			return obj.hset(f, v);
		}
		// Can use unsafe reflect here, since we checked for null above
		if(isBypassAccessor) {
			UnsafeReflect.setField(o, f, v);
		} else {
			UnsafeReflect.setProperty(o, f, v);
		}
		return v;
	}

	/**
	 * Meant for people to add their own usings.
	**/
	function registerUsingLocal(name: String, call: UsingCall): UsingEntry {
		var entry = new UsingEntry(name, call);
		usings.push(entry);
		return entry;
	}

	function useUsing(name:String) {
		for (us in UsingHandler.usingEntries) {
			if (us.name == name) {
				if (usings.indexOf(us) == -1)
					usings.push(us);
				return;
			}
		}

		var cls = Tools.getClass(name);
		if (cls != null) {
			var entry:UsingEntry = null;

			var fieldName = '_HX_USING__' + StringTools.replace(name, ".", "_");
			if (Reflect.hasField(cls, fieldName)) {
				var fields = Reflect.field(cls, fieldName);
				if (fields == null)
					return;

				entry = new UsingEntry(name, function(o:Dynamic, f:String, args:Array<Dynamic>):Dynamic {
					if (!fields.exists(f))
						return null;
					var type:ValueType = Type.typeof(o);
					var valueType:ValueType = fields.get(f);

					// If we figure out a better way to get the types as the real ValueType, we can use this instead
					// if (Type.enumEq(valueType, type))
					//	return Reflect.callMethod(cls, Reflect.field(cls, f), [o].concat(args));

					var canCall = valueType == null ? true : switch (valueType) {
						case TEnum(null):
							type.match(TEnum(_));
						case TClass(null):
							type.match(TClass(_));
						case TClass(IMap): // if we don't check maps like this, it just doesn't work
							type.match(TClass(IMap) | TClass(haxe.ds.ObjectMap) | TClass(haxe.ds.StringMap) | TClass(haxe.ds.IntMap) | TClass(haxe.ds.EnumValueMap));
						default:
							Type.enumEq(type, valueType);
					}

					return canCall ? Reflect.callMethod(cls, Reflect.field(cls, f), [o].concat(args)) : null;
				});

				#if debug
				trace("Registered macro based using entry for " + name);
				#end

				UsingHandler.usingEntries.push(entry);
				usings.push(entry);
				return;
			}
			else {
				// Use reflection to generate the using entry
				entry = new UsingEntry(name, function(o:Dynamic, f:String, args:Array<Dynamic>):Dynamic {
					if (!Reflect.hasField(cls, f))
						return null;
					var field = Reflect.field(cls, f);
					if (!Reflect.isFunction(field))
						return null;

					// invalid if the function has no arguments
					var totalArgs = Tools.argCount(field);
					if (totalArgs == 0)
						return null;

					return Reflect.callMethod(cls, field, [o].concat(args));
				});

				#if debug
				trace("Registered reflection based using entry for " + name);
				#end
			}
			
			UsingHandler.usingEntries.push(entry);
			usings.push(entry);
			return;
		}
		error(ECustom("Unknown using class " + name));
	}

	/**
	 * List of components that allow using static methods on objects.
	 * This only works if you do
	 * ```haxe
	 * var result = "Hello ".trim();
	 * ```
	 * and not
	 * ```haxe
	 * var trim = "Hello ".trim;
	 * var result = trim();
	 * ```
	 */
	var usings: Array<UsingEntry> = [];

	function fcall(o:Dynamic, f:String, args:Array<Dynamic>):Dynamic {
		for(_us in usings) {
			var v = _us.call(o, f, args);
			if(v != null)
				return v;
		}

		// Custom logic to handle super calls to prevent infinite recursion
		if(_inCustomClass) {
			// Force call super function.
			if(o == _proxy.superClass) {
				if(_proxy.superIsCustomClass)
					cast(_proxy.superClass, CustomClass).callFunction(f, args);
				else
					return call(o, Reflect.field(_proxy.superClass, '_HX_SUPER__${f}'), args);
			}	
		}
		else if (o is CustomClass) {
			_nextCallObject = null;
			var proxy:CustomClass = cast o;
			return proxy.callFunction(f, args);
		}
		else if (o is CustomClassDecl) {
			// Static function call
			var staticClass:CustomClassDecl = cast o;
			if(staticClass.hasFunction(f))
				return staticClass.callFunction(f, args);
		}

		var func = get(o, f);

		// Workaround for an HTML5-specific issue.
		// https://github.com/HaxeFoundation/haxe/issues/11298
		#if js
		if (func == null && f == "contains") {
			func = get(o, "includes");
		}
		#end

		return call(o, func, args);
	}

	function call(o:Dynamic, f:Dynamic, args:Array<Dynamic>):Dynamic {
		if (_inCustomClass) {
			if (o == null && _nextCallObject != null) {
				o = _nextCallObject;
			}
			if (f == null) {
				error(EInvalidAccess(f));
			}
			if (o == _proxy) {
				// If we are calling this.fn(), special handling is needed to prevent the local scope from being destroyed.
				// By checking `o == _proxy`, we handle BOTH fn() and this.fn().
				// super.fn() is exempt since it is not scripted.
				return callThis(f, args);
			}
			try {
				var r = Reflect.callMethod(o, f, args);
				_nextCallObject = null;
				return r;
			} catch (e) {
				error(ECustom('${_proxy.className} threw an exception: \n${e.message}'));
				_nextCallObject = null;
				return null;
			}
		}

		return UnsafeReflect.callMethodSafe(o, f, args);
	}

	/**
	 * Call a given function on the current proxy with the given arguments.
	 * Ensures that the local scope is not destroyed.
	 * @param fun The function to call.
	 * @param args The arguments to apply to that function.
	 * @return The result of the function call.
	 */
	function callThis(fun:Dynamic, args:Array<Dynamic>):Dynamic {
		// If we are calling this.fn(), special handling is needed to prevent the local scope from being destroyed.
		// Store the local scope.
		var capturedLocals = this.duplicate(locals);
		var capturedDeclared = this.declared;
		var capturedDepth = this.depth;

		this.depth++;

		// Call the function.
		try {
			var result = Reflect.callMethod(_proxy, fun, args);

			// Restore the local scope.
			this.locals = capturedLocals;
			this.declared = capturedDeclared;
			this.depth = capturedDepth;

			return result;
		} catch (e) {
			error(ECustom('Custom Class threw an exception: \n${fun}'));

			// Restore the local scope.
			this.locals = capturedLocals;
			this.declared = capturedDeclared;
			this.depth = capturedDepth;

			return null;
		}
	}

	function cnew(cl:String, args:Array<Dynamic>):Dynamic {
		// Custom Class
		if (customClassExist(cl)) {
			var proxy:CustomClass = new CustomClass(getCustomClass(cl), args, null, this);
			return proxy;
		}
		if (_inCustomClass) {
			if (_proxy.__class.pkg != null) {
				var packagedClass = _proxy.__class.pkg.join(".") + "." + cl;
				if (customClassExist(packagedClass)) {
					var proxy:CustomClass = new CustomClass(getCustomClass(cl), args, null, this);
					return proxy;
				}
			}

			if (_proxy.__class.imports != null && _proxy.__class.imports.exists(cl)) {
				var importedClass = _proxy.__class.imports.get(cl).fullPath;
				if (customClassExist(importedClass)) {
					var proxy:CustomClass = new CustomClass(getCustomClass(cl), args, null, this);
					return proxy;
				}

				var c = Type.resolveClass(importedClass);
				if (c != null) {
					return Type.createInstance(c, args);
				}
			}
		}

		var c:Dynamic = resolve(cl);
		if (c == null)
			c = Type.resolveClass(cl);
		if(c is IHScriptCustomConstructor) {
			var c:IHScriptCustomConstructor = cast c;
			return c.hnew(args);
		} else {
			return Type.createInstance(c, args);
		}
	}

	public function registerModule(module:Array<ModuleDecl>, ?as:String) {
		var pkg:Array<String> = null;
		var imports:Map<String, CustomClassImport> = [];
		var usings:Array<String> = [];
		var regAlias:Bool = false;
		for (decl in module) {
			switch (decl) {
				case DPackage(path):
					pkg = path;
				case DImport(path, _, asname):
					if (importBlocklist.contains(path.join(".")))
						continue;
					var last = path[path.length - 1];
					var hasAlias = asname != null;

					var importedClass:CustomClassImport = {
						name: last,
						pkg: [for (e in path) e.trim()],
						fullPath: path.join("."),
						as: asname
					}
					imports.set(hasAlias ? asname : importedClass.name, importedClass);
				case DUsing(path): 
					usings.push(path.join("."));
				case DTypedef(td):
					switch(td.t) {
						case CTPath(path, params):
							if (params != null && params.length > 1)
								error(ECustom("Typedefs can't have parameters"));
							if (path.length < 1)
								error(ECustom("Typedefs can't be empty"));

							var last = path[path.length - 1];

							var importedClass:CustomClassImport = {
								name: last,
								pkg: [for (e in path) e.trim()],
								fullPath: path.join("."),
								as: td.name
							}
							imports.set(td.name, importedClass);
						default:
					}
				case DClass(c):
					var extend = c.extend;
					if (extend != null) {
						var superClassPath = new Printer().typeToString(extend);
						if (imports.exists(superClassPath)) {
							switch (extend) {
								case CTPath(_, params):
									extend = CTPath(imports.get(superClassPath).pkg, params);
								case _:
							}
						}
					}
					var classDecl:ClassDecl = {
						name: c.name,
						params: c.params,
						meta: c.meta,
						isPrivate: c.isPrivate,
						extend: extend,
						implement: c.implement,
						fields: c.fields,
						isExtern: c.isExtern
					};

					var customClassDecl:CustomClassDecl = {
						classDecl: classDecl,
						imports: imports,
						usings: usings,
						pkg: pkg,
						ogInterp: this
					}
					//customClassDecl.cacheFields();
					registerCustomClass(customClassDecl, !regAlias ? as : null, _inCustomClass);
					if(as != null) regAlias = true;
			}
		}
	}
}
