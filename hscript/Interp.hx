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

import hscript.HEnum.HEnumValue;
import haxe.CallStack;
import hscript.utils.UsingHandler;
import hscript.utils.UnsafeReflect;
import haxe.PosInfos;
import hscript.Expr;
import haxe.Constraints.IMap;

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
	var SCustomClass; // custom classes
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

@:access(hscript.CustomClass)
@:analyzer(optimize, local_dce, fusion, user_var_fusion)
class Interp {
	private var hasScriptObject(get, never):Bool;
	private function get_hasScriptObject():Bool 
		return scriptObject != null;

	private var _scriptObjectType(default, null):ScriptObjectType = SNull;

	var __instanceFields:Array<String> = [];

	public var scriptObject(default, set):Dynamic;
	public function set_scriptObject(v:Dynamic) {
		switch(Type.typeof(v)) {
			case TClass(c): // Class Access
				__instanceFields = Type.getInstanceFields(c);
				if(v is IHScriptCustomClassBehaviour) {
					var v:IHScriptCustomClassBehaviour = cast v;
					var classFields = v.__class__fields;
					if(classFields != null)
						__instanceFields = __instanceFields.concat(classFields);
					_scriptObjectType = SCustomClass;
				} else if(v is IHScriptCustomAccessBehaviour) {
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
		return scriptObject = v;
	}

	var inCustomClass(get, never):Bool;
	private function get_inCustomClass():Bool
		return hasScriptObject && _scriptObjectType == SCustomClass;

	var __customClass(get, never):CustomClass;
	private function get___customClass():CustomClass
		return inCustomClass ? cast scriptObject : null;

	public var errorHandler:Error->Void;
	public var importFailedCallback:Array<String>->Bool;

	public var customClasses:Map<String, CustomClassHandler>;
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
	var setAlias:Null<String> = null; // Custom Class import alias
	var beforeAlias:Null<String> = null;

	public var importEnabled:Bool = true;

	public var allowStaticVariables:Bool = false;
	public var allowPublicVariables:Bool = false;

	// TODO: move this to an external class
	public var importBlocklist:Array<String> = [
		// "flixel.FlxG"
	];

	var usingHandler:UsingHandler;

	#if hscriptPos
	var curExpr:Expr;
	#end

	public function new() {
		locals = new Map();
		declared = [];
		resetVariables();
		initOps();
	}

	private function resetVariables():Void {
		customClasses = new Map<String, CustomClassHandler>();
		variables = new Map<String, Dynamic>();
		publicVariables = new Map<String, Dynamic>();
		staticVariables = new Map<String, Dynamic>();

		usingHandler = new UsingHandler();
		
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
			case EIdent("Class"):
				Std.isOfType(expr1, Class);
			case EIdent("Map") | EIdent("IMap"):
				Std.isOfType(expr1, IMap);
			default:
				var expr2:Dynamic = expr(e2);
				if(expr2 != null) {
					if(expr1 is CustomClass && expr2 is CustomClassHandler) {
						var objName = cast(expr1, CustomClass).className;
						var clsName = cast(expr2, CustomClassHandler).name;
						objName == clsName;
					}
					else 
						Std.isOfType(expr1, expr2);
				}
				else 
					false;
		}
	}

	public function varExists(name:String):Bool {
		return allowStaticVariables && staticVariables.exists(name) || allowPublicVariables && publicVariables.exists(name) || variables.exists(name);
	}

	public function setVar(name:String, v:Dynamic):Void {
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
				var l = locals.get(id);
				if (l == null) {
					if (hasScriptObject && !varExists(id)) {
						var instanceHasField = __instanceFields.contains(id);

						if (_scriptObjectType == SObject && instanceHasField) {
							UnsafeReflect.setField(scriptObject, id, v);
							return v;
						} else if((_scriptObjectType == SCustomClass && instanceHasField) || _scriptObjectType == SAccessBehaviourObject) {
							var obj:IHScriptCustomAccessBehaviour = cast scriptObject;
							if(isBypassAccessor) {
								obj.__allowSetGet = false;
								var res = obj.hset(id, v);
								obj.__allowSetGet = true;
								return res;
							}
							return obj.hset(id, v);
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
						var obj = resolve(id, false, false);
						if (obj != null && obj is Property) {
							var prop:Property = cast obj;
							return prop.callSetter(id, v);
						}
						setVar(id, v);
					}
				} else if (l.r is Property) {
					var prop:Property = cast l.r;
					return prop.callSetter(id, v);
				} else {
					l.r = v;
					if (l.depth == 0) {
						setVar(id, v);
					}
				}
				// TODO
			case EField(e, f, s):
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
				var l = locals.get(id);
				v = fop(expr(e1), expr(e2));
				if (l == null) {
					if(hasScriptObject && !varExists(id)) {
						var instanceHasField = __instanceFields.contains(id);

						if (_scriptObjectType == SObject && instanceHasField) {
							UnsafeReflect.setField(scriptObject, id, v);
							return v;
						} else if((_scriptObjectType == SCustomClass && instanceHasField) || _scriptObjectType == SAccessBehaviourObject) {
							var obj:IHScriptCustomAccessBehaviour = cast scriptObject;
							if(isBypassAccessor) {
								obj.__allowSetGet = false;
								var res = obj.hset(id, v);
								obj.__allowSetGet = true;
								return res;
							}
							return obj.hset(id, v);
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
						var obj = resolve(id, true, false);
						if (obj != null && obj is Property) {
							var prop:Property = cast obj;
							return prop.callSetter(id, v);
						}
						setVar(id, v);
					}
				}
				else {
					var l = locals.get(id);
					if (l.r is Property) {
						var prop:Property = cast l.r;
						return prop.callSetter(id, v);
					}
					l.r = v;
					if (l.depth == 0) {
						setVar(id, v);
					}
				}
			case EField(e, f, s):
				var obj = expr(e);
				if(s && obj == null) return null;
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
					var prop:Property = null;
					if (v is Property) {
						prop = cast v;
						v = prop.callGetter(id);
					}

					if (prefix) {
						v += delta;
						if (prop != null)
							prop.callSetter(id, v);
						else
							l.r = v;
					} else {
						if (prop != null)
							prop.callSetter(id, v + delta);
						else
							l.r = v + delta;
					}
					return v;
				} else {
					var v:Dynamic = resolve(id, true, false);
					var prop:Property = null;
					if (v is Property) {
						prop = cast v;
						v = prop.callGetter(id);
					}

					if (prefix) {
						v += delta;
						if (prop != null)
							prop.callSetter(id, v);
						else
							setVar(id, v);
					} else {
						if (prop != null)
							prop.callSetter(id, v + delta);
						else
							setVar(id, v + delta);
					}
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

		if (rethrow)
			this.rethrow(e);
		else
			throw e;
		
		return null;
	}

	inline function rethrow(e:Dynamic):Void {
		#if hl
		hl.Api.rethrow(e);
		#else
		throw e;
		#end
	}

	public function resolve(id:String, doException:Bool = true, allowProperty:Bool = true):Dynamic {
		if (id == null)
			return null;
		id = StringTools.trim(id);

		if(inCustomClass && id == 'super') {
			var customClass:IHScriptCustomClassBehaviour = cast scriptObject;
			var superClass = customClass.hget('superClass');
			return superClass == null ? customClass.hget('superConstructor') : superClass;
		}

		if (locals.exists(id)) {
			var l = locals.get(id);
			if(l != null) {
				if(l.r != null && l.r is Property && allowProperty)  
					return cast(l.r, Property).callGetter(id);
				else 
					return l.r;
			}
		}

		for(map in [variables, publicVariables, staticVariables]) {
			if(map.exists(id)) {
				var r:Null<Dynamic> = map.get(id);
				if(r != null && r is Property && allowProperty) 
					return cast(r, Property).callGetter(id);
				else 
					return r;
			}
		}

		if(customClasses.exists(id))
			return customClasses.get(id);

		if (hasScriptObject) {
			// search in object
			if (id == "this") {
				return scriptObject;
			}
			var instanceHasField = __instanceFields.contains(id);

			if (_scriptObjectType == SObject && instanceHasField) {
				return UnsafeReflect.field(scriptObject, id);
			} else if((_scriptObjectType == SCustomClass && instanceHasField) || _scriptObjectType == SAccessBehaviourObject) {
				var obj:IHScriptCustomAccessBehaviour = cast scriptObject;
				if(isBypassAccessor) {
					obj.__allowSetGet = false;
					var res = obj.hget(id);
					obj.__allowSetGet = true;
					return res;
				}
				return obj.hget(id);
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

	public static var importRedirects:Map<String, String> = new Map();
	public static function getImportRedirect(className:String):String {
		return importRedirects.exists(className) ? importRedirects.get(className) : className;
	}

	public var localImportRedirects:Map<String, String> = new Map();
	public function getLocalImportRedirect(className:String):String {
		var className = className;
		if (importRedirects.exists(className))
			className = importRedirects.get(className);
		if (localImportRedirects.exists(className))
			className = localImportRedirects.get(className);
		return className;
	}

	public function expr(e:Expr):Dynamic {
		#if hscriptPos
		curExpr = e;
		var e = e.e;
		#end
		switch (e) {
			case EPackage(_):
			case EClass(name, fields, extend, interfaces, isFinal):
				var oldName:String = name;
				var hasAlias:Bool = (setAlias != null && beforeAlias == oldName);
				var toSetName:String = hasAlias ? setAlias : oldName;

				if (customClasses.exists(toSetName))
					error(EAlreadyExistingClass(toSetName));

				inline function importVar(thing:String):String {
					if (thing == null)
						return null;
					final variable:Class<Any> = variables.exists(thing) ? cast variables.get(thing) : null;
					return variable == null ? thing : Type.getClassName(variable);
				}
				var cls:CustomClassHandler = new CustomClassHandler(this, oldName, fields, importVar(extend), [for (i in interfaces) importVar(i)], isFinal);
				customClasses.set(toSetName, cls);
				if(hasAlias) {
					customClasses.set(oldName, cls); // Allow usage in the same module
					beforeAlias = null;
					setAlias = null;
				}
			case EImport(c, n, isUsing):
				if (!importEnabled)
					return null;
				var splitClassName = [for (e in c.split(".")) e.trim()];
				var realClassName = splitClassName.join(".");
				var claVarName = splitClassName[splitClassName.length - 1];
				var toSetName = n != null ? n : claVarName;
				var oldClassName = realClassName;
				var oldSplitName = splitClassName.copy();

				if (variables.exists(toSetName)) { // class is already imported 
					if(isUsing && !usingHandler.entryExists(toSetName))
						setUsing(toSetName, variables.get(toSetName)); 
					
					return null;
				}

				if(customClasses.exists(toSetName)) { // custom class is already parsed and imported 
					// NOTE: you will need to create/import 
					// the custom class first before
					// setting the extension
					if(isUsing && !usingHandler.entryExists(toSetName))
						setCustomClassUsing(toSetName, customClasses.get(toSetName));
					return null;
				}

				var realClassName = getLocalImportRedirect(realClassName);

				if (importBlocklist.contains(realClassName))
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
					beforeAlias = claVarName;
					setAlias = n;
					if (importFailedCallback == null || !importFailedCallback(oldSplitName)){
						beforeAlias = null;
						setAlias = null;
						error(EInvalidClass(oldClassName));
					}	
				} else {
					if (en != null) {
						if(isUsing) error(EInvalidClass(oldClassName));
						// ENUM!!!!
						var enumThingy:HEnum = {};
						for (c in en.getConstructors()) {
							try {
								//UnsafeReflect.setField(enumThingy, c, en.createByName(c));
								enumThingy.setEnum(c, en.createByName(c));
							} catch(e) {
								try {
									//UnsafeReflect.setField(enumThingy, c, UnsafeReflect.field(en, c));
									enumThingy.setEnum(c, UnsafeReflect.field(en, c));
								} catch(ex) {
									throw e;
								}
							}
						}
						variables.set(toSetName, enumThingy);
					} else {
						if(isUsing) setUsing(toSetName, cl);
						variables.set(toSetName, cl);
					}
				}

				return null;

			case EEnum(en, _): // TODO: enum abstracts
				var enumThingy:HEnum = {};
				var enumName = en.name;
				var enumFields = en.fields;
				for (i => ef in enumFields) {
					var fieldName = ef.name;
					
					if(ef.args.length < 1) {
						var enumValue:HEnumValue = {
							enumName: enumName,
							fieldName: fieldName,
							index: i,
							args: []
						}

						enumThingy.setEnum(fieldName, enumValue);
					}
					else {
						var params = ef.args;
						var hasOpt = false, minParams = 0;
						for (p in params) {
							if (p.opt)
								hasOpt = true;
							else
								minParams++;
						}
							
						var f = function(args:Array<Dynamic>):HEnumValue {
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
							return {
								enumName: enumName,
								fieldName: fieldName,
								index: i,
								args: args
							};
						};
						var f = Reflect.makeVarArgs(f);

						enumThingy.setEnum(fieldName, f);
					}
				}

				variables.set(en.name, enumThingy);
			case ECast(e, _): // TODO
				return expr(e);
			case EConst(c):
				switch (c) {
					case CInt(v): return v;
					case CFloat(f): return f;
					case CString(s): return s;
				}
			case EIdent(id):
				return resolve(id);
			case EVar(n, _, e, isPublic, isStatic, _, isFinal, _, getter, setter, isVar):
				var hasGetSet:Bool = (getter != null || setter != null);
				if(depth > 0 && hasGetSet) {
					error(ECustom("Property Accessor for local variables is not allowed"));
					return null;
				}
				declared.push({n: n, old: locals.get(n), depth: depth});
				var r:Dynamic = (e == null) ? null : expr(e);
				var declProp:Property = null;
				if (hasGetSet) {
					declProp = {
						r: r,
						getter: getter,
						setter: setter,
						isVar: isVar,
						isStatic: isStatic,
						interp: this,
					}
				}
				var declVar:DeclaredVar = {
					r: (declProp == null) ? r : declProp,
					depth: depth
				};
				locals.set(n, declVar);
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
				var args:Array<Dynamic> = makeArgs(params);

				switch (Tools.expr(e)) {
					case EField(e, f, s):
						var obj = expr(e);
						if (obj == null) {
							if(s) return null;
							error(EInvalidAccess(f));
						}
						return fcall(obj, f, args);
					default:
						return call(null, expr(e), args);
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
				var f = Reflect.makeVarArgs(f);
				if (name != null) {
					if (depth == 0) {
						// global function
						if(isStatic && allowStaticVariables) {
							staticVariables.set(name, f);
						} else if(isPublic && allowPublicVariables) {
							publicVariables.set(name, f);
						} else {
							variables.set(name, f);
						}
					} else {
						// function-in-function is a local function
						declared.push({n: name, old: locals.get(name), depth: depth});
						var ref:DeclaredVar = {r: f, depth: depth};
						locals.set(name, ref);
						capturedLocals.set(name, ref); // allow self-recursion
					}
				}
				return f;
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
			case ENew(cl, params, _):
				var a:Array<Dynamic> = makeArgs(params);
				return cnew(cl, a);
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
				var old = declared.length;
				var val:Dynamic = expr(e);
				var match = false;
				for (c in cases) {
					for (v in c.values) {
						// https://github.com/FunkinCrew/hscript/blob/funkin-dev/hscript/Interp.hx#L531
						switch (Tools.expr(v)) {
							case ECall(e, params):
								switch (Tools.expr(e)) {
									case EField(_, f):
										var isScripted:Bool = val is HEnumValue;
										var valStr:String = '';
										var valEnum:HEnumValue = null;
										if(isScripted)  {
											valEnum = cast val;
											valStr = valEnum.fieldName;
										}
										else {
											valStr = cast val;
											valStr = valStr.substring(0, valStr.indexOf("("));
										}

										if(valStr == f) {
											var valParams = isScripted ? valEnum.getConstructorArgs() : Type.enumParameters(val);
											for (i => p in params) {
												switch (Tools.expr(p)) {
													case EIdent(n):
														declared.push({
															n: n,
															old: {r: locals.get(n), depth: depth},
															depth: depth
														});
														locals.set(n, {r: valParams[i], depth: depth});
													default:
												}
											}
											match = true;
											break;
										}
									default:
								}
							default:
								if (expr(v) == val) {
									match = true;
									break;
								}
						}
					}
					
					if (match) {
						val = expr(c.expr);
						break;
					}
				}
				if (!match)
					val = def == null ? null : expr(def);
				restore(old);
				return val;
			case EMeta(a, b, e):
				var oldAccessor = isBypassAccessor;
				if(a == ":bypassAccessor") {
					isBypassAccessor = true;
				}
				var val = expr(e);

				isBypassAccessor = oldAccessor;
				return val;
			case ECheckType(e, _):
				return expr(e);
		}
		return null;
	}

	function doWhileLoop(econd:Expr, e:Expr):Void {
		var old = declared.length;
		do {
			if (!loopRun(() -> expr(e)))
				break;
		} while (expr(econd) == true);
		restore(old);
	}

	function whileLoop(econd:Expr, e:Expr):Void {
		var old = declared.length;
		while (expr(econd) == true) {
			if (!loopRun(() -> expr(e)))
				break;
		}
		restore(old);
	}

	function makeIterator(v:Dynamic, ?allowKeyValue = false):Iterator<Dynamic> {
		#if js
		// don't use try/catch (very slow)
		if(v is Array) {
			return allowKeyValue ? (v:Array<Dynamic>).keyValueIterator() : (v:Array<Dynamic>).iterator();
		}
		if(allowKeyValue && v.keyValueIterator != null)
			v = v.keyValueIterator();
		else if (v.iterator != null)
			v = v.iterator();
		#else
		if(allowKeyValue) 
			try v = v.keyValueIterator() catch (e:Dynamic) {};

		if(v.hasNext == null || v.next == null) 
			try v = v.iterator() catch (e:Dynamic) {};
		
		#end
		if (v.hasNext == null || v.next == null) error(EInvalidIterator(v));
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
						args.push(customClass.__superClass != null ? customClass.getSuperclass() : customClass);
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
			if (!loopRun(() -> expr(e)))
				break;
		}
		restore(old);
	}

	inline function loopRun(f:Void -> Void) {
		var cont = true;
		try {
			f();
		} catch (err:Stop) {
			switch (err) {
				case SContinue:
				case SBreak:
					cont = false;
				case SReturn:
					throw err;
			}
		}
		return cont;
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

		var cls:Null<Class<Dynamic>> = useRedirects ? Type.getClass(o) : null;
		if (useRedirects && {
			var cl:Null<String> = getClassType(o, cls);
			cl != null && getRedirects.exists(cl) && (_getRedirect = getRedirects[cl]) != null;
		}) {
			return _getRedirect(o, f);
		}
		
		if (o is IHScriptCustomAccessBehaviour) {
			var obj:IHScriptCustomAccessBehaviour = cast o;
			if(isBypassAccessor) {
				obj.__allowSetGet = false;
				var res = obj.hget(f);
				obj.__allowSetGet = true;
				return res;
			}
			return obj.hget(f);
		}

		if (o is IHScriptCustomBehaviour) {
			var obj:IHScriptCustomBehaviour = cast o;
			return obj.hget(f);
		}
		var v:Null<Dynamic> = null;
		if(isBypassAccessor) {
			if ((v = UnsafeReflect.field(o, f)) == null && useRedirects)
				v = Reflect.field(cls, f);
		}

		if(v == null) {
			#if php
			// https://github.com/HaxeFoundation/haxe/issues/4915
			try {
				if ((v = UnsafeReflect.getProperty(o, f)) == null && useRedirects)
					v = Reflect.getProperty(cls, f);
			}
			catch(e:Dynamic) {
				if ((v = UnsafeReflect.field(o, f)) == null && useRedirects)
					v = Reflect.field(cls, f);
			}
			#else
			if ((v = UnsafeReflect.getProperty(o, f)) == null && useRedirects)
				v = Reflect.getProperty(cls, f);
			#end
		}
		return v;
	}

	function set(o:Dynamic, f:String, v:Dynamic):Dynamic {
		if (o == null)
			error(EInvalidAccess(f));

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

	// STATIC EXTENSION ("USING")

	// Real class static extension
	function setUsing(name:String, obj:Dynamic) {
		if (usingHandler.entryExists(name)) return;
		if (UsingHandler.defaultExtension.exists(name)) {
			var us:UsingEntry = UsingHandler.defaultExtension.get(name);
			usingHandler.usingEntries.set(name, us);
			return;
		}
		if (obj == null) error(ECustom("Unknown using class " + name));

		var fn:Dynamic->String->Array<Dynamic>->Dynamic = null;
		var fields:Array<String> = [];
		var cls = obj;

		switch (Type.typeof(cls)) {
			case TClass(c):
				fields = Type.getClassFields(c);
			case TObject:
				fields = Reflect.fields(cls);
			default:
				error(ECustom('$name is not a class'));
		}

		fn = function(o:Dynamic, f:String, args:Array<Dynamic>) {
			var field = Reflect.field(cls, f);
			if (!Reflect.isFunction(field))
				return null;

			// invalid if the function has no arguments
			var totalArgs = Tools.argCount(field);
			if (totalArgs == 0)
				return null;

			return UnsafeReflect.callMethodUnsafe(cls, field, [o].concat(args));
		}

		if(fn != null) usingHandler.registerEntry(name, fn, fields);
	}

	// Custom Class Static Extension
	@:access(hscript.CustomClassHandler)
	function setCustomClassUsing(name:String, cls:CustomClassHandler) {
		if (usingHandler.entryExists(name)) return;

		var fn:Dynamic->String->Array<Dynamic> -> Dynamic;
		var customClass:CustomClassHandler = cls;
		var fields:Array<String> = customClass.__staticFields.copy();

		fn = function(o:Dynamic, f:String, args:Array<Dynamic>):Dynamic {
			var field:Dynamic = customClass.getField(f);
			if (!Reflect.isFunction(field))
				return null;
			/*
			var totalArgs:Int = Tools.argCount(field);
			if (totalArgs == 0)
				return null;
			 */
			return UnsafeReflect.callMethodUnsafe(null, field, [o].concat(args));
		}

		usingHandler.registerEntry(name, fn, fields);
	}

	function fcall(o:Dynamic, f:String, args:Array<Dynamic>):Dynamic {
		// Custom logic to handle super calls to prevent infinite recursion
		if(inCustomClass) {
			if (o == scriptObject.__superClass) {
				if (scriptObject.__superClass is CustomClass)
					return cast(scriptObject.__superClass, CustomClass).call(f, args, true);
				else
					return UnsafeReflect.callMethodUnsafe(scriptObject.__superClass, UnsafeReflect.field(scriptObject.__superClass, '_HX_SUPER__$f'), args);
			}
		}

		if (usingHandler.usingEntries.iterator().hasNext()) { // If is not empty
			var v:Dynamic = null;
			for (n => us in usingHandler.usingEntries) {
				if(us.hasField(f)) {
					v = us.call(o, f, args);
					if (v != null)
						return v;
				}
			}
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
		return UnsafeReflect.callMethodSafe(o, f, args);
	}

	function cnew(cl:String, args:Array<Dynamic>):Dynamic {
		var c:Dynamic = resolve(cl);
		if (c == null)
			c = Type.resolveClass(cl);
		if (c is IHScriptCustomConstructor) {
			var c:IHScriptCustomConstructor = cast c;
			return c.hnew(args);
		} else
			return Type.createInstance(c, args);
	}
}
