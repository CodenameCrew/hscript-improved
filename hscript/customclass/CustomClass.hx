package hscript.customclass;

import hscript.utils.UnsafeReflect;
import haxe.Constraints.Function;
import hscript.Expr;
import hscript.Expr.FieldPropertyAccess;
import hscript.Expr.VarDecl;
import hscript.Expr.FunctionDecl;
import hscript.Expr.FieldDecl;

using Lambda;
using StringTools;

/**
 * The Custom Class core.
 * 
 * Provides handlers for custom classes.
 * 
 * Rest in peace, CustomClassHandler.hx
 * 
 * Based on Polymod Hscript class system
 * @see https://github.com/larsiusprime/polymod/tree/master/polymod/hscript/_internal
 */
@:access(hscript.customclass.CustomClassDecl)
class CustomClass implements IHScriptCustomAccessBehaviour {
	public var interp:Interp;

	public var superClass:Dynamic;
	public var superConstructor(default, null):Dynamic;

	public var superIsCustomClass(get, never):Bool;
	private function get_superIsCustomClass():Bool
		return (superClass != null && superClass is CustomClass);

	public var className(get, never):String;
	private function get_className():String {
		return __class.toString();
	}

	private var __class:CustomClassDecl;
	private var __cachedSuperFields:Null<Map<String, Dynamic>> = null;

	private var __cachedFieldDecls:Map<String, FieldDecl> = [];
	private var __cachedFunctionDecls:Map<String, FunctionDecl> = [];
	private var __cachedVarDecls:Map<String, VarDecl> = [];

	public var __allowSetGet:Bool = false;
	public var __allowPrivateAccess:Bool = false;

	private var isInline(default, null):Bool = false;
	private var ogVariables(default, null):Map<String, Dynamic>;
	private var initializing(default, null):Bool = false; // Allows final variables to be initialized

	public function new(__class:CustomClassDecl, args:Array<Dynamic>, ?extendFieldDecl:Map<String, Dynamic>, ?ogInterp:Interp, ?callNew:Bool = true) {
		this.__class = __class;
		this.interp = new Interp(this);

		if (ogInterp != null) {
			interp.importFailedCallback = ogInterp.importFailedCallback;
			interp.errorHandler = ogInterp.errorHandler;
			interp.allowStaticVariables = ogInterp.allowStaticVariables;
			interp.staticVariables = ogInterp.staticVariables;
			// todo: make it so you can use variables from the same scope as where the class was defined
			if(__class.isInline != null && __class.isInline) {
				isInline = __class.isInline;
				ogVariables = ogInterp.variables;
				interp.allowPublicVariables = __class.staticInterp.allowPublicVariables;
				interp.publicVariables = __class.staticInterp.publicVariables;
			}
		}

		buildImports();
		buildUsings();

		if (extendFieldDecl != null)
			__cachedSuperFields = extendFieldDecl;

		buildClass();

		if (hasFunction('new') && callNew) {
			buildSuperConstructor();
			initializing = true;
			callFunction('new', args);
			initializing = false;

			if (this.superClass == null && this.__class.classDecl.extend != null)
				this.interp.error(ECustom("super() not called"));
		} else if (__class.classDecl.extend != null) {
			createSuperClass(args);
		}
	}

	function buildClass() {
		if (__cachedSuperFields == null)
			__cachedSuperFields = [];

		for (f in __class.classDecl.fields) {
			if (f.access.contains(AStatic))
				continue; // Skip static field. It's handled by CustomClassDecl.hx
			__cachedFieldDecls.set(f.name, f);
			switch (f.kind) {
				case KFunction(fn):
					__cachedFunctionDecls.set(f.name, fn);
					#if hscriptPos
					var fexpr:Expr = {
						e: ExprDef.EFunction(fn.args, fn.body, f.name, fn.ret, false, false),
						pmin: fn.body.pmin,
						pmax: fn.body.pmax,
						line: fn.body.line,
						origin: fn.body.origin
					};
					#else
					var fexpr = Expr.EFunction(fn.args, fn.body, f.name, fn.ret, false, false);
					#end
					var func:Function = this.interp.expr(fexpr);
					this.interp.variables.set(f.name, func);
				case KVar(v):
					if(v.get != ADefault || v.set != ADefault)
						__allowSetGet = true;
					__cachedVarDecls.set(f.name, v);
					if (v.expr != null) {
						var varValue = this.interp.expr(v.expr);
						this.interp.variables.set(f.name, varValue);
					}
			}
		}

		if (!__cachedSuperFields.empty()) {
			for (f => v in __cachedSuperFields) {
				this.hset(f, v);
			}
			__cachedSuperFields.clear();
		}
	}

	function buildSuperConstructor() {
		superConstructor = Reflect.makeVarArgs(function(args:Array<Dynamic>) {
			createSuperClass(args);
		});
	}

	private function createSuperClass(?args:Array<Dynamic>) {
		if (args == null)
			args = [];

		if(__class.superClassDecl is CustomClassDecl) 
			superClass = new CustomClass(__class.superClassDecl, args, __cachedSuperFields, this.interp);
		else {
			if (__cachedSuperFields != null) {
				Reflect.setField(__class.superClassDecl, "__cachedFields", __cachedSuperFields); // Static field
			}

			var disallowCopy = Type.getInstanceFields(__class.superClassDecl);

			superClass = Type.createInstance(__class.superClassDecl, args);
			superClass.__customClass = this;
			superClass.__real_fields = disallowCopy;

			if(isInline) {
				for(s => v in ogVariables)
					if(!disallowCopy.contains(s))
						interp.variables.set(s, v);
			}
		}
	}

	function buildImports() {
		var i:Int = 0;
		for (_import in __class.imports) {
			var importedClass = _import.fullPath;
			var importAlias = _import.as;

			if (Interp.customClassExist(importedClass) && this.interp.importFailedCallback != null) {
				this.interp.importFailedCallback(importedClass.split("."), importAlias);
				continue;
			}

			#if hscriptPos
			var e:Expr = {
				e: ExprDef.EImport(importedClass, importAlias),
				pmin: 0,
				pmax: 0,
				origin: this.className,
				line: i
			};
			#else
			var e = Expr.EImport(importedClass, importAlias);
			#end
			this.interp.expr(e);
			i++;
		}
	}

	inline function buildUsings() {
		for (us in __class.usings) {
			@:privateAccess this.interp.useUsing(us);
		}
	}

	public function callFunction(name:String, ?args:Array<Dynamic>):Dynamic {
		var r:Dynamic = null;

		if (hasField(name)) {
			var fn = getFunction(name);
			try {
				if (fn == null)
					interp.error(ECustom('${name} is not a function'));

				r = UnsafeReflect.callMethodUnsafe(null, fn, args == null ? [] : args);
			} catch (e:hscript.Expr.Error) {
				// A script error occurred while executing the custom class function.
				// Purge the function from the cache so it is not called again.
				purgeFunction(name);
			}
		} 
		else {
			var fixedArgs = [];
			for (a in args) {
				if ((a is CustomClass)) {
					var customClass:CustomClass = cast(a, CustomClass);
					fixedArgs.push(customClass.superClass != null ? customClass.getSuperclass() : customClass);
				} else {
					fixedArgs.push(a);
				}
			}
			var superFn:Function = null;
			if(superClass is CustomClass) {
				superFn = cast(superClass, CustomClass).hget(name);
			}
			else {
				var fixedName = '_HX_SUPER__${name}';
				superFn = Reflect.field(superClass, fixedName);
			}
			
			if (superFn == null || !Reflect.isFunction(superFn)) {
				this.interp.error(ECustom('Error while calling function super.${name}(): EInvalidAccess'
					+ '\n'
					+ 'InvalidAccess error: Super function "${name}" does not exist! Define it or call the correct superclass function.'));
			}
			r = Reflect.callMethod((superClass is CustomClass) ? null : superClass, superFn, fixedArgs);
		}
		return r;
	}

	// Field check

	private function hasField(name:String):Bool {
		return __cachedFieldDecls.exists(name);
	}

	private function getField(name:String):FieldDecl {
		return __cachedFieldDecls != null ? __cachedFieldDecls.get(name) : null;
	}

	private function hasVar(name:String):Bool {
		return __cachedVarDecls.exists(name);
	}

	private function getVar(name:String):VarDecl {
		return __cachedVarDecls.get(name);
	}

	private function hasFunction(name:String):Bool {
		return __cachedFunctionDecls.exists(name);
	}

	private function getFunction(name:String):Function {
		var fn = this.interp.variables.get(name);
		return Reflect.isFunction(fn) ? fn : null;
	}

	// SuperClass field check

	private function cacheSuperField(name:String, value:Dynamic) {
		if (__cachedSuperFields != null) {
			__cachedSuperFields.set(name, value);
		}
	}

	var __superClassFieldList:Array<String> = null;
	
	public function superHasField(name:String):Bool {
		if (superClass == null)
			return false;

		// Reflect.hasField(this, name) is REALLY expensive so we use a cache.
		if (__superClassFieldList == null) {
			__superClassFieldList = [];

			if(superClass is CustomClass) {
				var cls:Null<Dynamic> = superClass;
				while(cls != null && cls is CustomClass) {
					var currentClass = cast(cls, CustomClass);
					var fields = [for(f in currentClass.__cachedFieldDecls.keys()) f];
					__superClassFieldList.concat(fields);

					var next = currentClass.superClass;
					if(next == null)
						break;
					cls = next;
				}
				
				// The last fetched class is a real class
				if(!(cls is CustomClass))
					__superClassFieldList.concat(Reflect.fields(cls).concat(Type.getInstanceFields(Type.getClass(cls))));
			}
			else {
				var realFields = Reflect.fields(superClass).concat(Type.getInstanceFields(Type.getClass(superClass)));
				__superClassFieldList.concat(realFields);
			}
		}

		return __superClassFieldList.indexOf(name) != -1;
	}

	/**
	 * Remove a function from the cache.
	 * This is useful when a function is broken and needs to be skipped.
	 * @param name The name of the function to remove from the cache.
	 */
	private function purgeFunction(name:String):Void {
		if (__cachedFunctionDecls != null) {
			__cachedFunctionDecls.remove(name);
		}
	}

	// Access fields

	public function hget(name:String):Dynamic {
		switch (name) {
			case "superClass": return this.superClass;
			case "createSuperClass": return this.createSuperClass;
			case "hasFunction": return this.hasFunction;
			case "callFunction": return this.callFunction;
			default:
				if (hasFunction(name)) {
					var fn:Function = Reflect.makeVarArgs(function(args:Array<Dynamic>) {
						return this.callFunction(name, args);
					});

					return fn;
				}

				if (hasVar(name)) {
					var v = getVar(name);
					var getter = v.get;
					
					var value:Dynamic = null;

					if(getter == ANever || getter == ANull && !__allowPrivateAccess)
						throw 'field $name cannot be accessed for reading';

					if (__allowSetGet && getter == AGet) {
						if (hasFunction('get_$name'))
							value = __callGetter(name);
						else
							throw 'Method get_$name required by property $name is missing';
					}
					else if (this.interp.variables.exists(name)) 
						value = this.interp.variables.get(name);
					else {
						if (v.expr != null) {
							value = this.interp.expr(v.expr);
							this.interp.variables.set(name, value);
						}
					}

					return value;
				}

				if (this.superClass != null) {
					if (superHasField(name)) {
						if (Type.getClass(this.superClass) == null) {
							// Anonymous structure
							if (Reflect.hasField(this.superClass, name))
								return Reflect.field(this.superClass, name);
							else
								throw "field '" + name + "' does not exist in custom class '" + this.className + "' or super class '[ANONYMOUS STRUCTURE]'";
						}

						if (this.superClass is CustomClass) {
							var superCustomClass:CustomClass = cast(this.superClass, CustomClass);

							superCustomClass.__allowSetGet = this.__allowSetGet;
							superCustomClass.__allowPrivateAccess = this.__allowPrivateAccess;
							return superCustomClass.hget(name);
						}

						// Real Class
						if (__allowSetGet)
							Reflect.getProperty(this.superClass, name);
						else 
							Reflect.field(this.superClass, name);
					}
					else
						throw "field '" + name + "' does not exist in custom class '" + this.className + "' or super class '" + Type.getClassName(Type.getClass(this.superClass)) + "'";
				} 
				else 
					throw "field '" + name + "' does not exist in custom class '" + this.className + "'";
		}
		return null;
	}

	public function hset(name:String, val:Dynamic):Dynamic {
		switch (name) {
			default:
				if (hasVar(name)) {
					var v = getVar(name);
					var setter = v.set;

					if (setter == ANever || setter == ANull && !__allowPrivateAccess || (v.isFinal && !initializing))
						throw 'field $name cannot be accessed for writing';

					if (__allowSetGet && setter == ASet) {
						if (hasFunction('set_$name'))
							return __callSetter(name, val);
						else
							throw 'Method set_$name required by property $name is missing';
					}

					this.interp.variables.set(name, val);
				} 
				else if (this.superClass != null) {
					if (superHasField(name)) {
						if (Type.getClass(this.superClass) == null) {
							// Anonymous structure
							if (Reflect.hasField(this.superClass, name)) {
								Reflect.setField(this.superClass, name, val);
								return val;
							}
							else 
								throw "field '" + name + "' does not exist in custom class '" + this.className + "' or super class '[ANONYMOUS STRUCTURE]'";
						} 

						if (this.superClass is CustomClass) {
							var superCustomClass:CustomClass = cast(this.superClass, CustomClass);

							superCustomClass.__allowSetGet = this.__allowSetGet;
							superCustomClass.__allowPrivateAccess = this.__allowPrivateAccess;
							return superCustomClass.hset(name, val);
						}
						// Real Class

						if (__allowSetGet)
							Reflect.setProperty(this.superClass, name, val);
						else
							Reflect.setField(this.superClass, name, val);
					}
					else 
						throw "field '" + name + "' does not exist in custom class '" + this.className + "' or super class '" + Type.getClassName(Type.getClass(this.superClass)) + "'";
				} 
				else 
					throw "field '" + name + "' does not exist in custom class '" + this.className + "'";
		}
		return val;
	}

	public function __callGetter(name:String):Dynamic {
		__allowSetGet = false;
		var r = callFunction('get_$name');
		__allowSetGet = true;
		return r;
	}

	public function __callSetter(name:String, val:Dynamic):Dynamic {
		__allowSetGet = false;
		var r = callFunction('set_$name', [val]);
		__allowSetGet = true;
		return r;
	}

	/**
	 * Returns the real superClass if the Custom Class
	 * extends another Custom Class, and so on until
	 * it reaches a real class, otherwise it will
	 * return the last fetched Custom Class
	 * @return Null<Dynamic>
	 */
	public function getSuperclass():Null<Dynamic> {
		var cls:Null<Dynamic> = this.superClass;

		// Check if the superClass is another custom class,
		// so it will find for a real class, otherwise
		// returns the last super CustomClass parent.
		while(cls != null && cls is CustomClass) {
			var next = cast(cls, CustomClass).superClass;
			if(next == null)
				break; // Return the Custom Class itself
			cls = next;
		}

		return cls;
	}
}
