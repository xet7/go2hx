package stdgo;

import stdgo.StdGoTypes.AnyInterface;
import stdgo.StdGoTypes.Error;
import stdgo.StdGoTypes.GoByte;
import stdgo.StdGoTypes.GoFloat64;
import stdgo.StdGoTypes.GoFloat;
import stdgo.StdGoTypes.GoInt64;
import stdgo.StdGoTypes.GoInt;
import stdgo.StdGoTypes.GoUInt64;
import stdgo.internal.ErrorReturn;

function parseFloat(s:GoString, bitSize:GoInt64):ErrorReturn<GoFloat> {
	try {
		return {v0: Std.parseFloat(s.toString())};
	} catch (e) {
		return {v0: 0, v1: cast e};
	}
}

inline function unquote(s:GoString):ErrorReturn<GoString> {
	if (s.length < 2)
		return {v0: "", v1: errSyntax};
	s = s.substr(1, s.length.toBasic() - 2);
	return {v0: s, v1: null};
}

inline function parseInt(s:GoString, base:GoInt64, bitSize:GoInt64):ErrorReturn<GoInt> {
	try {
		var value = Std.parseInt(s);
		if (value == null)
			return {v0: 0, v1: stdgo.Errors.new_('parsing "$s": invalid syntax')};
		return {v0: value};
	} catch (e) {
		if (s.substr(0, 2) == "0x")
			return parseInt(s.substr(2), 0, 0);
		return {v0: 0, v1: cast e};
	}
}

inline function parseBool(s:GoString):ErrorReturn<Bool> {
	return switch s.toString() {
		case "1", "t", "T", "true", "TRUE", "True":
			{v0: true};
		case "0", "f", "F", "false", "FALSE", "False":
			{v0: false};
		default:
			{v0: false, v1: syntaxError("parseBool", s)};
	}
}

inline function formatBool(b:Bool):GoString
	return b ? "true" : "false";

inline function formatInt(i:GoInt64, base:GoInt):GoString {
	return '$i';
}

inline function formatUint(i:GoUInt64, base:GoInt):GoString {
	return '$i';
}

inline function formatFloat(i:GoFloat64, fmt:GoByte, prec:GoInt, bitSize:GoInt):GoString {
	return '$i';
}

final errRange = stdgo.Errors.new_("value out of range");
final errSyntax = stdgo.Errors.new_("invalid syntax");

private function syntaxError(fn:GoString, str:GoString):NumError {
	return new NumError(fn, str, errSyntax);
}

private function rangeError(fn:GoString, str:GoString):NumError {
	return new NumError(fn, str, errRange);
}

inline function parseUint(s:GoString, base:GoInt64, bitSize:GoInt64):ErrorReturn<GoInt> {
	return parseInt(s, base, bitSize);
}

// `Atoi` is a convenience function for basic base-10

inline function atoi(s:GoString) {
	return parseInt(s, 0, 0);
}

inline function itoa(i:GoInt):GoString
	return '$i';

class NumError implements Error {
	public function __underlying__():AnyInterface
		return null;

	public var func:GoString;
	public var num:GoString;
	public var err:Error;

	public function new(func, num, err) {
		this.func = func;
		this.num = num;
		this.err = err;
	}

	public function error():GoString
		return this.err.error();

	public function unwrap():Error
		return this.err;
}

// final intSize:GoInt64 = "9223372036854775807";