package stdgo.fmt;

import haxe.Int64;
import haxe.Rest;
import haxe.io.BufferInput;
import haxe.macro.Expr;
import stdgo.Error;
import stdgo.StdGoTypes.AnyInterface;
import stdgo.StdGoTypes.GoByte;
import stdgo.StdGoTypes.GoInt;
import stdgo.StdGoTypes.GoRune;
import stdgo.io.Io.Writer;

interface Formatter {
	public function format(_f:State, _verb:GoRune):Void;
	public function __underlying__():AnyInterface;
}

interface Scanner {
	public function scan(_state:ScanState, _verb:GoRune):Error;
	public function __underlying__():AnyInterface;
}

interface ScanState {
	public function readRune():{var _r:GoRune; var _size:GoInt; var _err:Error;};
	public function unreadRune():Error;
	public function skipSpace():Void;
	public function token(_skipSpace:Bool, _f:GoRune->Bool):{var _token:Slice<GoByte>; var _err:Error;};
	public function width():{var _wid:GoInt; var _ok:Bool;};
	public function read(_buf:Slice<GoByte>):{var _n:GoInt; var _err:Error;};
	public function __underlying__():AnyInterface;
}

interface State {
	public function write(_b:Slice<GoByte>):{var _n:GoInt; var _err:Error;};
	public function width():{var _wid:GoInt; var _ok:Bool;};
	public function precision():{var _prec:GoInt; var _ok:Bool;};
	public function flag(_c:GoInt):Bool;
	public function __underlying__():AnyInterface;
}

interface Stringer {
	public function __underlying__():AnyInterface;
	function toString():GoString;
}

interface GoStringer {
	public function __underlying__():AnyInterface;
	function goString():GoString;
}

inline function errorf(fmt:GoString, args:Rest<AnyInterface>) {
	return stdgo.errors.Errors.new_(format(fmt, args));
}

function println(args:Rest<Dynamic>):{_n:Int, _err:Error} {
	log(parse(args).join(" ") + "\n");
	return {_n: 0, _err: null};
}

function print(args:Rest<Dynamic>):{_n:Int, _err:Error} {
	log(parse(args).join(""));
	return {_n: 0, _err: null};
}

inline function printf(fmt:GoString, args:Rest<AnyInterface>) { // format
	log(format(fmt, args));
}

inline function fprintf(w:Writer, fmt:GoString, args:Rest<Dynamic>) {}
inline function fprintln(w:Writer, args:Rest<Dynamic>) {}
inline function fprint(w:Writer, args:Rest<Dynamic>) {}

inline function sprint(args:Rest<Dynamic>):GoString {
	return parse(args).join(" ");
}

function sprintln(args:Rest<Dynamic>):GoString {
	return parse(args).join(" ") + "\n";
}

private function parse(args:Array<Dynamic>):Array<String> {
	return [
		for (i in 0...args.length) {
			Go.string(args[i]);
		}
	];
}

inline function sprintf(fmt:GoString, args:Rest<AnyInterface>):GoString { // format
	return format(fmt, args);
}

private function format(fmt:GoString, args:Array<AnyInterface>):GoString {
	var i = 0;
	var c = 0;
	var n = 0;
	final fmt:String = fmt;
	inline function isDigit(x)
		return x >= 48 && x <= 57;
	inline function next()
		c = StringTools.fastCodeAt(fmt, i++);
	var buf = new StringBuf();
	var k = fmt.length;
	var argIndex = 0;
	while (i < k) {
		next();
		if (c == "%".code) {
			next();
			if (c == "%".code) {
				buf.addChar(c);
				continue;
			}
			switch c {
				case ".".code:
					next();
				case "#".code: // alternative format
					next();
				case "+".code: // always print a sign for numeric values ASCII only output for %+q
					next();
				case "-".code: // pad with spaces on the right rather than the left
					next();
				case " ".code: // leave a space for elided sign in numbers, or put spaces between bytes or slices in hex
					next();
				case "0".code: // pad with leading zeros for numbers, padding after the sign
					next();
			}
			if ([for (i in 0...10) '$i'.charCodeAt(0)].indexOf(c) != -1)
				next();
			if (args[argIndex] == null) {
				buf.add("null");
				argIndex++;
			} else {
				switch c {
					case "T".code: // go type
						buf.add(args[argIndex++].type.toString());
					case "v".code: // default format, plus flag adds field names
						buf.add(Go.string(args[argIndex++].value));
					case "d".code: // int(x)/uint(x) etc
						buf.add(Go.string(args[argIndex++].value));
					case "g".code: // float32/complex64 etc
						buf.add(Go.string(args[argIndex++].value));
					case "s".code: // string
						buf.add(Go.string(args[argIndex++].value));
					case "p".code: // pointer/chan
						buf.add(Go.string(args[argIndex++].value));
					case "t".code: // true or false
						buf.add(Go.string(args[argIndex++].value));
					case "b".code: // int base 2
						buf.add(Go.string(args[argIndex++].value));
					case "o".code: // int base 8
						buf.add(Go.string(args[argIndex++].value));
					case "q".code: // charachter literal
						buf.add(Go.string(args[argIndex++].value));
					case "x".code: // int base 16 lower case letters
						buf.add(Go.string(args[argIndex++].value));
					case "X".code: // based 16 upper case letters
						buf.add(Go.string(args[argIndex++].value));
					case "U".code: // unicode format
						buf.add(Go.string(args[argIndex++].value));
					case "f".code: // float point
						buf.add(Go.string(args[argIndex++].value));
					default:
						buf.addChar(c);
				}
			}
		} else {
			buf.addChar(c);
		}
	}
	return buf.toString();
}

private inline function log(v:Dynamic) {
	#if sys
	#if test
	Sys.print(v);
	#else
	// unicode support for hashlink thanks to Zeta
	Sys.stdout().writeString(Std.string(v));
	#end
	#elseif js
	js.html.Console.log(v);
	#end
}
