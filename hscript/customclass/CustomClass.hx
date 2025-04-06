package hscript.customclass;

import hscript.utils.UnsafeReflect;
import haxe.Constraints.Function;
import hscript.Expr;
import hscript.Expr.VarDecl;
import hscript.Expr.FunctionDecl;
import hscript.Expr.FieldDecl;

using Lambda;
using StringTools;

/**
 * The Custom Class core.
 * 
 * Provides handlers for custom classes.
 * Based on Polymod Hscript class system
 * @see https://github.com/larsiusprime/polymod/tree/master/polymod/hscript/_internal
 */
@:access(hscript.customclass.CustomClassDecl)
class CustomClass implements IHScriptCustomAccessBehaviour {
	public var interp:Interp;

	public var superClass:Dynamic;
	public var superConstructor(default, null):Dynamic;
	// TODO: move this to CustomClassDecl
	public var className(get, never):String;
	private function get_className():String {
		var pkg = __class.pkg != null ? '${__class.pkg.join(".")}.' : "";
		var name = __class.classDecl.name;
		return '$pkg$name';
	}

	private var __class:CustomClassDecl;
	private var _cachedSuperFields:Null<Map<String, Dynamic>> = null;

	private var _cachedFieldDecls:Map<String, FieldDecl> = null;
	private var _cachedFunctionDecls:Map<String, FunctionDecl> = null;
	private var _cachedVarDecls:Map<String, VarDecl> = null;

	public var __allowSetGet:Bool = false;

	public function new(__class:CustomClassDecl, args:Array<Dynamic>, ?extendFieldDecl:Map<String, Dynamic>, ?ogInterp:Interp, ?callNew:Bool = true) {
		this.__class = __class;
		this.interp = new Interp(this);

		if (ogInterp != null && ogInterp.importFailedCallback != null && ogInterp.errorHandler != null) {
			interp.importFailedCallback = ogInterp.importFailedCallback;
			interp.errorHandler = ogInterp.errorHandler;
			interp.allowStaticVariables = ogInterp.allowStaticVariables;
			interp.staticVariables = ogInterp.staticVariables;
			// todo: make it so you can use variables from the same scope as where the class was defined
		}

		buildImports();
		buildUsings();

		if (extendFieldDecl != null)
			_cachedSuperFields = extendFieldDecl;

		buildClass();

		if (hasFunction('new') && callNew) {
			buildSuperConstructor();
			callFunction('new', args);
			if (this.superClass == null && this.__class.classDecl.extend != null)
				this.interp.error(ECustom("super() not called"));
		} else if (__class.classDecl.extend != null) {
			createSuperClass(args);
		}
	}

	function buildClass() {
		_cachedFieldDecls = [];
		_cachedFunctionDecls = [];
		_cachedVarDecls = [];

		if (_cachedSuperFields == null)
			_cachedSuperFields = [];

		for (f in __class.classDecl.fields) {
			if (f.access.contains(AStatic))
				continue; // Skip static field. It's handled by CustomClassDecl.hx
			_cachedFieldDecls.set(f.name, f);
			switch (f.kind) {
				case KFunction(fn):
					if(f.name.startsWith('set_') || f.name.startsWith('get_'))
						__allowSetGet = true;
					_cachedFunctionDecls.set(f.name, fn);
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
					var f0 = this.interp.expr(fexpr);
					this.interp.variables.set(f.name, f0);
				case KVar(v):
					_cachedVarDecls.set(f.name, v);
					if (v.expr != null) {
						var varValue = this.interp.expr(v.expr);
						this.interp.variables.set(f.name, varValue);
					}
			}
		}

		if (!_cachedSuperFields.empty()) {
			for (f => v in _cachedSuperFields) {
				this.hset(f, v);
			}
			_cachedSuperFields.clear();
		}
	}

	function buildSuperConstructor() {
		superConstructor = Reflect.makeVarArgs(function(args:Array<Dynamic>) {
			createSuperClass(args);
		});
	}

	private function createSuperClass(args:Array<Dynamic> = null) {
		if (args == null)
			args = [];

		if(__class.superClassDecl is CustomClassDecl)
			superClass = new CustomClass(__class.superClassDecl, args, _cachedFieldDecls, this.interp);
		else {
			if (_cachedSuperFields != null) {
				Reflect.setField(__class.superClassDecl, "__cachedFields", _cachedSuperFields); // Static field
			}
			superClass = Type.createInstance(__class.superClassDecl, args);
			superClass.__customClass = this;
			superClass.__real_fields = Type.getInstanceFields(__class.superClassDecl);
		}
		/*
		var extendString = new Printer().typeToString(__class.classDecl.extend);
		if (__class.pkg != null && extendString.indexOf(".") == -1) {
			extendString = __class.pkg.join(".") + "." + extendString;
		}

		if (Interp.customClassExist(extendString)) {
			var customSuperClass:CustomClass = new CustomClass(Interp.getCustomClass(extendString), args, _cachedSuperFields, this.interp);
			superClass = customSuperClass;
		} else {
			var c = Type.resolveClass('${extendString}_HSX');
			if (c == null) {
				interp.error(ECustom("could not resolve super class: " + extendString));
			}
			if (_cachedSuperFields != null) {
				Reflect.setField(c, "__cachedFields", _cachedSuperFields); // Static field
			}

			superClass = Type.createInstance(c, args);
			superClass.__customClass = this;
			superClass.__real_fields = Type.getInstanceFields(c);
		}
		*/
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

	public function callFunction(name:String, args:Array<Dynamic> = null):Dynamic {
		var r:Dynamic = null;

		if (hasField(name)) {
			var fn = getFunction(name);
			try {
				if (fn == null)
					interp.error(ECustom('${name} is not a function'));

				r = UnsafeReflect.callMethodUnsafe(null, fn, args);
			} catch (e:hscript.Expr.Error) {
				// A script error occurred while executing the custom class function.
				// Purge the function from the cache so it is not called again.
				purgeFunction(name);
			}
		} else {
			var fixedArgs = [];
			// OVERRIDE CHANGE: Use _HX_SUPER__ when calling superclass
			var fixedName = '_HX_SUPER__${name}';
			for (a in args) {
				if ((a is CustomClass)) {
					var customClass:CustomClass = cast(a, CustomClass).superClass;
					fixedArgs.push(customClass.superClass != null ? customClass.superClass : customClass);
				} else {
					fixedArgs.push(a);
				}
			}
			var superFn = Reflect.field(superClass, fixedName);
			if (superFn == null) {
				this.interp.error(ECustom('Error while calling function super.${name}(): EInvalidAccess'
					+ '\n'
					+ 'InvalidAccess error: Super function "${name}" does not exist! Define it or call the correct superclass function.'));
			}
			r = Reflect.callMethod(superClass, superFn, fixedArgs);
		}
		return r;
	}

	// Field check

	private function hasField(name:String):Bool {
		return _cachedFieldDecls != null ? _cachedFieldDecls.exists(name) : false;
	}

	private function getField(name:String):FieldDecl {
		return _cachedFieldDecls != null ? _cachedFieldDecls.get(name) : null;
	}

	private function hasVar(name:String):Bool {
		return _cachedVarDecls != null ? _cachedVarDecls.exists(name) : false;
	}

	private function getVar(name:String):VarDecl {
		return _cachedVarDecls != null ? _cachedVarDecls.get(name) : null;
	}

	private function hasFunction(name:String):Bool {
		return _cachedFunctionDecls != null ? _cachedFunctionDecls.exists(name) : false;
	}

	private function getFunction(name:String):Function {
		var fn = this.interp.variables.get(name);
		return Reflect.isFunction(fn) ? fn : null;
	}

	// SuperClass field check

	private function cacheSuperField(name:String, value:Dynamic) {
		if (_cachedSuperFields != null) {
			_cachedSuperFields.set(name, value);
		}
	}

	var __superClassFieldList:Array<String> = null;
	// TODO: superHasField when it extends another Custom Class
	public function superHasField(name:String):Bool {
		if (superClass == null)
			return false;

		// Reflect.hasField(this, name) is REALLY expensive so we use a cache.
		if (__superClassFieldList == null) {
			__superClassFieldList = Reflect.fields(superClass).concat(Type.getInstanceFields(Type.getClass(superClass)));
		}

		return __superClassFieldList.indexOf(name) != -1;
	}

	/**
	 * Remove a function from the cache.
	 * This is useful when a function is broken and needs to be skipped.
	 * @param name The name of the function to remove from the cache.
	 */
	private function purgeFunction(name:String):Void {
		if (_cachedFunctionDecls != null) {
			_cachedFunctionDecls.remove(name);
		}
	}

	// Access fields

	public function hget(name:String):Dynamic {
		return resolveField(name);
	}

	public function hset(name:String, val:Dynamic):Dynamic {
		switch (name) {
			default:
				if (hasVar(name)) {
					if (__allowSetGet && hasFunction('set_${name}'))
						return __callSetter(name, val);

					this.interp.variables.set(name, val);
				} else if (this.superClass != null) {
					if (Type.getClass(this.superClass) == null) {
						// Anonymous structure
						if (Reflect.hasField(this.superClass, name)) {
							Reflect.setField(this.superClass, name, val);
						}
						return val;
					} else if (this.superClass is CustomClass) {
						var superCustomClass:CustomClass = cast(this.superClass, CustomClass);
						try {
							superCustomClass.__allowSetGet = this.__allowSetGet;
							return superCustomClass.hset(name, val);
						} catch (e:Dynamic) {}
					} else if (superHasField(name)) {
						if (__allowSetGet)
							Reflect.setProperty(this.superClass, name, val);
						else
							Reflect.setField(this.superClass, name, val);
					} else {
						throw "field '" + name + "' does not exist in custom class '" + this.className + "' or super class '"
							+ Type.getClassName(Type.getClass(this.superClass)) + "'";
					}
				} else {
					throw "field '" + name + "' does not exist in custom class '" + this.className + "'";
				}
		}
		return val;
	}

	public function __callGetter(name:String):Dynamic {
		__allowSetGet = false;
		var r = callFunction('get_${name}');
		__allowSetGet = true;
		return r;
	}

	public function __callSetter(name:String, val:Dynamic):Dynamic {
		__allowSetGet = false;
		var r = callFunction('set_${name}', [val]);
		__allowSetGet = true;
		return r;
	}

	private function resolveField(name:String):Dynamic {
		switch (name) {
			case "superClass":
				return this.superClass;
			case "createSuperClass":
				return this.createSuperClass;
			case "hasFunction":
				return this.hasFunction;
			case "callFunction":
				return this.callFunction;
			default:
				if (hasFunction(name)) {
					var fn:Function = Reflect.makeVarArgs(function(args:Array<Dynamic>) {
						return this.callFunction(name, args);
					});

					return fn;
				}

				if (hasVar(name)) {
					var value:Dynamic = null;

					if (__allowSetGet && hasFunction('get_${name}')) {
						value = __callGetter(name);
					} else if (this.interp.variables.exists(name)) {
						value = this.interp.variables.get(name);
					} else {
						var v = getVar(name);

						if (v.expr != null) {
							value = this.interp.expr(v.expr);
							this.interp.variables.set(name, value);
						}
					}

					return value;
				}

				if (this.superClass != null) {
					if (Type.getClass(this.superClass) == null) {
						// Anonymous structure
						if (Reflect.hasField(this.superClass, name)) {
							return Reflect.field(this.superClass, name);
						} else {
							throw "field '" + name + "' does not exist in custom class '" + this.className + "' or super class '"
								+ Type.getClassName(Type.getClass(this.superClass)) + "'";
						}
					}

					if (this.superClass is CustomClass) {
						var superCustomClass:CustomClass = cast(this.superClass, CustomClass);
						try {
							superCustomClass.__allowSetGet = this.__allowSetGet;
							return superCustomClass.hget(name);
						} catch (e:Dynamic) {}
					}

					var fields = Type.getInstanceFields(Type.getClass(this.superClass));
					if (fields.contains(name)) {
						return __allowSetGet ? Reflect.getProperty(this.superClass, name) : Reflect.field(this.superClass, name);
					} else {
						throw "field '" + name + "' does not exist in custom class '" + this.className + "' or super class '"
							+ Type.getClassName(Type.getClass(this.superClass)) + "'";
					}
				} else {
					throw "field '" + name + "' does not exist in custom class '" + this.className + "'";
				}
		}
		return null;
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
