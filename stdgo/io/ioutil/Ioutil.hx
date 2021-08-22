package stdgo.io.ioutil;

import haxe.io.Bytes;
import haxe.io.Path;
import stdgo.Io.Reader;
import stdgo.Os;
import stdgo.StdGoTypes;
import stdgo.internal.ErrorReturn;
import stdgo.internal.ErrorReturn;
import sys.FileSystem;
import sys.io.File;

function readAll(r:stdgo.Io.Reader)
	return stdgo.io.Io.readAll(r);

function readFile(filename:GoString) {}

function writeFile(filename:GoString, data:Bytes, ?perm:GoInt):Error {
	try {
		sys.io.File.saveBytes(filename, data);
		return null;
	} catch (e) {
		return cast e;
	}
}

function readDir(dirname:GoString):ErrorReturn<Slice<FileInfo>> {
	dirname = Path.addTrailingSlash(dirname);
	try {
		var array:Array<FileInfo> = [];
		for (path in FileSystem.readDirectory(dirname)) {}
		return {value: new Slice(...array)};
	} catch (e) {
		return {value: null, error: cast e};
	}
}

function close() {}
function nopCloser(r:Reader) {}
function write(p:Bytes) {}
function writeString(s:GoString) {}
function readFrom(r:Reader) {}
function tempFile(dir:GoString) {}
function tempDir(dir:GoString) {}