import haxe.Timer;
import hscript.Interp;
import hscript.Parser;

class PerfTest {
	static function main() {
		var parser = new Parser();
		parser.allowTypes = true;

		var testScript = "
			var sum = 0;
			var a = 1;
			var b = 2;
			var c = 3;
			for (i in 0...10000) {
				sum = sum + a * b + c - a / b;
				a = a + 1;
				b = b + 1;
				c = c + 1;
				if (sum > 1000000) sum = 0;
				if (a > 100) a = 1;
				if (b > 200) b = 2;
				if (c > 300) c = 3;
			}
			sum;
		";

		var program = parser.parseString(testScript);

		var interp = new Interp();
		interp.variables.set("Math", Math);

		var iterations = 100;

		Sys.println("=== Fast Binops (switch) Mode ===");

		var totalTests = 5;
		var times:Array<Float> = [];

		for (testNum in 0...totalTests) {
			var interp = new Interp();
			interp.variables.set("Math", Math);

			var startTime = Timer.stamp();
			for (i in 0...iterations) {
				interp.execute(program);
			}
			var endTime = Timer.stamp();
			var elapsed = endTime - startTime;
			times.push(elapsed);
			Sys.println('Test ${testNum + 1}: ${Std.string(elapsed * 1000).substr(0, 8)} ms');
		}

		var avg = Lambda.fold(times, function(a, b) return a + b, 0.0) / times.length;
		var minTime = Lambda.fold(times, function(a, b) return a < b ? a : b, times[0]);
		var maxTime = Lambda.fold(times, function(a, b) return a > b ? a : b, times[0]);

		Sys.println("");
		Sys.println('Average: ${Std.string(avg * 1000).substr(0, 8)} ms');
		Sys.println('Min: ${Std.string(minTime * 1000).substr(0, 8)} ms');
		Sys.println('Max: ${Std.string(maxTime * 1000).substr(0, 8)} ms');
	}
}
