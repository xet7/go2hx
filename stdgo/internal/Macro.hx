package stdgo.internal;

import haxe.macro.Compiler;
import haxe.macro.Context;
import haxe.macro.Expr.Field;
import haxe.macro.Expr;

using Lambda;

class Macro {
	public static macro function initLocals() {
		// Grab the variables accessible in the context the macro was called.
		var locals = Context.getLocalVars();
		var fields = Context.getLocalClass().get().fields.get();
		var exprs:Array<Expr> = [];
		for (local in locals.keys()) {
			if (fields.exists(function(field) return field.name == local)) {
				exprs.push(macro if ($i{local} != null) this.$local = $i{local});
			} else {
				throw new Error(Context.getLocalClass() + " has no field " + local, Context.currentPos());
			}
		}
		// Generates a block expression from the given expression array
		return macro $b{exprs};
	}

	public static macro function intEnum():Array<Field> {
		switch (Context.getLocalClass().get().kind) {
			case KAbstractImpl(_.get() => {type: TAbstract(_.get() => {name: "Int"}, _)}):
			default:
				Context.error("This macro should only be applied to abstracts with base type Int", Context.currentPos());
		}
		var fields:Array<Field> = Context.getBuildFields();
		var nextIndex:Int = 0;
		for (field in fields) {
			switch (field.kind) {
				case FVar(t, {expr: EConst(CInt(i))}):
					{ // `var some = 1;`
						nextIndex = Std.parseInt(i) + 1;
					};
				case FVar(t, null):
					{ // `var some;`
						var expr = EConst(CInt(Std.string(nextIndex++)));
						field.kind = FVar(t, {expr: expr, pos: field.pos});
					};
				default:
			}
		}
		return fields;
	}

	public static macro function pointer(expr) {
		var isRealPointer = false;
		var type = Context.follow(Context.typeof(expr));
		switch type {
			case TMono(t):
				type = t.get();
			default:
		}
		if (type == null)
			return macro null;
		switch type {
			case TAbstract(t, params):
				var t = t.get();
				if (isNumber(t.name)) {
					isRealPointer = true;
				}else{
					switch t.name {
						case "GoString","String","Bool","Slice","Map","Array","GoArray":
							isRealPointer = true;
					}
				}
			case TAnonymous(a):
			case TInst(t, params):
			default:
				trace("unknown make pointer type: " + type);
		}
		if (isRealPointer)
			return {expr: EObjectDecl([
				{
					field: "obj",
					expr: null,
				},
				{
					field: "get",
					expr: macro () -> $expr,
				},
				{
					field: "set",
					expr: macro (v) -> $expr = v,
				},
			]),pos: Context.currentPos()};
		return {expr: EObjectDecl([
			{
				field: "obj",
				expr: expr,
			},
			{
				field: "get",
				expr: macro null,
			},
			{
				field: "set",
				expr: macro null,
			},
		]),pos: Context.currentPos()};
	}

	public static function isNumber(name:String):Bool {
		return switch name {
			case "Int","Int8","Int16","Int32","Int64","UInt","UInt8","UInt16","UInt32","UInt64","Complex64","Complex128","Float":
				true;
			default:
				false;
		}
	}

	static function isHaxeStd(path:String):Bool {
		return [
			"cpp", "cs", "eval", "flash", "haxe", "hl", "java", "js", "jvm", "lua", "neko", "php", "python", "sys", "Any", "Array", "Class", "Date",
			"DateTools", "EReg", "Enum", "EnumValue", "IntIterator", "Lambda", "List", "Map", "Math", "Reflect", "Std", "StdTypes", "String", "StringBuf",
			"StringTools", "Sys", "Type", "UInt", "UnicodeString", "Xml", "_UInt", "_EnumValue", "_Any", "polygonal",

		].indexOf(path) > -1;
	}
}
