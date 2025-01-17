package stdgo;

import haxe.Exception;
import haxe.io.Bytes;
import haxe.macro.ComplexTypeTools;
import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.ExprTools;
import haxe.macro.PositionTools;
import haxe.macro.TypeTools;
import stdgo.reflect.Reflect.GoType;
import stdgo.reflect.Reflect.Type;

class Go {
	static function getMetaLength(meta:Metadata):ExprDef {
		for (m in meta) {
			if (m.name != ":length")
				continue;
			return m.params[0].expr;
		}
		return EConst(CIdent("0"));
	}

	static private function getData(expr:Expr):Expr {
		return switch expr.expr {
			case ECheckType(e, t): return e;
			case EParenthesis(e): return getData(e);
			default: expr;
		}
	}

	static private function getType(expr:Expr):ComplexType {
		var type:ComplexType = null;
		if (expr == null)
			return type;
		switch expr.expr {
			case ECheckType(e, t):
				type = t;
			case EParenthesis(e):
				type = getType(e);
			default:
		}
		return type;
	}

	public static macro function copy<T>(dst:Expr, src:Expr) {
		var type = Context.toComplexType(Context.followWithAbstracts(Context.typeof(dst)));
		var srcType = Context.toComplexType(Context.follow(Context.typeof(src)));
		var isString = switch srcType {
			case TPath(p): p.name == "String" && p.pack.length == 0;
			default:
				false;
		}
		switch srcType {
			case TPath(p):
				switch p.name {
					case "String", "GoString":
						src = macro($src : GoString);
					case "Slice", "SliceData": // src
					default: // named
						src = macro $src.__t__;
				}
			default:
		}
		switch type {
			case TPath(p):
				switch p.name {
					case "SliceData": // dst
					default: // named
						dst = macro $dst.__t__;
				}
			default:
		}
		return macro {
			var src = $src;
			var dst = $dst;
			var length = dst.length >= src.length ? src.length : dst.length; // min length
			for (i in 0...length.toBasic()) {
				dst[i] = src[i];
			}
			length;
		}
	}

	public static function string(s:Dynamic):String {
		if ((s is stdgo.StdGoTypes.AnyInterfaceData)) {
			s = s.value;
		}
		if ((s is stdgo.Error)) {
			s = s.error();
		}
		return if (haxe.Int64.isInt64(s)) {
			haxe.Int64.toStr(s);
		} else {
			Std.string(s);
		}
	}

	// GOROUTINE
	public static macro function routine(expr) {
		return expr;
	}

	public static macro function toInterface(expr) {
		var t = Context.typeof(expr);
		var follow = true;
		switch t {
			case TType(t, params):
				final t = t.get();
				if (t.pack.length == 1 && t.pack[0] == "stdgo" && (t.name != "GoByte" && t.name != "GoRune" && t.name != "GoFloat")) {
					follow = false;
				}
			default:
		}
		if (follow)
			t = Context.follow(t);
		switch t {
			case TAbstract(t, params):
				var t = t.get();
				if (t.name == "AnyInterface" && t.pack.length == 1 && t.pack[0] == "stdgo") {
					return expr; // prevent interface{} inside interface{}
				}
			case TInst(t, params):
				var t = t.get();
				if (t.name == "String" && t.pack.length == 0)
					expr = macro new GoString($expr);
			default:
		}
		var ty = gtDecode(t, expr, []);
		return macro new AnyInterface($expr, new stdgo.reflect.Reflect._Type($ty));
	}

	public static macro function smartcast(expr:Expr, toPointer:Bool = false) {
		function panicWrap(e:Expr) {
			final set = toPointer ? macro Go.pointer($e) : macro $e;
			return macro {var e = $e; e == null ?throw "panic: conversion":$set;};
		}
		switch expr.expr {
			case ECast(e, ct):
				var et = Context.typeof(e);
				switch et {
					case TInst(cl, params):
						var cl = cl.get();
						if (cl.isInterface) {
							var t = ComplexTypeTools.toType(ct);
							switch t {
								case TAbstract(_, _):
									return panicWrap(macro($e.__underlying__() : $ct));
								default:
							}
						}
					default:
				}
			default:
		}
		return panicWrap(expr);
	}

	public static macro function assertable(expr:Expr) {
		function parens(expr) {
			return switch expr.expr {
				case EParenthesis(e): parens(e);
				default: expr;
			}
		}
		expr = parens(expr);
		switch expr.expr {
			case ECheckType(e, t):
				var t = Context.follow(ComplexTypeTools.toType(t));
				if (t == null)
					Context.error("complexType converted to type is null", Context.currentPos());
				var et = Context.follow(Context.typeof(e));
				var value = gtDecode(t, null, []);
				switch et {
					case TInst(cl, params):
						var cl = cl.get();
						if (cl.isInterface) e = macro $e.__underlying__();
					default:
				}
				return macro {
					final v = new stdgo.reflect.Reflect._Type($value);
					@:privateAccess stdgo.reflect.Reflect.directlyAssignable(v,
						$e.type) || @:privateAccess stdgo.reflect.Reflect.implementsMethod(v, $e.type, false)
					;
				};
			default:
				Context.error("unknown assignable expr: " + expr.expr, Context.currentPos());
				return macro null;
		}
	}

	static function escapeParens(expr:Expr):Expr {
		return switch expr.expr {
			case EParenthesis(e):
				escapeParens(e);
			default:
				expr;
		}
	}

	public static macro function pointer(expr:Expr, hasSet:Bool = false) {
		expr = escapeParens(expr);

		var p:TypePath = {name: "Pointer", pack: ["stdgo"]};
		var expected = Context.getExpectedType();
		if (expected != null) {
			var ct = Context.toComplexType(expected);
			if (ct != null) {
				switch ct {
					case TPath(path):
						if (path.name == "Pointer") {
							p = path;
						}
					default:
				}
			}
		}

		var declare:Bool = false;
		switch expr.expr {
			case EConst(c):
				switch c {
					case CIdent(s):
						switch s {
							case "null":
								declare = true;
							case "this":
								Context.error('setting "this" to pointer is not allowed', Context.currentPos());
							case "false", "true":
								declare = true;
						}
					default:
						declare = true;
				}
			case EArray(e1, e2):
				var t = Context.follow(Context.typeof(e1));
				switch t {
					case TAbstract(t, params):
						var t = t.get();
						if (t.name == "Pointer") {
							switch params[0] {
								case TAbstract(t2, params2):
									t = t2.get();
									e1 = macro ${e1}.value;
								default:
							}
						}
						switch t.name {
							case "Slice":
								return macro {
									final _offset_ = ${e1}.getOffset();
									final index = (${e2} : GoInt).toBasic() + _offset_;
									final underlying = ${e1}.getUnderlying();
									var underlyingIndex = Go.toInterface((index : GoInt));
									new $p(() -> ${e1}.getUnderlying()[index], (v) -> ${e1}.getUnderlying()[index] = v, false, underlying, underlyingIndex);
								};
							case "GoArray":
								return macro {
									final underlying = ${e1}.toVector();
									final underlyingIndex = Go.toInterface((${e2} : GoInt));
									new $p(() -> $expr, (v) -> $expr = v, false, underlying, underlyingIndex);
								}
						}
					default:
				}
			default:
				declare = true;
		}
		if (declare)
			return macro {
				var e = $expr;
				new $p(() -> e, (v) -> e = v, $v{hasSet});
			};
		return macro new $p(() -> $expr, (__tmp__) -> $expr = __tmp__, $v{hasSet});
	}

	public static macro function recover() {
		return untyped macro {
			var r = recover_exception != null ? stdgo.runtime.Runtime.newRuntime(recover_exception.toString()) : null;
			recover_exception = null;
			r;
		}
	}

	public static macro function cfor(cond, post, expr) {
		#if !display
		var func = null;
		func = function(expr:haxe.macro.Expr) {
			return switch (expr.expr) {
				case EContinue: macro {$post; $expr;}
				case EWhile(_, _, _): expr;
				case ECall(macro cfor, _): expr;
				case EFor(_): expr;
				// case EIn(_): expr;
				default: haxe.macro.ExprTools.map(expr, func);
			}
		}
		expr = func(expr);
		#end
		var exprMacro = macro {
			while ($cond) {
				$expr;
				$post;
			}
		};
		return exprMacro;
	}

	#if macro
	// reflect decode
	private static function gtParams(params:Array<haxe.macro.Type>, marked:Map<String, Bool>):Array<Expr> {
		var pTypes = [];
		for (i in 0...params.length) {
			final param = Context.follow(params[i]);
			pTypes.push(gtDecode(param, null, marked));
		}
		return pTypes;
	}

	public static function gtDecode(t:haxe.macro.Type, expr:Expr = null, marked:Map<String, Bool>):Expr {
		final marked = marked.copy();
		var ret = macro stdgo.reflect.Reflect.GoType.invalidType;
		switch (t) {
			case TType(t, params):
				final name = t.get().name;
				switch name {
					case "GoUnTypedInt":
						ret = macro stdgo.reflect.Reflect.GoType.basic(untyped_int_kind);
					case "GoUnTypedFloat":
						ret = macro stdgo.reflect.Reflect.GoType.basic(untyped_float_kind);
					case "GoUnTypedComplex":
						ret = macro stdgo.reflect.Reflect.GoType.basic(untyped_complex_kind);
					case "GoRune":
						ret = macro stdgo.reflect.Reflect.GoType.basic(int32_kind);
					case "GoByte":
						ret = macro stdgo.reflect.Reflect.GoType.basic(uint8_kind);
					default:
						Context.error("unknown typedef: " + t.toString() + " " + name, Context.currentPos());
				}
			case TMono(ref):
				return macro stdgo.reflect.Reflect.GoType.basic(unsafepointer_kind);
			case TAbstract(ref, params):
				var sref:String = ref.toString();
				switch (sref) {
					case "stdgo.Slice":
						ret = macro stdgo.reflect.Reflect.GoType.sliceType($a{gtParams(params, marked)});
					case "stdgo.GoArray":
						var len = macro - 1;
						if (expr != null)
							len = macro($expr : GoArray<Dynamic>).length.toBasic();
						ret = macro stdgo.reflect.Reflect.GoType.arrayType(${gtParams(params, marked)[0]},
							$len); // TODO go2hx does not store the length in the type
					case "stdgo.Pointer":
						ret = macro stdgo.reflect.Reflect.GoType.pointer($a{gtParams(params, marked)});
					case "stdgo.UnsafePointer", "stdgo.Unsafe.UnsafePointer", "stdgo.unsafe.UnsafePointer":
						return macro stdgo.reflect.Reflect.GoType.basic(unsafepointer_kind);
					case "stdgo.GoMap":
						var ps = gtParams(params, marked);
						ret = macro stdgo.reflect.Reflect.GoType.mapType($a{ps});
					case "haxe.Rest":
						ret = macro stdgo.reflect.Reflect.GoType.slice($a{gtParams(params, marked)});
					case "stdgo.GoInt8":
						ret = macro stdgo.reflect.Reflect.GoType.basic(int8_kind);
					case "stdgo.GoInt16":
						ret = macro stdgo.reflect.Reflect.GoType.basic(int16_kind);
					case "stdgo.GoInt32":
						ret = macro stdgo.reflect.Reflect.GoType.basic(int32_kind);
					case "stdgo.GoInt", "Int":
						ret = macro stdgo.reflect.Reflect.GoType.basic(int_kind);
					case "stdgo.GoInt64":
						ret = macro stdgo.reflect.Reflect.GoType.basic(int64_kind);
					case "stdgo.GoUInt8":
						ret = macro stdgo.reflect.Reflect.GoType.basic(uint8_kind);
					case "stdgo.GoUInt16":
						ret = macro stdgo.reflect.Reflect.GoType.basic(uint16_kind);
					case "stdgo.GoUInt":
						ret = macro stdgo.reflect.Reflect.GoType.basic(uint_kind);
					case "stdgo.GoUInt32":
						ret = macro stdgo.reflect.Reflect.GoType.basic(uint32_kind);
					case "stdgo.GoUInt64":
						ret = macro stdgo.reflect.Reflect.GoType.basic(uint64_kind);
					case "stdgo.GoString", "String":
						ret = macro stdgo.reflect.Reflect.GoType.basic(string_kind);
					case "stdgo.GoComplex64":
						ret = macro stdgo.reflect.Reflect.GoType.basic(complex64_kind);
					case "stdgo.GoComplex128":
						ret = macro stdgo.reflect.Reflect.GoType.basic(complex128_kind);
					case "stdgo.ComplexType":
						ret = macro stdgo.reflect.Reflect.GoType.basic(complex128_kind);
					case "stdgo.GoFloat32":
						ret = macro stdgo.reflect.Reflect.GoType.basic(float32_kind);
					case "stdgo.GoFloat64", "Float":
						ret = macro stdgo.reflect.Reflect.GoType.basic(float64_kind);
					case "stdgo.FloatType":
						ret = macro stdgo.reflect.Reflect.GoType.basic(float64_kind);
					case "Bool":
						ret = macro stdgo.reflect.Reflect.GoType.basic(bool_kind);
					case "stdgo.AnyInterface":
						ret = macro stdgo.reflect.Reflect.GoType.interfaceType(true);
					case "stdgo.GoUIntptr":
						ret = macro stdgo.reflect.Reflect.GoType.basic(uintptr_kind);
					case "haxe.Function":
						ret = macro stdgo.reflect.Reflect.GoType.signature(false, [], [], stdgo.reflect.Reflect.GoType.invalidType);
					case "Void":
						ret = macro stdgo.reflect.Reflect.GoType.invalidType; // Currently no value is supported for Void however in the future, there will be a runtime value to match to it. HaxeFoundation/haxe-evolution#76
					default: // used internally such as reflect.Kind
						Context.error('unknown abstract type: $sref', Context.currentPos());
				}
			case TInst(ref, params):
				final refString = ref.toString();
				var ref = ref.get();
				if (!marked.exists(refString)) {
					marked[refString] = true;
					if (params.length == 1 && ref.pack.length == 1 && ref.pack[0] == "stdgo" && ref.name == "Chan") {
						var param = gtParams(params, marked)[0];
						ret = macro stdgo.reflect.Reflect.GoType.chanType(0, $param);
					} else {
						if (ref.isInterface) {
							ret = gtDecodeInterfaceType(ref, marked);
						} else {
							if (ref.meta.has(":named")) {
								var type:haxe.macro.Type = null;
								for (field in ref.fields.get()) {
									if (field.name == "__t__") {
										type = field.type;
										break;
									}
								}
								if (type == null)
									Context.error("unable to find __t__ type", Context.currentPos());
								var interfaces:Array<Expr> = [];
								var path = ref.module;
								ret = macro stdgo.reflect.Reflect.GoType.named($v{path}, [], $a{interfaces}, ${gtDecode(type, null, marked)});
							} else {
								ret = gtDecodeClassType(ref, marked);
							}
						}
					}
				} else {
					var name = parseModule(ref.module) + "." + ref.name;
					ret = macro stdgo.reflect.Reflect.GoType.previouslyNamed($v{name});
				}
			case TAnonymous(a):
				var a = a.get();
				a.fields.sort((a, b) -> {
					return haxe.macro.Context.getPosInfos(a.pos).min - haxe.macro.Context.getPosInfos(b.pos).min;
				});
				var fields = [];
				for (field in a.fields) {
					var t = gtDecode(field.type, null, marked);
					var name:Expr = macro $v{field.name};
					final embedded = field.meta.has(":embedded") ? macro true : macro false;
					fields.push(macro {
						name: $name,
						tag: "",
						embedded: $embedded,
						type: $t
					});
				}
				var fields = macro $a{fields};
				ret = macro stdgo.reflect.Reflect.GoType.structType($fields);
			case TFun(a, result):
				var args = [];
				for (arg in a) {
					args.push(gtDecode(arg.t, null, marked));
				}
				var results = []; // TODO handle multi return
				var isVoid = false;
				switch result {
					case TAbstract(t, params):
						if (t.toString() == "Void") isVoid = true;
					default:
				}
				if (!isVoid)
					results.push(gtDecode(result, null, marked));
				var variadic = macro false;
				var recv = macro stdgo.reflect.Reflect.GoType.invalidType;
				// TODO
				ret = macro stdgo.reflect.Reflect.GoType.signature($variadic, $a{args}, $a{results}, $recv);
			case TDynamic(t):
				ret = macro stdgo.reflect.Reflect.GoType.interfaceType(true);
			case TLazy(f):
				ret = gtDecode(f(), null, []);
			case TEnum(_, _):
				ret = macro stdgo.reflect.Reflect.GoType.invalidType;
			default:
				Context.error('reflect.cast_AnyInterface - unhandled typeof $t', Context.currentPos());
		}
		return ret;
	}

	static function createPath(pack:Array<String>, name:String):String {
		return pack.join(".") + "." + name;
	}

	static function gtDecodeInterfaceType(ref:haxe.macro.Type.ClassType, marked:Map<String, Bool>):Expr {
		var methods:Array<Expr> = [];
		var fields = ref.fields.get();
		for (method in fields) {
			switch method.name {
				case "__underlying__":
					continue;
				default:
			}
			methods.push(macro {name: $v{method.name}, type: ${gtDecode(method.type, null, marked)}});
		}
		var path = createPath(ref.pack, ref.name);
		var empty = methods.length == 0 ? macro true : macro false;
		return macro stdgo.reflect.Reflect.GoType.interfaceType($empty, $v{path}, $a{methods});
	}

	static function gtDecodeClassType(ref:haxe.macro.Type.ClassType, marked:Map<String, Bool>):Expr {
		var methods:Array<Expr> = [];
		var fields:Array<Expr> = [];
		var interfaces = [];
		if (ref.module == "String")
			return macro stdgo.reflect.Reflect.GoType.basic(string_kind);
		for (inter in ref.interfaces) {
			var inter = inter.t.get();
			interfaces.push(gtDecodeInterfaceType(inter, marked));
		}
		var fs = ref.fields.get();
		var underlyingType:haxe.macro.Type = null;
		var module = parseModule(ref.module);
		for (field in fs) {
			switch field.kind {
				case FMethod(k):
					switch field.name {
						case "new", "__copy__", "__underlying__", "__t__":
							continue;
					}
					switch field.type {
						case TLazy(f):
							continue;
						default:
					}
					switch field.type {
						case TFun(args, ret):
							var params = [];
							var rets = [];
							for (arg in args) {
								params.push(gtDecode(arg.t, null, marked));
							}
							switch ret {
								case TAnonymous(a):
									var fs = a.get().fields;
									for (f in fs) {
										final embedded = f.meta.has(":embedded");
										rets.push(macro stdgo.reflect.Reflect.GoType.field(f.name, gtDecode(f.type), "", embedded));
									}
								default:
									if (field.name == "toString") {
										switch ret {
											case TInst(t, params):
												var t = t.get();
												if (t.name == "String") continue;
											default:
										}
									}
									rets.push(gtDecode(ret, null, marked));
							}
							final embedded = field.meta.has(":embedded") ? macro true : macro false;
							params.unshift(macro stdgo.reflect.Reflect.GoType.field("this",
								stdgo.reflect.Reflect.GoType.previouslyNamed($v{module} + "." + $v{ref.name}), "", false)); // recv
						default:
							Context.error("method needs to be a function: " + field.type, Context.currentPos());
					}
				default:
					if (field.name == "__t__") {
						underlyingType = field.type;
						continue;
					}
					var t = gtDecode(field.type, null, marked);
					final embedded = field.meta.has(":embedded") ? macro true : macro false;
					final tag = field.meta.has(":tag") ? field.meta.extract(":tag")[0].params[0] : macro "";
					fields.push(macro new stdgo.reflect.Reflect.FieldType($v{field.name}, $t, $tag, $embedded));
			}
		}
		var fields = macro $a{fields};
		var t = macro stdgo.reflect.Reflect.GoType.structType($fields);
		if (ref.meta.has(":named") && underlyingType != null) {
			t = gtDecode(underlyingType, null, marked);
		}
		var path = createPath(ref.pack, ref.name);
		return macro stdgo.reflect.Reflect.GoType.named($v{path}, $a{methods}, $a{interfaces}, $t);
	}
	#end

	public static macro function setKeys(expr:Expr) {
		var t = Context.toComplexType(Context.getExpectedType());
		return macro($expr : $t);
	}

	public static macro function multireturn(expr:Expr):Expr {
		function getFields(t:ComplexType) {
			switch t {
				case TAnonymous(fields):
					fields.sort((a, b) -> {
						return Context.getPosInfos(a.pos).min - Context.getPosInfos(b.pos).min;
					});
					return fields;
				default:
					Context.error('not anon type: $t', Context.currentPos());
			}
			return [];
		}
		function parens(expr) {
			return switch expr.expr {
				case EParenthesis(e): parens(e);
				default: expr;
			}
		}
		expr = parens(expr);
		switch expr.expr {
			case ECheckType(e, t):
				var fields2 = getFields(t);
				var t = Context.toComplexType(Context.typeof(e));
				var fields = getFields(t);
				var struct = {
					expr: EObjectDecl([
						for (i in 0...fields.length) {
							var fieldName = fields[i].name;
							{
								field: fields2[i].name,
								expr: macro obj.$fieldName,
							};
						}
					]),
					pos: Context.currentPos()
				};
				return macro {
					var obj = $e;
					$struct;
				}
			default:
		}
		return macro null;
	}

	private static function parseModule(module:String):String {
		var index = module.lastIndexOf(".");
		var name = module.substr(index + 1);
		module = module.substr(0, index);
		module = module.substr(module.lastIndexOf(".") + 1);
		if (module == name.charAt(0).toLowerCase() + name.substr(1))
			module = "main";
		return module;
	}
}
