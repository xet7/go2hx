package std;
using Lambda;
import haxe.macro.Context;
class Macro {
    macro static public function initLocals():Expr {
        // Grab the variables accessible in the context the macro was called.
        var locals = Context.getLocalVars();
        var fields = Context.getLocalClass().get().fields.get();
        var exprs:Array<Expr> = [];
        for (local in locals.keys()) {
        if (fields.exists(function(field) return field.name == local)) {
            exprs.push(macro this.$local = $i{local});
        } else {
            throw new Error(Context.getLocalClass() + " has no field " + local, Context.currentPos());
        }
        }
        // Generates a block expression from the given expression array 
        return macro $b{exprs};
    }
    public static macro function intEnum():Array<Field> {
		switch (Context.getLocalClass().get().kind) {
			case KAbstractImpl(_.get() => { type: TAbstract(_.get() => { name: "Int" }, _) }):
			default: Context.error(
				"This macro should only be applied to abstracts with base type Int",
				Context.currentPos());
		}
		var fields:Array<Field> = Context.getBuildFields();
		var nextIndex:Int = 0;
		for (field in fields) {
			switch (field.kind) {
				case FVar(t, { expr: EConst(CInt(i)) }): { // `var some = 1;`
					nextIndex = Std.parseInt(i) + 1;
				};
				case FVar(t, null): { // `var some;`
					var expr = EConst(CInt(Std.string(nextIndex++)));
					field.kind = FVar(t, { expr: expr, pos: field.pos });
				};
				default:
			}
		}
		return fields;
	}
}