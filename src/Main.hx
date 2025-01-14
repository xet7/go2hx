// ! -lib hxnodejs
package;

import Typer.DataType;
import haxe.Json;
import haxe.Resource;
import haxe.io.Bytes;
import haxe.io.Path;
import hl.uv.Loop;
import hl.uv.Stream;
import hl.uv.Tcp;
import shared.Util;
import stdgo.StdGoTypes;
import sys.FileSystem;
import sys.io.File;
import sys.io.Process;

final cwd = Sys.getCwd();
final loop = hl.uv.Loop.getDefault();
final server = new Tcp(loop);
var clients:Array<Client> = [];
var processes:Array<Process> = [];
var onComplete:(modules:Array<Typer.Module>, data:Dynamic) -> Void = null;
var mainThread = sys.thread.Thread.current();

@:structInit
class Client {
	public var stream:Stream;
	public var runnable:Bool = true; // start out as true
	public var data:Dynamic = null;
	public var id:Int = 0;

	public function new(stream, id) {
		this.stream = stream;
		this.id = id;
	}
}

function main() {
	var args = Sys.args();
	// args = ["-test", "time", Sys.getCwd()];
	run(args);
}

var printGoCode = false;
var localPath = "";
var target = "";
var targetOutput = "";
var libwrap = false;
var outputPath:String = "";
var hxmlPath:String = "";
var test:Bool = false;
final passthroughArgs = ["-test"];

function run(args:Array<String>) {
	outputPath = "golibs";
	var help = false;
	final argHandler = Args.generate([
		["-help", "--help", "-h", "--h"] => () -> help = true, @doc("go test")
		["-test", "--test"] => () -> test = true,
		@doc("set output path or file location")
		["-output", "--output", "-o", "--o", "-out", "--out"] => out -> {
			outputPath = out;
		},
		@doc("generate hxml from target command")
		["-hxml", "--hxml"] => out -> {
			hxmlPath = out;
		},
		@doc("add go code as a comment to the generated Haxe code")
		["-printgocode", "--printgocode"] => () -> printGoCode = true,
		@doc("all non main packages wrapped as a haxelib library to be used\n\nTarget:")
		["-libwrap", "--libwrap"] => () -> libwrap = true,
		@doc('generate C++ code into target directory')
		["-cpp", "--cpp"] => out -> {
			target = "cpp";
			targetOutput = out;
		},
		@doc('generate JavaScript code into target file')
		["-js", "--js", ] => out -> {
			target = "js";
			targetOutput = out;
		},
		@doc('generate JVM bytecode into target file')
		["-jvm", "--jvm", "-java", "--java"] => out -> {
			target = "jvm";
			targetOutput = out;
		},
		@doc('generate Python code into target file')
		["-python", "--python"] => out -> {
			target = "python";
			targetOutput = out;
		},
		@doc('generate Lua code into target file')
		["-lua", "--lua"] => out -> {
			target = "lua";
			targetOutput = out;
		},
		@doc('generate C# code into target directory')
		["-cs", "--cs"] => out -> {
			target = "cs";
			targetOutput = out;
		},
		@doc('generate HashLink .hl bytecode or .c code into target file')
		["-hl", "--hl", "-hashlink", "--hashlink"] => out -> {
			target = "hl";
			targetOutput = out;
		},
		@doc('interpret the program using internal macro system')
		["-eval", "--eval", "-interp", "--interp"] => () -> {
			target = "interp";
		}
	]);
	argHandler.parse(args);
	for (option in argHandler.options) {
		if (passthroughArgs.indexOf(option.flags[0]) != -1)
			continue;
		for (i in 0...args.length) {
			if (option.flags.indexOf(args[i]) != -1) {
				args.remove(args[i]);
				for (j in 0...option.args.length)
					args.remove(args[i]);
			}
		}
	}
	var maxLength = 0;
	if (help) {
		printDoc(argHandler);
		close();
		return;
	}
	setup(0, 1, () -> {
		onComplete = (modules, data) -> {
			close();
		};
		if (args.length <= 1) {
			Repl.init();
		} else {
			compile(args);
		}
	}, outputPath);
	while (true)
		update();
}

private function printDoc(handler:Args.ArgHandler) {
	successMsg("go2hx");
	Sys.print("\n");
	final max = 20;
	for (option in handler.options) {
		if (option.doc == null)
			continue;
		Sys.println(StringTools.rpad(option.flags[0], " ", max) + option.doc);
	}
}

function update() {
	loop.run(NoWait);
	mainThread.events.progress();
	Sys.sleep(0.06); // wait
}

function close() {
	#if debug
	if (processes.length > 0) {
		processes[0].kill();
		try {
			while (true)
				Sys.println(processes[0].stdout.readLine());
		} catch (_) {}
	}
	#end
	for (process in processes)
		process.close();
	for (client in clients) {
		client.stream.write(Bytes.ofString("exit"));
		client.stream.close();
	}
	server.close();
	Sys.exit(0);
}

function setup(port:Int = 0, processCount:Int = 1, allAccepted:Void->Void = null, outputPath:String = "golibs") {
	if (port == 0)
		port = 6114 + Std.random(200); // random range in case port is still bound from before
	Typer.stdgoList = Json.parse(File.getContent("./stdgo.json")).stdgo;

	for (i in 0...processCount) {
		processes.push(new sys.io.Process("./go4hx", ['$port'], false));
	}
	Sys.println('listening on local port: $port');
	server.bind(new sys.net.Host("127.0.0.1"), port);
	server.noDelay(true);
	var index = 0;
	server.listen(0, () -> {
		final client:Client = {stream: server.accept(), id: index++};
		clients.push(client);
		var pos = 0;
		var buff:Bytes = null;
		function reset() {
			client.runnable = true;
			pos = 0;
			buff = null;
		}
		client.stream.readStart(bytes -> {
			if (bytes == null) {
				// health check
				for (proc in processes) {
					final code = proc.exitCode(false);
					if (code == null)
						continue;
					if (code != 0) {
						Sys.print(proc.stderr.readAll());
					}
				}
				// close as stream has broken
				trace("stream has broken");
				close();
				return;
			}
			if (buff == null) {
				final len:Int = haxe.Int64.toInt(bytes.getInt64(0));
				buff = Bytes.alloc(len);
				bytes = bytes.sub(8, bytes.length - 8);
			}
			buff.blit(pos, bytes, 0, bytes.length);
			pos += bytes.length;
			if (pos == buff.length) {
				var exportData:DataType = bson.Bson.decode(buff);
				var modules = [];
				modules = Typer.main(exportData, printGoCode);
				Sys.setCwd(localPath);
				outputPath = Path.addTrailingSlash(outputPath);
				var libs:Array<String> = [];
				reset();
				for (module in modules) {
					if (libwrap && !module.isMain) {
						Sys.setCwd(cwd);
						var name = module.name;
						var libPath = "libs/" + name + "/";
						Gen.create(libPath, module);
						Sys.command('haxelib dev $name $libPath');
						if (libs.indexOf(name) == -1)
							libs.push(name);
					} else {
						Gen.create(outputPath, module);
					}
				}
				runTarget(modules);
				onComplete(modules, client.data);
			}
		});
		if (index >= processCount && allAccepted != null)
			allAccepted();
	});
}

function targetLibs():String {
	final libs = switch target {
		case "jvm":
			["hxjava"];
		case "cs":
			["hxcs"];
		case "cpp":
			["hxcpp"];
		case "js":
			["hxnodejs"];
		default:
			[];
	}
	return [for (lib in libs) '-lib $lib'].join(' ');
}

private function runTarget(modules:Array<Typer.Module>) {
	if (test && target == "")
		target = "interp"; // default test target
	if (target == "")
		return;
	final mainPath = mainPath(modules);
	final libs = targetLibs();
	final commands = [
		'-cp $outputPath',
		'-main $mainPath',
		libs,
		'-lib go2hx',
		'--$target $targetOutput',
	];
	final command = "haxe " + commands.join(" ");
	if (hxmlPath != "")
		File.saveContent(hxmlPath, commands.join("\n"));
	Sys.println(command);
	Sys.command(command);
}

function compile(args:Array<String>, data:Dynamic = null):Bool {
	if (localPath == "")
		localPath = args[args.length - 1];
	var httpsString = "https://";
	for (i in 0...args.length - 1) {
		var path = args[i];
		if (StringTools.startsWith(path, httpsString)) {
			path = path.substr(httpsString.length);
			args[i] = path;
		}
		if (Path.extension(path) == "go" || path.charAt(0) == "." || path.indexOf("/") == -1)
			continue;
		var command = 'go get $path';
		Sys.command(command);
	}
	return write(args, data);
}

function write(args:Array<String>, data:Dynamic):Bool {
	for (client in clients) {
		if (!client.runnable)
			continue;
		client.data = data;
		client.stream.write(Bytes.ofString(args.join(" ")));
		client.runnable = false;
		return true;
	}
	return false;
}
